from datetime import timedelta
import pytest
from crm.models import Order,ScheduleBlock
from .conftest import order_payload
from .test_orders import url
pytestmark = pytest.mark.django_db


def test_manual_conflict_and_adjacency(api,data):
    r = api.post('/api/v1/schedule/blocks/',{'start_at':data['start'].isoformat(),'end_at':data['end'].isoformat(),'type':'MANUAL','note':'Busy'},format='json')
    assert r.status_code == 201
    assert api.post(url(data,'confirm'),{},format='json').status_code == 409
    r = api.post('/api/v1/schedule/check/',{'start_at':data['start'].isoformat(),'end_at':data['end'].isoformat()},format='json')
    assert r.status_code == 200 and r.data['available'] is False
    adjacent = api.post('/api/v1/orders/',order_payload(data,start_at=data['end'].isoformat(),end_at=(data['end']+timedelta(hours=1)).isoformat()),format='json')
    assert adjacent.status_code == 201
    assert api.post(f"/api/v1/orders/{adjacent.data['id']}/confirm/",{},format='json').status_code == 200
    manual_id = ScheduleBlock.objects.get(type='MANUAL').pk
    assert api.delete(f'/api/v1/schedule/blocks/{manual_id}/').status_code == 204
    assert api.post(url(data,'confirm'),{},format='json').status_code == 200


def test_two_orders_conflict_and_reschedule_rollback(api,data):
    assert api.post(url(data,'confirm'),{},format='json').status_code == 200
    r = api.post('/api/v1/orders/',order_payload(data),format='json')
    assert r.status_code == 409
    new_start = data['start']+timedelta(hours=3)
    new_end = new_start+timedelta(hours=1)
    api.post('/api/v1/schedule/blocks/',{'start_at':new_start.isoformat(),'end_at':new_end.isoformat()},format='json')
    r = api.post(url(data,'reschedule'),{'new_start_at':new_start.isoformat(),'new_end_at':new_end.isoformat()},format='json')
    assert r.status_code == 409
    data['order'].refresh_from_db()
    assert data['order'].start_at == data['start']
    assert ScheduleBlock.objects.get(order=data['order']).start_at == data['start']
    new_start += timedelta(hours=2)
    new_end += timedelta(hours=2)
    r = api.post(url(data,'reschedule'),{'new_start_at':new_start.isoformat(),'new_end_at':new_end.isoformat()},format='json')
    assert r.status_code == 200
    assert ScheduleBlock.objects.get(order=data['order']).start_at == new_start


def test_calendar_protection_and_ranges(api,data):
    api.post(url(data,'confirm'),{},format='json')
    block = ScheduleBlock.objects.get(order=data['order'])
    assert api.delete(f'/api/v1/schedule/blocks/{block.pk}/').status_code == 404
    assert api.post('/api/v1/schedule/blocks/',{'start_at':data['start'].isoformat(),'end_at':data['end'].isoformat(),'type':'ORDER'},format='json').status_code == 400
    assert api.get('/api/v1/schedule/?from=oops').status_code == 400
    assert api.get('/api/v1/schedule/free-slots/?date=oops').status_code == 400
    assert api.get('/api/v1/schedule/free-slots/?date='+data['start'].date().isoformat()).status_code == 200
    api.force_authenticate(data['users'][1])
    assert api.get('/api/v1/schedule/').data['count'] == 0
    assert api.post('/api/v1/schedule/check/',{'master_id':str(data['masters'][0].pk),'start_at':data['start'].isoformat(),'end_at':data['end'].isoformat()},format='json').status_code == 400


def test_local_working_hours_breaks_weekend_and_timezone(api, data):
    from datetime import date, datetime, timezone
    from crm.services.schedule import free_slots
    master = data['masters'][0]
    hours = {str(day): [] for day in range(7)}
    hours['0'] = [['09:00', '13:00'], ['14:00', '18:00']]
    result = api.patch('/api/v1/me/', {'master_profile': {'working_hours': hours}}, format='json')
    assert result.status_code == 200
    slots = free_slots(master.pk, date(2026, 10, 5))
    assert slots == [
        {'start_at': datetime(2026, 10, 5, 4, tzinfo=timezone.utc), 'end_at': datetime(2026, 10, 5, 8, tzinfo=timezone.utc)},
        {'start_at': datetime(2026, 10, 5, 9, tzinfo=timezone.utc), 'end_at': datetime(2026, 10, 5, 13, tzinfo=timezone.utc)}]
    assert free_slots(master.pk, date(2026, 10, 4)) == []
    hours['0'] = [['09:00', '14:00'], ['13:00', '18:00']]
    assert api.patch('/api/v1/me/', {'master_profile': {'working_hours': hours}}, format='json').status_code == 400
    assert api.patch('/api/v1/me/', {'master_profile': {'timezone': 'Invalid/City'}}, format='json').status_code == 400


def test_working_hours_boundaries_and_manual_exception(api, data):
    from datetime import datetime, timezone
    from crm.services.schedule import within_working_hours
    master = data['masters'][0]
    master.working_hours = {str(d): [] for d in range(7)}
    master.working_hours['0'] = [['09:00', '13:00'], ['14:00', '19:00']]
    master.save()
    def at(hour):
        return datetime(2026, 10, 5, hour, tzinfo=timezone.utc)
    assert within_working_hours(master, at(4), at(8))
    assert not within_working_hours(master, at(7), at(10))  # crosses lunch
    assert not within_working_hours(master, at(3), at(5))
    assert not within_working_hours(master, at(13), at(15))
    start = data['start'].replace(hour=18)
    end = start + timedelta(hours=1)
    check = api.post('/api/v1/schedule/check/', {
        'start_at': start.isoformat(), 'end_at': end.isoformat()}, format='json')
    assert check.data == {'available': True, 'within_working_hours': False}
    response = api.post('/api/v1/orders/', order_payload(data,
        start_at=start.isoformat(), end_at=end.isoformat()), format='json')
    assert response.status_code == 201
    assert api.post(f"/api/v1/orders/{response.data['id']}/confirm/", {}, format='json').status_code == 200
    # Excluding the same order permits rescheduling without self-conflict.
    check = api.post('/api/v1/schedule/check/', {
        'start_at': start.isoformat(), 'end_at': end.isoformat(),
        'exclude_order': response.data['id']}, format='json')
    assert check.data['available'] is True
    # Exclusion cannot expose another master's order.
    api.force_authenticate(data['users'][1])
    assert api.post('/api/v1/schedule/check/', {
        'start_at': start.isoformat(), 'end_at': end.isoformat(),
        'exclude_order': response.data['id']}, format='json').status_code == 404
