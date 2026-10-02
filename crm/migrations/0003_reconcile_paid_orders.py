from decimal import Decimal
from django.db import migrations
from django.db.models import Sum


def reconcile(apps, schema_editor):
    Order = apps.get_model('crm', 'Order')
    Payment = apps.get_model('crm', 'Payment')
    History = apps.get_model('crm', 'OrderStatusHistory')
    alias = schema_editor.connection.alias
    for order in Order.objects.using(alias).filter(status='PAID', final_price__isnull=False).iterator():
        payments = Payment.objects.using(alias).filter(order_id=order.pk)
        received = payments.filter(status='PAID').exclude(type='REFUND').aggregate(total=Sum('amount'))['total'] or Decimal('0')
        # Historical refunds must remain deductions, never be compensated by backfill.
        missing = order.final_price - received
        if missing <= 0:
            continue
        payment = Payment.objects.using(alias).create(order_id=order.pk, amount=missing, type='FULL', status='PAID')
        paid_at = History.objects.using(alias).filter(order_id=order.pk, to_status='PAID').order_by('-created_at').values_list('created_at', flat=True).first()
        Payment.objects.using(alias).filter(pk=payment.pk).update(created_at=paid_at or order.updated_at)


class Migration(migrations.Migration):
    dependencies = [('crm', '0002_masterprofile_timezone_masterprofile_working_hours')]
    operations = [migrations.RunPython(reconcile, migrations.RunPython.noop)]
