import os
from datetime import timedelta
from django.core.management.base import BaseCommand,CommandError
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone
from accounts.models import User
from crm.models import MasterProfile,Specialization,MasterSpecialization,Client,Order
from crm.services.orders import create_order


class Command(BaseCommand):
    help = 'Create idempotent demo masters/clients/orders. Requires DEMO_PASSWORD environment variable.'
    @transaction.atomic
    def handle(self,*args,**options):
        password = os.getenv('DEMO_PASSWORD')
        if not password:
            raise CommandError('Set DEMO_PASSWORD first')
        try:
            validate_password(password)
        except ValidationError as exc:
            raise CommandError('; '.join(exc.messages))
        spec,_ = Specialization.objects.get_or_create(name='Сантехника')
        masters = []
        for i,name in enumerate(['Бакыт','Ерлан','Айдар']):
            phone = f'+7700000000{i}'
            user = User.objects.filter(phone=phone).first()
            if not user:
                user = User.objects.create_user(phone,password,email=f'demo{i}@flowza.test')
            master,_ = MasterProfile.objects.get_or_create(user=user,defaults={'full_name':name,'city':'Алматы','districts':['Бостандыкский']})
            MasterSpecialization.objects.get_or_create(master=master,specialization=spec)
            masters.append(master)
        client,_ = Client.objects.get_or_create(created_by=masters[0].user,phone='+77771112233',defaults={'name':'Демо клиент'})
        if not Order.objects.filter(client=client,title='Ремонт смесителя (демо)').exists():
            start = (timezone.now()+timedelta(days=2)).replace(hour=9,minute=0,second=0,microsecond=0)
            create_order(masters[0].user,client=client,master=masters[0],specialization=spec,
                title='Ремонт смесителя (демо)',address='Алматы, демонстрационный адрес',district='Бостандыкский',
                start_at=start,end_at=start+timedelta(hours=1),estimated_price=10000)
        self.stdout.write(self.style.SUCCESS('Demo ready: +77000000000 / +77000000001 / +77000000002. Existing passwords were not changed.'))
