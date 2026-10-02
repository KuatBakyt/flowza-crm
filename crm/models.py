import uuid
from decimal import Decimal
from django.conf import settings
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from accounts.models import normalize_phone


class Entity(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        abstract = True
        ordering = ['-created_at','id']


class MasterProfile(Entity):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='master_profile')
    full_name = models.CharField(max_length=150)
    city = models.CharField(max_length=100, blank=True)
    districts = models.JSONField(default=list)
    is_available = models.BooleanField(default=True)
    internal_rating = models.DecimalField(max_digits=3, decimal_places=2, default=0, editable=False)
    completed_orders_count = models.PositiveIntegerField(default=0, editable=False)


class Specialization(Entity):
    name = models.CharField(max_length=150, unique=True)
    is_active = models.BooleanField(default=True)
    def __str__(self):
        return self.name


class MasterSpecialization(Entity):
    master = models.ForeignKey(MasterProfile, on_delete=models.CASCADE, related_name='skills')
    specialization = models.ForeignKey(Specialization, on_delete=models.PROTECT)
    experience_years = models.PositiveSmallIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    class Meta(Entity.Meta):
        constraints = [models.UniqueConstraint(fields=['master','specialization'],name='unique_master_skill')]


class Source(models.TextChoices):
    BOT = 'BOT'
    MANUAL = 'MANUAL'
    TRANSFER = 'TRANSFER'
    OTHER = 'OTHER'


class Client(Entity):
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='clients')
    name = models.CharField(max_length=150, blank=True, null=True)
    phone = models.CharField(max_length=30, db_index=True)
    source = models.CharField(max_length=10, choices=Source.choices, default=Source.MANUAL)
    external_id = models.CharField(max_length=150, blank=True, null=True)
    notes = models.TextField(blank=True)
    def save(self, *args, **kwargs):
        self.phone = normalize_phone(self.phone)
        super().save(*args, **kwargs)


class Order(Entity):
    class Status(models.TextChoices):
        NEW = 'NEW'
        PENDING = 'PENDING'
        CONFIRMED = 'CONFIRMED'
        IN_PROGRESS = 'IN_PROGRESS'
        COMPLETED = 'COMPLETED'
        PAID = 'PAID'
        CANCELLED_CLIENT = 'CANCELLED_CLIENT'
        CANCELLED_MASTER = 'CANCELLED_MASTER'
        TRANSFERRED = 'TRANSFERRED'
        REFUNDED = 'REFUNDED'
    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name='orders')
    master = models.ForeignKey(MasterProfile, on_delete=models.PROTECT, null=True, blank=True, related_name='orders')
    specialization = models.ForeignKey(Specialization, on_delete=models.PROTECT)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    address = models.CharField(max_length=255, blank=True)
    district = models.CharField(max_length=100, blank=True)
    start_at = models.DateTimeField()
    end_at = models.DateTimeField()
    estimated_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)])
    final_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True, validators=[MinValueValidator(0)])
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.NEW)
    source = models.CharField(max_length=10, choices=Source.choices, default=Source.MANUAL)
    cancellation_reason = models.TextField(blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    class Meta(Entity.Meta):
        indexes = [models.Index(fields=['master','status','start_at']),models.Index(fields=['client','-created_at'])]
        constraints = [models.CheckConstraint(condition=models.Q(start_at__lt=models.F('end_at')),name='order_valid_interval'),
            models.CheckConstraint(condition=models.Q(final_price__gte=0)|models.Q(final_price__isnull=True),name='order_nonnegative_final'),
            models.CheckConstraint(condition=models.Q(estimated_price__gte=0)|models.Q(estimated_price__isnull=True),name='order_nonnegative_estimate')]


class OrderStatusHistory(Entity):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='status_history')
    actor = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.SET_NULL,null=True)
    from_status = models.CharField(max_length=20, blank=True)
    to_status = models.CharField(max_length=20)
    note = models.TextField(blank=True)


class ScheduleBlock(Entity):
    class Type(models.TextChoices):
        ORDER = 'ORDER'
        MANUAL = 'MANUAL'
        UNAVAILABLE = 'UNAVAILABLE'
    master = models.ForeignKey(MasterProfile,on_delete=models.CASCADE,related_name='blocks')
    order = models.OneToOneField(Order,on_delete=models.CASCADE,null=True,blank=True,related_name='schedule_block')
    start_at = models.DateTimeField()
    end_at = models.DateTimeField()
    type = models.CharField(max_length=15,choices=Type.choices,default=Type.MANUAL)
    note = models.CharField(max_length=255,blank=True)
    class Meta(Entity.Meta):
        indexes = [models.Index(fields=['master','start_at','end_at'])]
        constraints = [models.CheckConstraint(condition=models.Q(start_at__lt=models.F('end_at')),name='block_valid_interval'),
            models.CheckConstraint(condition=(models.Q(type='ORDER',order__isnull=False)|(~models.Q(type='ORDER') & models.Q(order__isnull=True))),name='block_order_type')]


class Transfer(Entity):
    class Status(models.TextChoices):
        OFFERED = 'OFFERED'
        ACCEPTED = 'ACCEPTED'
        DECLINED = 'DECLINED'
        EXPIRED = 'EXPIRED'
    order = models.ForeignKey(Order,on_delete=models.CASCADE,related_name='transfers')
    from_master = models.ForeignKey(MasterProfile,on_delete=models.PROTECT,related_name='outgoing_transfers')
    to_master = models.ForeignKey(MasterProfile,on_delete=models.PROTECT,related_name='incoming_transfers')
    status = models.CharField(max_length=10,choices=Status.choices,default=Status.OFFERED)
    reason = models.CharField(max_length=255,blank=True)
    offered_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True,blank=True)
    class Meta(Entity.Meta):
        indexes = [models.Index(fields=['to_master','status','-offered_at'])]
        constraints = [models.CheckConstraint(condition=~models.Q(from_master=models.F('to_master')),name='transfer_different_masters'),
            models.UniqueConstraint(fields=['order','to_master'],condition=models.Q(status='OFFERED'),name='unique_active_offer')]


class Payment(Entity):
    class Type(models.TextChoices):
        PREPAYMENT = 'PREPAYMENT'
        FULL = 'FULL'
        REFUND = 'REFUND'
    class Status(models.TextChoices):
        PENDING = 'PENDING'
        PAID = 'PAID'
        REFUNDED = 'REFUNDED'
    order = models.ForeignKey(Order,on_delete=models.PROTECT,related_name='payments')
    amount = models.DecimalField(max_digits=12,decimal_places=2,validators=[MinValueValidator(Decimal('0.01'))])
    type = models.CharField(max_length=15,choices=Type.choices)
    status = models.CharField(max_length=10,choices=Status.choices,default=Status.PAID)
    class Meta(Entity.Meta):
        constraints = [models.CheckConstraint(condition=models.Q(amount__gt=0),name='payment_positive')]


class Review(Entity):
    order = models.OneToOneField(Order,on_delete=models.PROTECT,related_name='review')
    master = models.ForeignKey(MasterProfile,on_delete=models.PROTECT,related_name='reviews')
    score = models.PositiveSmallIntegerField(validators=[MinValueValidator(1),MaxValueValidator(5)])
    comment = models.TextField(blank=True)
    class Meta(Entity.Meta):
        constraints = [models.CheckConstraint(condition=models.Q(score__gte=1,score__lte=5),name='review_score_range')]


class Notification(Entity):
    user = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='notifications')
    type = models.CharField(max_length=40)
    title = models.CharField(max_length=200)
    body = models.TextField(blank=True)
    payload = models.JSONField(default=dict)
    is_read = models.BooleanField(default=False)
    dedup_key = models.CharField(max_length=160,null=True,blank=True,unique=True)
    class Meta(Entity.Meta):
        indexes = [models.Index(fields=['user','is_read','-created_at'])]
