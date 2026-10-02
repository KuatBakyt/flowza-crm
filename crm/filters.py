import django_filters
from crm.models import Order


class OrderFilter(django_filters.FilterSet):
    date_from = django_filters.IsoDateTimeFilter(field_name='start_at',lookup_expr='gte')
    date_to = django_filters.IsoDateTimeFilter(field_name='start_at',lookup_expr='lte')
    class Meta:
        model = Order
        fields = ['status','client','specialization','date_from','date_to']
