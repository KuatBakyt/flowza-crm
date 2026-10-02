from django.db import transaction
from rest_framework.exceptions import PermissionDenied, ValidationError
from crm.models import Order, Notification
from .schedule import lock_masters

CLEANABLE_STATUSES = {'NEW', 'PENDING', 'CANCELLED_CLIENT', 'CANCELLED_MASTER'}


@transaction.atomic
def cleanup_orders(ids, actor):
    if not actor.is_active or not actor.is_staff or actor.role != 'ADMIN' or not actor.has_perm('crm.delete_order'):
        raise PermissionDenied('Очистка доступна администратору с правом удаления заявок')
    orders = list(Order.objects.select_for_update().filter(pk__in=ids).order_by('pk'))
    # Validate the whole selection before deleting anything, including confirmation races.
    for order in orders:
        if order.status not in CLEANABLE_STATUSES or order.payments.exists() or hasattr(order, 'review'):
            raise ValidationError(f'Заявка «{order.title}» защищена: удалять можно только новые, ожидающие и отменённые заявки без платежей и оценок.')
    lock_masters(*{order.master_id for order in orders if order.master_id})
    for order in orders:
        Notification.objects.filter(payload__order_id=str(order.pk)).delete()
        order.delete()
    return len(orders)
