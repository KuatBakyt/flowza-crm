from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import pytest
from django.db import connection, close_old_connections
from crm.models import Order, ScheduleBlock, Transfer
from crm.services import orders, schedule, transfers
from crm.errors import Conflict

pytestmark = [pytest.mark.django_db(transaction=True),pytest.mark.postgres]


def parallel(*operations):
    barrier = Barrier(len(operations))
    def run(operation):
        close_old_connections()
        barrier.wait(timeout=10)
        try:
            operation()
            return 'ok'
        except Conflict:
            return 'conflict'
        except Exception as exc:
            from rest_framework.exceptions import ValidationError
            if isinstance(exc,ValidationError):
                return 'invalid'
            raise
        finally:
            close_old_connections()
    with ThreadPoolExecutor(max_workers=len(operations)) as pool:
        return list(pool.map(run,operations))


@pytest.fixture(autouse=True)
def postgres_only():
    if connection.vendor != 'postgresql':
        pytest.skip('Row locks require PostgreSQL; CI runs this test against PostgreSQL 16.')


def second_order(data):
    return Order.objects.create(client=data['client'],master=data['masters'][0],specialization=data['spec'],title='Second',start_at=data['start'],end_at=data['end'])


def test_parallel_confirm_empty_calendar(data):
    other = second_order(data)
    result = parallel(lambda:orders.confirm_order(data['order'],data['users'][0]),lambda:orders.confirm_order(other,data['users'][0]))
    assert sorted(result) == ['conflict','ok']
    assert ScheduleBlock.objects.filter(master=data['masters'][0]).count() == 1


def test_manual_block_races_confirm(data):
    result = parallel(lambda:orders.confirm_order(data['order'],data['users'][0]),lambda:schedule.create_manual_block(master=data['masters'][0],start_at=data['start'],end_at=data['end'],type='MANUAL'))
    assert sorted(result) == ['conflict','ok']
    assert ScheduleBlock.objects.count() == 1


def test_parallel_accept_one_winner(data):
    orders.confirm_order(data['order'],data['users'][0])
    first = transfers.offer(data['order'],data['users'][0])
    other = Transfer.objects.create(order=data['order'],from_master=data['masters'][0],to_master=data['masters'][2])
    result = parallel(lambda:transfers.accept(first,data['users'][1]),lambda:transfers.accept(other,data['users'][2]))
    assert result.count('ok') == 1 and result.count('invalid') == 1
    assert Transfer.objects.filter(order=data['order'],status='ACCEPTED').count() == 1
    assert Transfer.objects.filter(order=data['order'],status='EXPIRED').count() == 1
    assert ScheduleBlock.objects.filter(order=data['order']).count() == 1
