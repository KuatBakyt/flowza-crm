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
    following = Transfer.objects.get(order=data['order'], status='OFFERED')
    assert following.to_master_id == data['masters'][2].pk
    assert following.reason == t.reason
    api.force_authenticate(data['users'][0])
    r = api.post(url(data,'transfers'),{},format='json')
    assert str(r.data['id']) == str(following.pk)


def test_reschedule_expires_offer_and_unavailable_candidate(api,data):
    t = transfers.offer(data['order'],data['users'][0])
    r = api.post(url(data,'reschedule'),{'new_start_at':data['start'].isoformat(),'new_end_at':data['end'].isoformat()},format='json')
    assert r.status_code == 200
    t.refresh_from_db()
    assert t.status == 'EXPIRED'
    for m in data['masters'][1:]:
        m.is_available = False;m.save()
    assert api.post(url(data,'transfers'),{},format='json').status_code == 409


def test_decline_exhaustion_keeps_order_and_notifies_owner(api, data):
    first = transfers.offer(data['order'], data['users'][0], reason='Busy')
    second = transfers.decline(first, data['users'][1])
    assert second.status == 'DECLINED'
    following = Transfer.objects.get(order=data['order'], status='OFFERED')
    assert following.reason == 'Busy'
    transfers.decline(following, data['users'][2])
    assert not Transfer.objects.filter(order=data['order'], status='OFFERED').exists()
    assert Transfer.objects.filter(order=data['order'], status='DECLINED').count() == 2
    data['order'].refresh_from_db()
    assert data['order'].master_id == data['masters'][0].pk
    assert Notification.objects.filter(user=data['users'][0], type='TRANSFER_EXHAUSTED').count() == 1
    with pytest.raises(transfers.ValidationError):
        transfers.decline(following, data['users'][2])
    assert Notification.objects.filter(type='TRANSFER_EXHAUSTED').count() == 1


@pytest.mark.parametrize('field,value', [('city', 'Astana'), ('districts', ['Other district'])])
def test_accept_rechecks_changed_territory(api, data, field, value):
    assert api.post(url(data, 'confirm'), {}, format='json').status_code == 200
    transfer = transfers.offer(data['order'], data['users'][0])
    master = data['masters'][1]
    setattr(master, field, value)
    master.save()
    api.force_authenticate(data['users'][1])
    response = api.post(f'/api/v1/transfers/{transfer.pk}/accept/', {}, format='json')
    assert response.status_code == 409 and response.data['code'] == 'transfer_territory_conflict'
    transfer.refresh_from_db()
    data['order'].refresh_from_db()
    assert transfer.status == 'OFFERED'
    assert data['order'].master_id == data['masters'][0].pk
    assert ScheduleBlock.objects.get(order=data['order']).master_id == data['masters'][0].pk


def test_almaty_aliases_all_city_and_latest_candidate_filter(api, data):
    sender, first, second = data['masters']
    sender.city = ' Алматы '
    sender.save()
    first.city = ' ALMATY '
    first.districts = []
    first.save()
    second.city = 'Алма-Ата'
    second.districts = ['Other district']
    second.save()
    transfer = transfers.offer(data['order'], data['users'][0])
    assert transfer.to_master_id == first.pk
    # Re-evaluate changes made after the first offer before selecting the next.
    second.districts = []
    second.save()
    transfers.decline(transfer, data['users'][1])
    following = Transfer.objects.get(order=data['order'], status='OFFERED')
    assert following.to_master_id == second.pk
    transfers.accept(following, data['users'][2])
    data['order'].refresh_from_db()
    assert data['order'].master_id == second.pk


def test_decline_skips_newly_busy_candidate(data):
    first = transfers.offer(data['order'], data['users'][0])
    ScheduleBlock.objects.create(master=data['masters'][2], start_at=data['start'],
                                end_at=data['end'], type='MANUAL')
    transfers.decline(first, data['users'][1])
    assert not Transfer.objects.filter(order=data['order'], status='OFFERED').exists()
    assert Notification.objects.filter(type='TRANSFER_EXHAUSTED').exists()
