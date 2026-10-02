import re
import uuid
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.core.exceptions import ValidationError
from django.db import models


def normalize_phone(value):
    digits = re.sub(r'[\s()+-]', '', str(value))
    if len(digits) == 11 and digits.startswith('8'):
        digits = '7' + digits[1:]
    if not digits.isdigit() or not 10 <= len(digits) <= 15:
        raise ValidationError('Телефон должен содержать 10–15 цифр.')
    return '+' + digits


class UserManager(BaseUserManager):
    def create_user(self, phone, password=None, **extra):
        if extra.get('email'):
            extra['email'] = self.normalize_email(extra['email']).lower()
        user = self.model(phone=normalize_phone(phone), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password=None, **extra):
        extra.update(role='ADMIN', is_staff=True, is_superuser=True)
        return self.create_user(phone, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    class Role(models.TextChoices):
        MASTER = 'MASTER'
        ADMIN = 'ADMIN'
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=30, unique=True)
    email = models.EmailField(unique=True, null=True, blank=True)
    role = models.CharField(max_length=10, choices=Role.choices, default=Role.MASTER)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    objects = UserManager()
    USERNAME_FIELD = 'phone'
    REQUIRED_FIELDS = []

    def save(self, *args, **kwargs):
        self.phone = normalize_phone(self.phone)
        self.email = self.email.lower() if self.email else None
        super().save(*args, **kwargs)

    def __str__(self):
        return self.phone
