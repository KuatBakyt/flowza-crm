from django.contrib import admin
from .models import MasterProfile,MasterSpecialization,Specialization,Client,Order,ScheduleBlock,Transfer,Payment,Review,Notification,OrderStatusHistory
from django.contrib import messages
from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.db import transaction
from django.db.models.deletion import ProtectedError
from django.template.response import TemplateResponse
from rest_framework.exceptions import APIException
from .services.cleanup import cleanup_orders, CLEANABLE_STATUSES


class ReadOnlyAdmin(admin.ModelAdmin):
    def has_add_permission(self,request):
        return False
    def has_change_permission(self,request,obj=None):
        return False
    def has_delete_permission(self,request,obj=None):
        return False


class OrderAdmin(ReadOnlyAdmin):
    list_display = ['title', 'status', 'source', 'master', 'start_at', 'created_at']
    list_filter = ['status', 'source']
    search_fields = ['title', 'client__phone', 'client__name', 'address']
    actions = ['cleanup_selected']

    def has_cleanup_permission(self, request):
        user = request.user
        return user.is_active and user.is_staff and user.role == 'ADMIN' and user.has_perm('crm.delete_order')

    @admin.action(description='Удалить выбранные заявки', permissions=['cleanup'])
    def cleanup_selected(self, request, queryset):
        if not self.has_cleanup_permission(request):
            self.message_user(request, 'Нет права удаления заявок', messages.ERROR)
            return
        selected = list(queryset.order_by('pk'))
        if request.POST.get('confirm_cleanup') == 'yes':
            try:
                with transaction.atomic():
                    self.log_deletions(request, selected)
                    count = cleanup_orders([order.pk for order in selected], request.user)
            except (APIException, ProtectedError) as exc:
                self.message_user(request, str(exc), messages.ERROR)
                return
            self.message_user(request, f'Удалено заявок: {count}', messages.SUCCESS)
            return
        protected = [order for order in selected if order.status not in CLEANABLE_STATUSES or order.payments.exists() or hasattr(order, 'review')]
        return TemplateResponse(request, 'admin/crm/order/cleanup_confirmation.html', {
            **self.admin_site.each_context(request), 'title': 'Удаление выбранных заявок',
            'opts': self.model._meta, 'orders': selected, 'protected': protected,
            'action_checkbox_name': ACTION_CHECKBOX_NAME,
        })


admin.site.register(Order, OrderAdmin)

# Booking/payment/status writers must go through the API service layer.
for model in [ScheduleBlock,Transfer,Payment,Review,OrderStatusHistory]:
    admin.site.register(model,ReadOnlyAdmin)
for model in [MasterProfile,MasterSpecialization,Specialization,Client,Notification]:
    admin.site.register(model)
