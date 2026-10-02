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
