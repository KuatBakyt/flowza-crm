from datetime import timedelta
from decimal import Decimal
import pytest
from django.utils import timezone
from rest_framework.test import APIClient
from accounts.models import User
from crm.models import MasterProfile, Specialization, MasterSpecialization, Client, Order


@pytest.fixture
def data(db):
    users = [User.objects.create_user(phone=f'+7700000000{i}',password='strong-pass-123',email=f'm{i}@flowza.test') for i in range(3)]
    masters = [MasterProfile.objects.create(user=u,full_name=f'Master {i}',city='Almaty',districts=['Bostandyk'],internal_rating=Decimal(5-i)) for i,u in enumerate(users)]
    spec = Specialization.objects.create(name='Plumbing')
    for m in masters:
        MasterSpecialization.objects.create(master=m,specialization=spec)
    client = Client.objects.create(created_by=users[0],phone='+77771112233',name='Client')
    start = (timezone.now()+timedelta(days=2)).replace(hour=6, minute=0, second=0, microsecond=0)
    end = start+timedelta(hours=1)
    order = Order.objects.create(client=client,master=masters[0],specialization=spec,title='Fix tap',district='Bostandyk',start_at=start,end_at=end)
    admin = User.objects.create_superuser('+77000000009','admin-pass-123')
    return dict(users=users,masters=masters,spec=spec,client=client,order=order,start=start,end=end,admin=admin)


@pytest.fixture
def api(data):
    client = APIClient()
    client.force_authenticate(data['users'][0])
    return client


def order_payload(data, **overrides):
    result = dict(client=str(data['client'].pk),specialization=str(data['spec'].pk),title='New job',start_at=data['start'].isoformat(),end_at=data['end'].isoformat())
    result.update(overrides)
    return result
