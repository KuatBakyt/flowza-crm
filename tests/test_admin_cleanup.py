import uuid
from decimal import Decimal
import pytest
from django.contrib.admin.models import LogEntry, DELETION
from rest_framework.exceptions import PermissionDenied, ValidationError
from crm.models import Order, OrderStatusHistory, Notification, Payment, ScheduleBlock
from crm.services.cleanup import cleanup_orders
from flowza_bot_api.models import BotOrderReceipt
from flowza_bot_api.views import submit

pytestmark = pytest.mark.django_db
URL = '/admin/crm/order/'


def action(order, confirm=False):
    return {'action': 'cleanup_selected', '_selected_action': str(order.pk),
            **({'confirm_cleanup': 'yes'} if confirm else {})}


def test_admin_confirmation_and_cleanup(client, data):
    order = data['order']
    OrderStatusHistory.objects.create(order=order, to_status='NEW')
    Notification.objects.create(user=data['users'][0], type='BOT_ORDER', title='New', payload={'order_id': str(order.pk)})
    unrelated = Notification.objects.create(user=data['users'][0], type='TEST', title='Keep')
    ScheduleBlock.objects.create(master=data['masters'][0], order=order, type='ORDER', start_at=order.start_at, end_at=order.end_at)
    client.force_login(data['admin'])
    response = client.post(URL, action(order))
    assert response.status_code == 200
    assert 'Да, удалить выбранные заявки' in response.content.decode()
    assert Order.objects.filter(pk=order.pk).exists()
    response = client.post(URL, action(order, True))
    assert response.status_code == 302
    assert not Order.objects.filter(pk=order.pk).exists()
    assert not OrderStatusHistory.objects.exists()
    assert not ScheduleBlock.objects.exists()
    assert Notification.objects.count() == 1 and Notification.objects.get().pk == unrelated.pk
    assert data['client'].__class__.objects.filter(pk=data['client'].pk).exists()
    assert LogEntry.objects.filter(object_id=str(order.pk), action_flag=DELETION).count() == 1


@pytest.mark.parametrize('status', ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'PAID', 'REFUNDED', 'TRANSFERRED'])
def test_protected_statuses_cannot_be_deleted(data, status):
    Order.objects.filter(pk=data['order'].pk).update(status=status)
    with pytest.raises(ValidationError):
        cleanup_orders([data['order'].pk], data['admin'])
    assert Order.objects.filter(pk=data['order'].pk).exists()


def test_paid_selection_and_confirmation_race_roll_back(client, data):
    client.force_login(data['admin'])
    order = data['order']
    assert client.post(URL, action(order)).status_code == 200
    Payment.objects.create(order=order, amount=Decimal('10'), type='PREPAYMENT')
    response = client.post(URL, action(order, True))
    assert response.status_code == 302
    assert Order.objects.filter(pk=order.pk).exists()
    assert not LogEntry.objects.filter(action_flag=DELETION).exists()
    other = Order.objects.create(client=data['client'], master=data['masters'][0], specialization=data['spec'],
                                title='Cleanable', start_at=data['start'], end_at=data['end'])
    with pytest.raises(ValidationError):
        cleanup_orders([order.pk, other.pk], data['admin'])
    assert Order.objects.filter(pk=other.pk).exists()


def test_master_cannot_clean_requests(data):
    with pytest.raises(PermissionDenied):
        cleanup_orders([data['order'].pk], data['users'][0])


def test_bot_receipt_prevents_recreating_deleted_request(data):
    body = {'request_id': str(uuid.uuid4()), 'client': {'name': 'Bot', 'phone': '+77012345678', 'external_id': 'telegram:42'},
            'order': {'specialization': str(data['spec'].pk), 'title': 'Repair', 'address': 'Almaty',
                      'start_at': data['start'].isoformat(), 'end_at': data['end'].isoformat()}}
    result = submit(data['users'][0], body)
    cleanup_orders([result['id']], data['admin'])
    receipt = BotOrderReceipt.objects.get()
    assert receipt.order_id is None
    replay = submit(data['users'][0], body)
    assert replay == {**result, 'replayed': True}
    assert not Order.objects.filter(pk=result['id']).exists()


def test_stale_order_action_after_cleanup_returns_not_found(data):
    from rest_framework.exceptions import NotFound
    from crm.services.orders import confirm_order
    order = data['order']
    cleanup_orders([order.pk], data['admin'])
    with pytest.raises(NotFound):
        confirm_order(order, data['users'][0])
