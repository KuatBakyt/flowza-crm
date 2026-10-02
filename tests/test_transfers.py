import pytest
from crm.models import Transfer,ScheduleBlock,Notification,Order
from crm.services import transfers
from .test_orders import url
pytestmark = pytest.mark.django_db


def test_auto_select_accept_and_old_access_removed(api,data):
    api.post(url(data,'confirm'),{},format='json')
    r = api.post(url(data,'transfers'),{'reason':'Busy'},format='json')
    assert r.status_code == 201 and r.data['to_master'] == data['masters'][1].pk
    t = Transfer.objects.get(pk=r.data['id'])
    assert Notification.objects.filter(user=data['users'][1],type='TRANSFER_OFFER').count() == 1
    assert api.post(f'/api/v1/transfers/{t.pk}/accept/',{},format='json').status_code == 404
    extra = Transfer.objects.create(order=data['order'],from_master=data['masters'][0],to_master=data['masters'][2])
    api.force_authenticate(data['users'][1])
    assert api.get('/api/v1/transfers/incoming/').data['count'] == 1
    assert api.post(f'/api/v1/transfers/{t.pk}/accept/',{},format='json').status_code == 200
    data['order'].refresh_from_db()
    assert data['order'].master_id == data['masters'][1].pk
    assert data['order'].status == 'CONFIRMED'
    assert ScheduleBlock.objects.get(order=data['order']).master_id == data['masters'][1].pk
    extra.refresh_from_db()
    assert extra.status == 'EXPIRED'
    assert api.get(f"/api/v1/clients/{data['client'].pk}/").status_code == 200
    assert api.post(f'/api/v1/transfers/{t.pk}/accept/',{},format='json').status_code == 400
    api.force_authenticate(data['users'][0])
    assert api.get(url(data)).status_code == 404


def test_transfer_conflict_rolls_back(api,data):
    api.post(url(data,'confirm'),{},format='json')
    r = api.post(url(data,'transfers'),{},format='json')
    t = Transfer.objects.get(pk=r.data['id'])
    ScheduleBlock.objects.create(master=data['masters'][1],start_at=data['start'],end_at=data['end'],type='MANUAL')
    api.force_authenticate(data['users'][1])
    r = api.post(f'/api/v1/transfers/{t.pk}/accept/',{},format='json')
    assert r.status_code == 409 and r.data['code'] == 'transfer_slot_conflict'
    t.refresh_from_db();data['order'].refresh_from_db()
    assert t.status == 'OFFERED' and data['order'].master_id == data['masters'][0].pk
    assert ScheduleBlock.objects.get(order=data['order']).master_id == data['masters'][0].pk


def test_no_manual_selection_and_decline_next_candidate(api,data):
    assert api.post(url(data,'transfers'),{'to_master':str(data['masters'][2].pk)},format='json').status_code == 400
    assert api.get(url(data,'transfer-candidates')).status_code == 403
    r = api.post(url(data,'transfers'),{},format='json')
    t = Transfer.objects.get(pk=r.data['id'])
    api.force_authenticate(data['users'][1])
    assert api.post(f'/api/v1/transfers/{t.pk}/decline/',{},format='json').status_code == 200
    api.force_authenticate(data['users'][0])
    r = api.post(url(data,'transfers'),{},format='json')
    assert r.data['to_master'] == data['masters'][2].pk


def test_reschedule_expires_offer_and_unavailable_candidate(api,data):
    t = transfers.offer(data['order'],data['users'][0])
    r = api.post(url(data,'reschedule'),{'new_start_at':data['start'].isoformat(),'new_end_at':data['end'].isoformat()},format='json')
    assert r.status_code == 200
    t.refresh_from_db()
    assert t.status == 'EXPIRED'
    for m in data['masters'][1:]:
        m.is_available = False;m.save()
    assert api.post(url(data,'transfers'),{},format='json').status_code == 409
