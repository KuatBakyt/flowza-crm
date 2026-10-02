from datetime import datetime, time, timedelta, timezone as dt_timezone
from django.db import transaction
from rest_framework.exceptions import ValidationError
from crm.models import MasterProfile, ScheduleBlock
from crm.errors import Conflict


def validate_interval(start_at, end_at):
    if start_at >= end_at:
        raise ValidationError({'end_at':'end_at должен быть позже start_at'})


def lock_masters(*ids):
    # Serialize every calendar writer on the stable master row, including empty calendars.
    return list(MasterProfile.objects.select_for_update().filter(pk__in=ids).order_by('pk'))


def check_availability(master_id, start_at, end_at, exclude_order=None, exclude_block=None):
    validate_interval(start_at,end_at)
    qs = ScheduleBlock.objects.filter(master_id=master_id,start_at__lt=end_at,end_at__gt=start_at)
    if exclude_order:
        qs = qs.exclude(order_id=exclude_order)
    if exclude_block:
        qs = qs.exclude(pk=exclude_block)
    return not qs.exists()


def require_available(master_id,start_at,end_at,**kwargs):
    if not check_availability(master_id,start_at,end_at,**kwargs):
        raise Conflict()


def create_order_block(order):
    require_available(order.master_id,order.start_at,order.end_at,exclude_order=order.pk)
    return ScheduleBlock.objects.update_or_create(order=order,defaults={
        'master_id':order.master_id,'start_at':order.start_at,'end_at':order.end_at,'type':'ORDER'})[0]


@transaction.atomic
def create_manual_block(**data):
    lock_masters(data['master'].pk)
    require_available(data['master'].pk,data['start_at'],data['end_at'])
    return ScheduleBlock.objects.create(**data)


@transaction.atomic
def update_manual_block(block, data):
    lock_masters(block.master_id)
    block = ScheduleBlock.objects.select_for_update().get(pk=block.pk)
    if block.type == 'ORDER':
        raise ValidationError('Блок заказа меняется только через заказ')
    start = data.get('start_at',block.start_at)
    end = data.get('end_at',block.end_at)
    require_available(block.master_id,start,end,exclude_block=block.pk)
    for key,value in data.items():
        setattr(block,key,value)
    block.save()
    return block


@transaction.atomic
def delete_manual_block(block):
    lock_masters(block.master_id)
    if block.type == 'ORDER':
        raise ValidationError('Блок заказа удаляется только через заказ')
    block.delete()


def free_slots(master_id, date):
    from zoneinfo import ZoneInfo
    master = MasterProfile.objects.get(pk=master_id)
    if not master.is_available or not master.user.is_active:
        return []
    zone = ZoneInfo(master.timezone)
    result = []
    for opening, closing in master.working_hours[str(date.weekday())]:
        start = datetime.combine(date, time.fromisoformat(opening), tzinfo=zone).astimezone(dt_timezone.utc)
        end = datetime.combine(date, time.fromisoformat(closing), tzinfo=zone).astimezone(dt_timezone.utc)
        cursor = start
        for block in ScheduleBlock.objects.filter(master_id=master_id, start_at__lt=end, end_at__gt=start).order_by('start_at'):
            if block.start_at > cursor:
                result.append({'start_at': cursor, 'end_at': min(block.start_at, end)})
            cursor = max(cursor, block.end_at)
        if cursor < end:
            result.append({'start_at': cursor, 'end_at': end})
    return result
