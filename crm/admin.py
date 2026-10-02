from django.contrib import admin
from .models import MasterProfile,MasterSpecialization,Specialization,Client,Order,ScheduleBlock,Transfer,Payment,Review,Notification,OrderStatusHistory
from .services.orders import validate_master


class ReadOnlyAdmin(admin.ModelAdmin):
    def has_add_permission(self,request):
        return False
    def has_change_permission(self,request,obj=None):
        return False
    def has_delete_permission(self,request,obj=None):
        return False


# Booking/payment/status writers must go through the API service layer.
for model in [Order,ScheduleBlock,Transfer,Payment,Review,OrderStatusHistory]:
    admin.site.register(model,ReadOnlyAdmin)
for model in [MasterProfile,MasterSpecialization,Specialization,Client,Notification]:
    admin.site.register(model)
