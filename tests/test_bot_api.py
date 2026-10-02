import uuid
import pytest
from crm.models import Order, Notification
pytestmark = pytest.mark.django_db


def test_bot_submission_retry_and_isolation(api, data):
    body = {'request_id': str(uuid.uuid4()), 'client': {'name': 'Bot client', 'phone': '+77012345678', 'external_id': 'telegram:42'},
            'order': {'specialization': str(data['spec'].pk), 'title': 'Repair', 'address': 'Almaty',
                      'start_at': data['start'].isoformat(), 'end_at': data['end'].isoformat()}}
    endpoint = '/api/v1/bot/orders/'
    first = api.post(endpoint, body, format='json')
    assert first.status_code == 201
    assert api.post(endpoint, body, format='json').data == {**first.data, 'replayed': True}
    assert Order.objects.filter(source='BOT').count() == 1
    assert Notification.objects.filter(type='BOT_ORDER').count() == 1
    body['order']['title'] = 'Changed'
    assert api.post(endpoint, body, format='json').status_code == 409
    api.force_authenticate(data['admin'])
    assert api.post(endpoint, body, format='json').status_code == 403


def test_bot_rollback_and_schedule_conflict(api, data):
    from crm.models import Client, ScheduleBlock
    body = {'request_id': str(uuid.uuid4()), 'client': {'name': 'Bot client', 'phone': '+77012345678', 'external_id': 'telegram:42'},
            'order': {'specialization': str(data['spec'].pk), 'title': 'Repair', 'address': 'Almaty',
                      'start_at': data['start'].isoformat(), 'end_at': data['end'].isoformat(), 'master': str(data['masters'][1].pk)}}
    assert api.post('/api/v1/bot/orders/', body, format='json').status_code == 400
    assert not Client.objects.filter(external_id='telegram:42').exists()
    del body['order']['master']
    ScheduleBlock.objects.create(master=data['masters'][0], start_at=data['start'], end_at=data['end'])
    assert api.post('/api/v1/bot/orders/', body, format='json').status_code == 409
    assert not Client.objects.filter(external_id='telegram:42').exists()
