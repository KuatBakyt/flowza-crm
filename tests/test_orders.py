from datetime import timedelta
import pytest
from crm.models import Order, ScheduleBlock, OrderStatusHistory
from .conftest import order_payload
pytestmark = pytest.mark.django_db


def url(data,action=''):
    return f"/api/v1/orders/{data['order'].pk}/{action + '/' if action else ''}"


def test_create_client_order_and_list(api,data):
    c = api.post('/api/v1/clients/',{'phone':'8 (777) 111-22-44','name':'New'},format='json')
    assert c.status_code == 201 and c.data['phone'] == '+77771112244'
    r = api.post('/api/v1/orders/',order_payload(data,client=c.data['id']),format='json')
    assert r.status_code == 201 and r.data['master'] == data['masters'][0].pk
    assert r.data['status'] == 'NEW'
    assert api.get('/api/v1/orders/?status=NEW').data['count'] == 2
    assert api.get(f"/api/v1/clients/{c.data['id']}/orders/").data['count'] == 1


def test_full_status_flow_and_double_complete(api,data):
    assert api.post(url(data,'complete'),{},format='json').status_code == 400
    assert api.post(url(data,'mark-paid'),{'final_price':'100'},format='json').status_code == 400
    assert api.post(url(data,'confirm'),{},format='json').status_code == 200
    assert ScheduleBlock.objects.filter(order=data['order']).count() == 1
    assert api.patch(url(data),{'title':'Changed'},format='json').status_code == 200
    assert api.post(url(data,'start'),{},format='json').data['status'] == 'IN_PROGRESS'
    assert api.post(url(data,'complete'),{},format='json').data['status'] == 'COMPLETED'
    assert api.post(url(data,'complete'),{},format='json').status_code == 400
    data['masters'][0].refresh_from_db()
    assert data['masters'][0].completed_orders_count == 1
    assert api.post(url(data,'mark-paid'),{'final_price':'1000'},format='json').data['status'] == 'PAID'
    assert OrderStatusHistory.objects.filter(order=data['order']).count() == 4
    assert api.delete(url(data)).status_code == 405


@pytest.mark.parametrize('change',[{'status':'PAID'},{'final_price':'10'},{'start_at':'2026-01-01T00:00:00Z','end_at':'2025-01-01T00:00:00Z'},{'estimated_price':'-1'}])
def test_invalid_order_inputs(api,data,change):
    assert api.patch(url(data),change,format='json').status_code == 400


def test_foreign_client_master_and_order_denied(api,data):
    assert api.post('/api/v1/orders/',order_payload(data,master=str(data['masters'][1].pk)),format='json').status_code == 400
    api.force_authenticate(data['users'][1])
    assert api.get(url(data)).status_code == 404
    assert api.get(f"/api/v1/clients/{data['client'].pk}/").status_code == 404
    assert api.post('/api/v1/orders/',order_payload(data),format='json').status_code == 400
    assert api.get('/api/v1/orders/').data['count'] == 0
    api.force_authenticate(data['admin'])
    assert api.get(url(data)).status_code == 200


def test_cancel_releases_calendar(api,data):
    api.post(url(data,'confirm'),{},format='json')
    r = api.post(url(data,'cancel'),{'reason':'No longer needed','cancelled_by':'CLIENT'},format='json')
    assert r.status_code == 200 and r.data['status'] == 'CANCELLED_CLIENT'
    assert not ScheduleBlock.objects.filter(order=data['order']).exists()


def test_confirm_past_and_invalid_specialization(api,data):
    Order.objects.filter(pk=data['order'].pk).update(start_at=data['start']-timedelta(days=4),end_at=data['end']-timedelta(days=4))
    assert api.post(url(data,'confirm'),{},format='json').status_code == 400
    data['masters'][0].skills.all().delete()
    assert api.post('/api/v1/orders/',order_payload(data),format='json').status_code == 400
