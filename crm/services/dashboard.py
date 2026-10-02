from datetime import timedelta
from decimal import Decimal
from django.utils import timezone
from django.db.models import Sum
from rest_framework.exceptions import ValidationError
from crm.models import Transfer, Payment
from .access import orders_for, is_admin, profile


def summary_for_master(user, period):
    days = {'day':1,'week':7,'month':30}.get(period)
    if days is None:
        raise ValidationError({'period':'Допустимы day, week, month'})
    since = timezone.now()-timedelta(days=days)
    orders = orders_for(user)
    recent = orders.filter(created_at__gte=since)
    transfers = Transfer.objects.filter(status='ACCEPTED',responded_at__gte=since)
    if not is_admin(user):
        transfers = transfers.filter(from_master=profile(user))
    paid = Payment.objects.filter(order__in=orders,created_at__gte=since,status='PAID').aggregate(total=Sum('amount'))['total'] or Decimal('0')
    refunds = Payment.objects.filter(order__in=orders,created_at__gte=since,status='REFUNDED',type='REFUND').aggregate(total=Sum('amount'))['total'] or Decimal('0')
    return {'new':recent.filter(status='NEW').count(),
        'active':orders.filter(status__in=['CONFIRMED','IN_PROGRESS']).count(),
        'completed':orders.filter(status__in=['COMPLETED','PAID'],updated_at__gte=since).count(),
        'cancelled':orders.filter(status__in=['CANCELLED_CLIENT','CANCELLED_MASTER'],updated_at__gte=since).count(),
        'revenue':paid-refunds,'transferred':transfers.count()}
