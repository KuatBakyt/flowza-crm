"""Atomic, idempotent ingress for a bot attached to one master account."""
import hashlib
import json
from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import generics, serializers
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from accounts.models import User, normalize_phone
from crm.errors import Conflict
from crm.models import Client, Order
from .models import BotOrderReceipt
from crm.serializers import StrictSerializer, StrictModelSerializer
from crm.services.access import profile
from crm.services.notifications import create_notification
from crm.services.orders import create_order
from crm.services.schedule import lock_masters, require_available, validate_interval, within_working_hours


class BotClientInput(StrictSerializer):
    name = serializers.CharField(max_length=150)
    phone = serializers.CharField(max_length=30)
    external_id = serializers.CharField(max_length=150)

    def validate_phone(self, value):
        return normalize_phone(value)


class BotOrderInput(StrictModelSerializer):
    class Meta:
        model = Order
        fields = ['specialization', 'title', 'description', 'address', 'district', 'start_at', 'end_at']
        extra_kwargs = {'address': {'required': True, 'allow_blank': False},
                        'description': {'max_length': 2000}}

    def validate(self, data):
        validate_interval(data['start_at'], data['end_at'])
        return data


class BotSubmission(StrictSerializer):
    request_id = serializers.UUIDField()
    client = BotClientInput()
    order = BotOrderInput()


class BotResult(serializers.Serializer):
    id = serializers.UUIDField()
    client_id = serializers.UUIDField()
    status = serializers.CharField()
    replayed = serializers.BooleanField()


@transaction.atomic
def submit(actor, raw):
    # One stable row serializes retries and client upserts even on an empty database.
    actor = User.objects.select_for_update().get(pk=actor.pk)
    if actor.role != 'MASTER' or not actor.is_active:
        raise PermissionDenied('Бот должен использовать активный аккаунт мастера')
    envelope = BotSubmission(data=raw)
    # Check the envelope key before resolving current catalog relations: a retry remains
    # valid after its specialization is disabled or its order is transferred.
    request_id = serializers.UUIDField().run_validation(raw.get('request_id'))
    fingerprint = hashlib.sha256(json.dumps(
        {k: v for k, v in raw.items() if k != 'request_id'},
        sort_keys=True, ensure_ascii=False, separators=(',', ':')
    ).encode()).hexdigest()
    receipt = BotOrderReceipt.objects.filter(actor=actor, request_id=request_id).first()
    if receipt:
        if receipt.fingerprint != fingerprint:
            raise Conflict('Ключ запроса уже использован с другими данными', code='idempotency_conflict')
        return {**receipt.response, 'replayed': True}
    envelope.is_valid(raise_exception=True)
    data = envelope.validated_data
    master = profile(actor)
    master = lock_masters(master.pk)[0]
    if not master.is_available:
        raise ValidationError({'master': 'Мастер временно недоступен'})
    if not timezone.now() < data['order']['start_at'] <= timezone.now() + timedelta(days=365):
        raise ValidationError({'start_at': 'Выберите время в будущем в пределах 365 дней'})
    require_available(master.pk, data['order']['start_at'], data['order']['end_at'])
    if not within_working_hours(master, data['order']['start_at'], data['order']['end_at']):
        raise Conflict('Выберите время внутри рабочего графика мастера', code='outside_working_hours')
    customer = data['client']
    client = Client.objects.filter(created_by=actor, external_id=customer['external_id']).first()
    if client is None:
        client = Client.objects.create(created_by=actor, source='BOT', **customer)
    else:
        client.name, client.phone = customer['name'], customer['phone']
        client.save(update_fields=['name', 'phone'])
    order = create_order(actor, client=client, master=master, source='BOT', **data['order'])
    result = {'id': str(order.pk), 'client_id': str(client.pk), 'status': order.status}
    BotOrderReceipt.objects.create(actor=actor, request_id=request_id,
        fingerprint=fingerprint, order=order, response=result)
    create_notification(actor, 'BOT_ORDER', 'Новая заявка из Telegram',
        body=order.title, payload={'order_id': str(order.pk)}, dedup_key=f'bot-order:{order.pk}')
    return {**result, 'replayed': False}


class BotOrderView(generics.GenericAPIView):
    serializer_class = BotSubmission

    @extend_schema(responses={200: BotResult, 201: BotResult}, tags=['Bot'])
    def post(self, request):
        if not isinstance(request.data, dict):
            raise ValidationError('Ожидается JSON-объект')
        result = submit(request.user, request.data)
        return Response(result, status=200 if result['replayed'] else 201)
