from django.db.models import Q
from rest_framework.exceptions import NotFound, PermissionDenied
from crm.models import Client, Order, MasterProfile


def is_admin(user):
    return user.role == 'ADMIN'


def profile(user):
    try:
        return user.master_profile
    except MasterProfile.DoesNotExist:
        raise PermissionDenied('Профиль мастера не создан администратором')


def orders_for(user):
    qs = Order.objects.select_related('master','client','specialization')
    return qs if is_admin(user) else qs.filter(master=profile(user))


def clients_for(user):
    qs = Client.objects.all()
    return qs if is_admin(user) else qs.filter(Q(created_by=user)|Q(orders__master=profile(user))).distinct()


def ensure_order_access(order, actor):
    if not is_admin(actor) and order.master_id != profile(actor).pk:
        raise NotFound()
