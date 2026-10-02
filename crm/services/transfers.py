from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError, NotFound
from crm.models import Order, Transfer, MasterProfile, ScheduleBlock, OrderStatusHistory
from crm.errors import Conflict
from .access import ensure_order_access, is_admin, profile
from .orders import locked_order, validate_master, record_status
from .schedule import lock_masters, check_availability, create_order_block
from .notifications import create_notification

TRANSFERABLE = {'NEW','PENDING','CONFIRMED'}


def candidates(order):
    busy = ScheduleBlock.objects.filter(start_at__lt=order.end_at,end_at__gt=order.start_at).values_list('master_id',flat=True)
    masters = MasterProfile.objects.filter(is_available=True,user__is_active=True,
        skills__is_active=True,skills__specialization=order.specialization,
        skills__specialization__is_active=True).exclude(pk=order.master_id).exclude(pk__in=busy).distinct()
    # Exact district match, then rating, then completed work; final UUID breaks ties.
    eligible = [m for m in masters if m.city == order.master.city and (not m.districts or not order.district or order.district in m.districts)]
    return sorted(eligible,key=lambda m:(-m.internal_rating,-m.completed_orders_count,str(m.pk)))


@transaction.atomic
def offer(order, actor, reason=''):
    order = locked_order(order,actor)
    if order.status not in TRANSFERABLE or not order.master_id or order.start_at <= timezone.now():
        raise ValidationError('Заказ нельзя передать в текущем состоянии')
    # No to_master input: selection is always performed by the server.
    existing = Transfer.objects.filter(order=order,status='OFFERED').first()
    if existing:
        return existing
    excluded = set(Transfer.objects.filter(order=order,status='DECLINED').values_list('to_master_id',flat=True))
    for candidate in candidates(order):
        if candidate.pk in excluded:
            continue
        # Receiver's calendar is rechecked on acceptance, so offer itself doesn't reserve it.
        transfer = Transfer.objects.create(order=order,from_master=order.master,to_master=candidate,reason=reason)
        create_notification(candidate.user,'TRANSFER_OFFER','Новый заказ для передачи',payload={'transfer_id':str(transfer.pk),'order_id':str(order.pk)})
        return transfer
    raise Conflict('Подходящий свободный мастер не найден',code='no_transfer_candidate')


@transaction.atomic
def accept(transfer, actor):
    # All order services lock order first, then master rows in UUID order.
    order = Order.objects.select_for_update().get(pk=transfer.order_id)
    transfer = Transfer.objects.select_for_update().get(pk=transfer.pk)
    if not is_admin(actor) and transfer.to_master_id != profile(actor).pk:
        raise NotFound()
    if transfer.status != 'OFFERED':
        raise ValidationError('Принять можно только активное предложение')
    if order.status not in TRANSFERABLE or order.master_id != transfer.from_master_id:
        raise ValidationError('Предложение больше не соответствует заказу')
    if order.start_at <= timezone.now():
        raise ValidationError('Нельзя принять заказ в прошлом')
    locked = lock_masters(transfer.from_master_id,transfer.to_master_id)
    recipient = next(m for m in locked if m.pk == transfer.to_master_id)
    validate_master(recipient,order.specialization)
    if not recipient.is_available or not recipient.user.is_active:
        raise ValidationError('Мастер недоступен')
    if not check_availability(recipient.pk,order.start_at,order.end_at):
        raise Conflict('Время получателя уже занято',code='transfer_slot_conflict')
    old_user = transfer.from_master.user
    order.master = recipient
    create_order_block(order)  # Updates OneToOne block, releasing old master atomically.
    record_status(order,'CONFIRMED',actor,'Передача заказа')
    transfer.status = 'ACCEPTED'
    transfer.responded_at = timezone.now()
    transfer.save(update_fields=['status','responded_at'])
    Transfer.objects.filter(order=order,status='OFFERED').exclude(pk=transfer.pk).update(status='EXPIRED',responded_at=timezone.now())
    create_notification(old_user,'TRANSFER_ACCEPTED','Заказ передан',payload={'order_id':str(order.pk),'transfer_id':str(transfer.pk)})
    return transfer


@transaction.atomic
def decline(transfer, actor):
    Order.objects.select_for_update().get(pk=transfer.order_id)
    transfer = Transfer.objects.select_for_update().get(pk=transfer.pk)
    if not is_admin(actor) and transfer.to_master_id != profile(actor).pk:
        raise NotFound()
    if transfer.status != 'OFFERED':
        raise ValidationError('Отклонить можно только активное предложение')
    transfer.status = 'DECLINED'
    transfer.responded_at = timezone.now()
    transfer.save(update_fields=['status','responded_at'])
    create_notification(transfer.from_master.user,'TRANSFER_DECLINED','Передача отклонена',payload={'order_id':str(transfer.order_id)})
    return transfer
