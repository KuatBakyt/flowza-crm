import pytest
from crm.models import Notification,Payment,Review,Order
from crm.tasks import send_reminders
from .test_orders import url
pytestmark = pytest.mark.django_db


def test_payments_dashboard_isolation_and_refunds(api,data):
    assert api.post(url(data,'payments'),{'amount':'-1','type':'FULL'},format='json').status_code == 400
    assert api.post(url(data,'payments'),{'amount':'1000','type':'FULL','status':'PAID'},format='json').status_code == 201
    assert api.post(url(data,'payments'),{'amount':'100','type':'REFUND','status':'REFUNDED'},format='json').status_code == 201
    assert api.get('/api/v1/dashboard/summary/?period=week').data['revenue'] == '900.00'
    assert api.get('/api/v1/dashboard/summary/?period=bad').status_code == 400
    api.force_authenticate(data['users'][1])
    assert api.get('/api/v1/dashboard/summary/').data['revenue'] == '0.00'
    assert api.get(url(data,'payments')).status_code == 404


def test_notifications_and_review_permissions(api,data):
    n = Notification.objects.create(user=data['users'][0],type='TEST',title='Hello')
    assert api.post(f'/api/v1/notifications/{n.pk}/read/',{},format='json').data['is_read']
    api.force_authenticate(data['users'][1])
    assert api.get('/api/v1/notifications/').data['count'] == 0
    assert api.post(f'/api/v1/notifications/{n.pk}/read/',{},format='json').status_code == 404
    assert api.post('/api/v1/reviews/',{'order':str(data['order'].pk),'score':5},format='json').status_code == 403
    api.force_authenticate(data['admin'])
    assert api.post('/api/v1/reviews/',{'order':str(data['order'].pk),'score':6},format='json').status_code == 400
    Order.objects.filter(pk=data['order'].pk).update(status='COMPLETED')
    assert api.post('/api/v1/reviews/',{'order':str(data['order'].pk),'score':4},format='json').status_code == 201
    data['masters'][0].refresh_from_db()
    assert data['masters'][0].internal_rating == 4


def test_reminder_dedup(data):
    from datetime import timedelta
    from django.utils import timezone
    start = timezone.now()+timedelta(minutes=30)
    Order.objects.filter(pk=data['order'].pk).update(status='CONFIRMED',start_at=start,end_at=start+timedelta(hours=1))
    send_reminders();send_reminders()
    assert Notification.objects.filter(type='ORDER_REMINDER').count() == 1


def test_schema_and_swagger(api):
    schema = api.get('/api/schema/')
    assert schema.status_code == 200
    assert '/api/v1/orders/{id}/confirm/' in schema.data['paths']
    assert api.get('/api/docs/').status_code == 200


def test_mark_paid_records_only_balance_and_retries(api, data):
    Order.objects.filter(pk=data['order'].pk).update(status='COMPLETED')
    api.post(url(data, 'payments'), {'amount': '400', 'type': 'PREPAYMENT'}, format='json')
    assert api.post(url(data, 'mark-paid'), {'final_price': '1000'}, format='json').status_code == 200
    assert api.post(url(data, 'mark-paid'), {'final_price': '1000'}, format='json').status_code == 200
    assert Payment.objects.filter(order=data['order']).count() == 2
    assert api.get('/api/v1/dashboard/summary/').data['revenue'] == '1000.00'
    detail = api.get(url(data)).data
    assert detail['paid_amount'] == '1000.00'
    assert detail['outstanding_amount'] == '0.00'
    assert api.post(url(data, 'payments'), {'amount': '1', 'type': 'FULL'}, format='json').status_code == 400
    assert api.post(url(data, 'payments'), {'amount': '1001', 'type': 'REFUND', 'status': 'REFUNDED'}, format='json').status_code == 400
    assert api.post(url(data, 'payments'), {'amount': '100', 'type': 'REFUND', 'status': 'REFUNDED'}, format='json').status_code == 201
    assert api.get('/api/v1/dashboard/summary/').data['revenue'] == '900.00'
    assert api.get(url(data)).data['outstanding_amount'] == '100.00'


def test_mark_paid_rejects_price_below_received_and_zero_is_free(api, data):
    Order.objects.filter(pk=data['order'].pk).update(status='COMPLETED')
    api.post(url(data, 'payments'), {'amount': '400', 'type': 'PREPAYMENT'}, format='json')
    assert api.post(url(data, 'mark-paid'), {'final_price': '399'}, format='json').status_code == 400
    assert Payment.objects.count() == 1
    Payment.objects.all().delete()
    assert api.post(url(data, 'mark-paid'), {'final_price': '0'}, format='json').status_code == 200
    assert Payment.objects.count() == 0


def test_legacy_paid_orders_are_reconciled_once(data):
    import importlib
    from decimal import Decimal
    from django.apps import apps
    from django.db import connection
    from crm.models import OrderStatusHistory
    Order.objects.filter(pk=data['order'].pk).update(status='PAID', final_price=Decimal('1000'))
    history = OrderStatusHistory.objects.create(order=data['order'], actor=data['users'][0], to_status='PAID')
    Payment.objects.create(order=data['order'], amount=Decimal('300'), type='PREPAYMENT', status='PAID')
    migration = importlib.import_module('crm.migrations.0003_reconcile_paid_orders')
    editor = connection.schema_editor()
    migration.reconcile(apps, editor)
    migration.reconcile(apps, editor)
    assert Payment.objects.count() == 2
    assert Payment.objects.get(type='FULL').amount == Decimal('700')
    assert Payment.objects.get(type='FULL').created_at == history.created_at


def test_legacy_backfill_preserves_existing_refund(data):
    import importlib
    from decimal import Decimal
    from django.apps import apps
    from django.db import connection
    Order.objects.filter(pk=data['order'].pk).update(status='PAID', final_price=Decimal('1000'))
    Payment.objects.create(order=data['order'], amount=Decimal('1000'), type='FULL', status='PAID')
    Payment.objects.create(order=data['order'], amount=Decimal('100'), type='REFUND', status='REFUNDED')
    migration = importlib.import_module('crm.migrations.0003_reconcile_paid_orders')
    migration.reconcile(apps, connection.schema_editor())
    assert Payment.objects.count() == 2
    from crm.services.orders import payment_balance
    assert payment_balance(data['order']) == Decimal('900')
