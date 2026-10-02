from decimal import Decimal
from django.db import transaction
from django.db.models import F
from django.utils import timezone
from rest_framework.exceptions import ValidationError, NotFound
from crm.models import Order, OrderStatusHistory, ScheduleBlock, Transfer, MasterProfile, MasterSpecialization, Payment
from .access import ensure_order_access
from .schedule import lock_masters, validate_interval, create_order_block, require_available
from .notifications import create_notification

ACTIVE = {'CONFIRMED','IN_PROGRESS'}
TERMINAL = {'COMPLETED','PAID','CANCELLED_CLIENT','CANCELLED_MASTER','REFUNDED'}


def validate_master(master, specialization):
    if master and not MasterSpecialization.objects.filter(master=master,specialization=specialization,is_active=True,specialization__is_active=True).exists():
        raise ValidationError({'specialization':'Мастер не имеет активной специализации'})


def record_status(order, status, actor, note=''):
    old = order.status
    order.status = status
    order.save()
    OrderStatusHistory.objects.create(order=order,actor=actor,from_status=old,to_status=status,note=note)


def locked_order_by_id(order_id):
    try:
        return Order.objects.select_for_update().get(pk=order_id)
    except Order.DoesNotExist:
        raise NotFound("Заявка удалена или недоступна")


def locked_order(order, actor):
    order = locked_order_by_id(order.pk)
    ensure_order_access(order,actor)
    return order


def expire_offers(order):
    Transfer.objects.filter(order=order,status='OFFERED').update(status='EXPIRED',responded_at=timezone.now())


@transaction.atomic
def create_order(actor, **data):
    validate_interval(data['start_at'],data['end_at'])
    validate_master(data.get('master'),data['specialization'])
    if data.get('master'):
        lock_masters(data['master'].pk)
        require_available(data['master'].pk, data['start_at'], data['end_at'])
    order = Order.objects.create(**data)
    OrderStatusHistory.objects.create(order=order,actor=actor,to_status='NEW')
    if order.master_id and order.source != 'BOT':
        create_notification(order.master.user, 'ORDER_NEW', 'Новая заявка', body=order.title,
                            payload={'order_id': str(order.pk)}, dedup_key=f'new-order:{order.pk}')
    return order


@transaction.atomic
def edit_order(order, actor, data):
    order = locked_order(order,actor)
    if order.status not in {'NEW','PENDING','CONFIRMED'}:
        raise ValidationError('Заказ в этом статусе нельзя редактировать')
    if order.status in ACTIVE and {'start_at','end_at','master','specialization'} & data.keys():
        raise ValidationError('Для изменения времени используйте reschedule')
    validate_interval(data.get('start_at',order.start_at),data.get('end_at',order.end_at))
    validate_master(data.get('master',order.master),data.get('specialization',order.specialization))
    if {'start_at', 'end_at', 'master'} & data.keys():
        master = data.get('master', order.master)
        if master:
            lock_masters(master.pk)
            require_available(master.pk, data.get('start_at', order.start_at),
                data.get('end_at', order.end_at), exclude_order=order.pk)
    if {'start_at','end_at','master','specialization','district'} & data.keys():
        expire_offers(order)
    for key,value in data.items():
        setattr(order,key,value)
    order.save()
    return order


@transaction.atomic
def confirm_order(order, actor):
    order = locked_order(order,actor)
    if order.status not in {'NEW','PENDING','TRANSFERRED'}:
        raise ValidationError('Подтверждение невозможно из текущего статуса')
    if not order.master_id:
        raise ValidationError({'master':'Сначала назначьте мастера'})
    if order.start_at <= timezone.now():
        raise ValidationError({'start_at':'Нельзя подтвердить заказ в прошлом'})
    masters = lock_masters(order.master_id)
    if not masters[0].is_available or not masters[0].user.is_active:
        raise ValidationError({'master':'Мастер недоступен'})
    validate_master(order.master,order.specialization)
    create_order_block(order)
    record_status(order,'CONFIRMED',actor)
    return order


@transaction.atomic
def start_order(order, actor):
    order = locked_order(order,actor)
    if order.status != 'CONFIRMED':
        raise ValidationError('Начать можно только подтверждённый заказ')
    record_status(order,'IN_PROGRESS',actor)
    return order


@transaction.atomic
def complete_order(order, actor):
    order = locked_order(order,actor)
    if order.status not in ACTIVE:
        raise ValidationError('Завершить можно только подтверждённый/активный заказ')
    lock_masters(order.master_id)
    record_status(order,'COMPLETED',actor)
    # Keep the historical calendar block; completed work still occupied this interval.
    MasterProfile.objects.filter(pk=order.master_id).update(completed_orders_count=F('completed_orders_count')+1)
    expire_offers(order)
    return order


@transaction.atomic
def mark_paid(order, actor, final_price):
    order = locked_order(order,actor)
    if order.status == 'PAID' and order.final_price == final_price:
        return order
    if order.status != 'COMPLETED':
        raise ValidationError('Оплатить можно только завершённый заказ')
    received = payment_balance(order)
    if received > final_price:
        raise ValidationError({'final_price': 'Цена меньше уже полученной суммы'})
    if received < final_price:
        Payment.objects.create(order=order, amount=final_price-received, type='FULL', status='PAID')
    order.final_price = final_price
    record_status(order,'PAID',actor)
    return order


@transaction.atomic
def cancel_order(order, actor, reason, cancelled_by):
    order = locked_order(order,actor)
    if order.status in TERMINAL:
        raise ValidationError('Нельзя отменить завершённый/отменённый заказ')
    if order.master_id:
        lock_masters(order.master_id)
    order.cancellation_reason = reason
    record_status(order,'CANCELLED_'+cancelled_by,actor,reason)
    ScheduleBlock.objects.filter(order=order).delete()
    expire_offers(order)
    return order


@transaction.atomic
def reschedule_order(order, actor, new_start_at, new_end_at):
    order = locked_order(order,actor)
    if order.status not in {'NEW','PENDING','CONFIRMED'}:
        raise ValidationError('Перенос невозможен из текущего статуса')
    validate_interval(new_start_at,new_end_at)
    if new_start_at <= timezone.now():
        raise ValidationError({'new_start_at':'Нельзя перенести заказ в прошлое'})
    if order.master_id:
        lock_masters(order.master_id)
        require_available(order.master_id, new_start_at, new_end_at, exclude_order=order.pk)
    order.start_at,order.end_at = new_start_at,new_end_at
    if order.status in ACTIVE:
        create_order_block(order)
    order.save()
    expire_offers(order)
    OrderStatusHistory.objects.create(order=order,actor=actor,from_status=order.status,to_status=order.status,note='Перенос времени')
    return order


def payment_balance(order):
    balance = Decimal('0')
    for payment in order.payments.all():
        if payment.type == 'REFUND' and payment.status == 'REFUNDED':
            balance -= payment.amount
        elif payment.type != 'REFUND' and payment.status == 'PAID':
            balance += payment.amount
    return balance


@transaction.atomic
def record_payment(order, actor, **data):
    order = locked_order(order,actor)
    if data['type'] == 'REFUND' and data['status'] != 'REFUNDED':
        raise ValidationError({'status':'Возврат должен иметь статус REFUNDED'})
    if data['type'] != 'REFUND' and data['status'] == 'REFUNDED':
        raise ValidationError({'type':'Для возврата используйте REFUND'})
    balance = payment_balance(order)
    if data['type'] == 'REFUND' and data['amount'] > balance:
        raise ValidationError({'amount': 'Возврат превышает полученную сумму'})
    if data['status'] == 'PAID' and order.final_price is not None and balance+data['amount'] > order.final_price:
        raise ValidationError({'amount': 'Оплата превышает итоговую цену'})
    payment = Payment.objects.create(order=order,**data)
    if data['type'] == 'REFUND' and order.status == 'PAID':
        record_status(order, 'REFUNDED' if data['amount'] == balance else 'COMPLETED', actor)
    return payment
