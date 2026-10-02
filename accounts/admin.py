from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.contrib.auth.forms import UserCreationForm, UserChangeForm
from .models import User


class CreateUserForm(UserCreationForm):
    class Meta:
        model = User
        fields = ['phone','email','role']


class ChangeUserForm(UserChangeForm):
    class Meta:
        model = User
        fields = '__all__'


@admin.register(User)
class FlowzaUserAdmin(UserAdmin):
    form = ChangeUserForm
    add_form = CreateUserForm
    list_display = ['phone','email','role','is_active','is_staff']
    ordering = ['phone']
    search_fields = ['phone','email']
    fieldsets = ((None,{'fields':('phone','email','password')}),
        ('Доступ',{'fields':('role','is_active','is_staff','is_superuser','groups','user_permissions')}))
    add_fieldsets = ((None,{'classes':('wide',),'fields':('phone','email','role','password1','password2')}),)
