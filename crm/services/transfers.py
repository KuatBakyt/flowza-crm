from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError, NotFound
from crm.models import Order, Transfer, MasterProfile, ScheduleBlock, OrderStatusHistory
from crm.errors import Conflict
from crm.locations import serves_territory
from .access import ensure_order_access, is_admin, profile
from .orders import locked_order_by_id, locked_order, validate_master, record_status
from .schedule import lock_masters, check_availability, create_order_block
from .notifications import create_notification

TRANSFERABLE = {'NEW','PENDING','CONFIRMED'}


def candidates(order):
    busy = ScheduleBlock.objects.filter(start_at__lt=order.end_at,end_at__gt=order.start_at).values_list('master_id',flat=True)
    masters = MasterProfile.objects.filter(is_available=True,user__is_active=True,
        skills__is_active=True,skills__specialization=order.specialization,
        skills__specialization__is_active=True).exclude(pk=order.master_id).exclude(pk__in=busy).distinct()
    # Filter territory before ranking; final UUID breaks ties.
    eligible = [m for m in masters if serves_territory(m, order.master, order.district)]
    return sorted(eligible,key=lambda m:(-m.internal_rating,-m.completed_orders_count,str(m.pk)))


@transaction.atomic
def offer(order, actor, reason=''):
    order = locked_order(order,actor)
    if order.status not in TRANSFERABLE or not order.master_id or order.start_at <= timezone.now():
        raise ValidationError('Заказ нельзя передать в текущем состоянии')
    transfer = next_offer(order, reason)
    if transfer is None:
        raise Conflict('Подходящий свободный мастер не найден',code='no_transfer_candidate')
    return transfer


def next_offer(order, reason=''):
    """Called only while the order row is locked; exhaustion is a valid result."""
    existing = Transfer.objects.filter(order=order,status='OFFERED').first()
    if existing:
        return existing
    excluded = set(Transfer.objects.filter(order=order,status='DECLINED').values_list('to_master_id',flat=True))
    for candidate in candidates(order):
        if candidate.pk in excluded:
            continue
        transfer = Transfer.objects.create(order=order,from_master=order.master,to_master=candidate,reason=reason)
        create_notification(candidate.user,'TRANSFER_OFFER','Новый заказ для передачи',payload={'transfer_id':str(transfer.pk),'order_id':str(order.pk)})
        return transfer
    return None


@transaction.atomic
def accept(transfer, actor):
    # All order services lock order first, then master rows in UUID order.
    order = locked_order_by_id(transfer.order_id)
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
    sender = next(m for m in locked if m.pk == transfer.from_master_id)
    if not serves_territory(recipient, sender, order.district):
        raise Conflict('Город или район заказа больше не соответствует территории мастера',
                       code='transfer_territory_conflict')
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
    order = locked_order_by_id(transfer.order_id)
    transfer = Transfer.objects.select_for_update().get(pk=transfer.pk)
    if not is_admin(actor) and transfer.to_master_id != profile(actor).pk:
        raise NotFound()
    if transfer.status != 'OFFERED':
        raise ValidationError('Отклонить можно только активное предложение')
    if order.status not in TRANSFERABLE or order.master_id != transfer.from_master_id or order.start_at <= timezone.now():
        raise ValidationError('Предложение больше не соответствует заказу')
    transfer.status = 'DECLINED'
    transfer.responded_at = timezone.now()
    transfer.save(update_fields=['status','responded_at'])
    create_notification(transfer.from_master.user,'TRANSFER_DECLINED','Передача отклонена',payload={'order_id':str(transfer.order_id)})
    following = next_offer(order, transfer.reason)
    if following is None:
        create_notification(order.master.user, 'TRANSFER_EXHAUSTED',
                            'Не найден мастер для передачи',
                            body='Все подходящие мастера отказались или недоступны. Заявка остаётся у вас.',
                            payload={'order_id': str(order.pk)},
                            dedup_key=f'transfer-exhausted:{transfer.pk}')
    return transfer
