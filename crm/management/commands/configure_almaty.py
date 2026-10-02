from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from accounts.models import normalize_phone
from crm.models import MasterProfile


class Command(BaseCommand):
    help = 'Set selected master to work throughout Almaty without district restrictions.'
    def add_arguments(self, parser):
        parser.add_argument('--phone', required=True)
    @transaction.atomic
    def handle(self, *args, **options):
        master = MasterProfile.objects.select_for_update().filter(user__phone=normalize_phone(options['phone']), user__role='MASTER').first()
        if not master:
            raise CommandError('Master with this phone does not exist')
        master.city = 'Алматы'
        master.districts = []
        master.save(update_fields=['city', 'districts'])
        self.stdout.write(self.style.SUCCESS('Мастер обслуживает весь Алматы — все 8 районов.'))
