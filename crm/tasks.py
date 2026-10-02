from datetime import timedelta
from celery import shared_task
from django.db import transaction
from django.utils import timezone
from crm.models import Order, Transfer
from crm.services.notifications import create_notification


@shared_task
def send_reminders():
    now = timezone.now()
    for order in Order.objects.filter(status='CONFIRMED',start_at__gt=now,start_at__lte=now+timedelta(hours=1)).select_related('master__user'):
        create_notification(order.master.user,'ORDER_REMINDER','Заказ начнётся в течение часа',
            payload={'order_id':str(order.pk)},dedup_key=f'reminder:{order.pk}:{order.start_at.isoformat()}')


@shared_task
def expire_transfers():
    now = timezone.now()
    ids = list(Transfer.objects.filter(status='OFFERED',order__start_at__lte=now).values_list('order_id',flat=True).distinct())
    for order_id in ids:
        with transaction.atomic():
            Order.objects.select_for_update().get(pk=order_id)
            Transfer.objects.filter(order_id=order_id,status='OFFERED').update(status='EXPIRED',responded_at=now)
