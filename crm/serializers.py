from rest_framework import serializers
from django.db.models import Q
from accounts.models import normalize_phone
from crm.models import Client, Order, ScheduleBlock, Transfer, Payment, Review, Notification, Specialization, OrderStatusHistory, MasterProfile
from crm.services.access import is_admin, profile, clients_for
from crm.services.schedule import validate_interval


class StrictSerializer(serializers.Serializer):
    def to_internal_value(self, data):
        unknown = set(data)-set(self.fields)
        if unknown:
            raise serializers.ValidationError({key:'Недопустимое поле' for key in unknown})
        return super().to_internal_value(data)


class StrictModelSerializer(serializers.ModelSerializer):
    def to_internal_value(self,data):
        protected = {key for key in data if key not in self.fields or self.fields[key].read_only}
        if protected:
            raise serializers.ValidationError({key:'Поле нельзя изменять' for key in protected})
        return super().to_internal_value(data)


class ClientSerializer(StrictModelSerializer):
    class Meta:
        model = Client
        fields = ['id','name','phone','source','external_id','notes','created_at']
        read_only_fields = ['id','created_at']
    def validate_phone(self,value):
        return normalize_phone(value)


class HistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderStatusHistory
        fields = ['id','actor','from_status','to_status','note','created_at']


class OrderSerializer(StrictModelSerializer):
    status_history = HistorySerializer(many=True,read_only=True)
    class Meta:
        model = Order
        fields = ['id','client','master','specialization','title','description','address','district',
            'start_at','end_at','estimated_price','final_price','status','source','cancellation_reason',
            'created_at','updated_at','status_history']
        read_only_fields = ['id','status','final_price','cancellation_reason','created_at','updated_at','status_history']
        extra_kwargs = {'master':{'required':False,'allow_null':True}}
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            self.fields['client'].queryset = clients_for(request.user)
            if not is_admin(request.user):
                self.fields['master'].queryset = MasterProfile.objects.filter(user=request.user)
    def validate(self,data):
        user = self.context['request'].user
        if not is_admin(user):
            if 'master' in data and data['master'] != profile(user):
                raise serializers.ValidationError({'master':'Назначение другого мастера запрещено'})
            if not self.instance:
                data['master'] = profile(user)
        start = data.get('start_at',getattr(self.instance,'start_at',None))
        end = data.get('end_at',getattr(self.instance,'end_at',None))
        if start and end:
            validate_interval(start,end)
        return data


class BlockSerializer(StrictModelSerializer):
    class Meta:
        model = ScheduleBlock
        fields = ['id','master','order','start_at','end_at','type','note','created_at']
        read_only_fields = ['id','order','created_at']
        extra_kwargs = {'master':{'required':False},'type':{'required':False}}
    def validate(self,data):
        user = self.context['request'].user
        if data.get('type') == 'ORDER':
            raise serializers.ValidationError({'type':'ORDER создаётся через подтверждение заказа'})
        if not is_admin(user):
            if 'master' in data and data['master'] != profile(user):
                raise serializers.ValidationError({'master':'Чужой календарь недоступен'})
            data['master'] = profile(user)
        elif not self.instance and not data.get('master'):
            raise serializers.ValidationError({'master':'Обязательное поле'})
        if self.instance and 'master' in data and data['master'].pk != self.instance.master_id:
            raise serializers.ValidationError({'master':'Мастер блока не меняется'})
        start = data.get('start_at',getattr(self.instance,'start_at',None))
        end = data.get('end_at',getattr(self.instance,'end_at',None))
        if start and end:
            validate_interval(start,end)
        return data


class TransferSerializer(serializers.ModelSerializer):
    order_details = serializers.SerializerMethodField()
    def get_order_details(self,obj) -> dict:
        # Incoming offers expose job details, never unrelated client history/notes.
        o = obj.order
        return {'title':o.title,'description':o.description,'address':o.address,'district':o.district,
            'start_at':o.start_at.isoformat(),'end_at':o.end_at.isoformat(),
            'specialization':str(o.specialization_id),'estimated_price':str(o.estimated_price) if o.estimated_price is not None else None}
    class Meta:
        model = Transfer
        fields = ['id','order','from_master','to_master','status','reason','offered_at','responded_at','order_details']
        read_only_fields = fields


class PaymentSerializer(StrictModelSerializer):
    class Meta:
        model = Payment
        fields = ['id','order','amount','type','status','created_at']
        read_only_fields = ['id','order','created_at']
    def validate(self,data):
        data.setdefault('status','PAID')
        return data


class ReviewSerializer(StrictModelSerializer):
    class Meta:
        model = Review
        fields = ['id','order','master','score','comment','created_at']
        read_only_fields = ['id','master','created_at']


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ['id','type','title','body','payload','is_read','created_at']
        read_only_fields = fields


class SpecializationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Specialization
        fields = ['id','name','is_active']


class EmptySerializer(StrictSerializer):
    pass


class OfferSerializer(StrictSerializer):
    reason = serializers.CharField(max_length=255,required=False,allow_blank=True,default='')


class CancelSerializer(StrictSerializer):
    reason = serializers.CharField(max_length=2000)
    cancelled_by = serializers.ChoiceField(choices=['CLIENT','MASTER'])


class RescheduleSerializer(StrictSerializer):
    new_start_at = serializers.DateTimeField()
    new_end_at = serializers.DateTimeField()
    def validate(self,data):
        validate_interval(data['new_start_at'],data['new_end_at'])
        return data


class PaidSerializer(StrictSerializer):
    final_price = serializers.DecimalField(max_digits=12,decimal_places=2,min_value=0)


class CheckSerializer(StrictSerializer):
    master_id = serializers.PrimaryKeyRelatedField(queryset=MasterProfile.objects.all(),required=False)
    start_at = serializers.DateTimeField()
    end_at = serializers.DateTimeField()
    def validate(self,data):
        user = self.context['request'].user
        if not is_admin(user):
            if data.get('master_id') and data['master_id'] != profile(user):
                raise serializers.ValidationError({'master_id':'Чужой календарь недоступен'})
            data['master_id'] = profile(user)
        elif not data.get('master_id'):
            raise serializers.ValidationError({'master_id':'Обязательное поле'})
        validate_interval(data['start_at'],data['end_at'])
        return data


class AvailableSerializer(serializers.Serializer):
    available = serializers.BooleanField()


class SlotSerializer(serializers.Serializer):
    start_at = serializers.DateTimeField()
    end_at = serializers.DateTimeField()


class SummarySerializer(serializers.Serializer):
    new = serializers.IntegerField()
    active = serializers.IntegerField()
    completed = serializers.IntegerField()
    cancelled = serializers.IntegerField()
    revenue = serializers.DecimalField(max_digits=14,decimal_places=2)
    transferred = serializers.IntegerField()


class DateRangeSerializer(StrictSerializer):
    # Reserved keyword is remapped in views.
    from_at = serializers.DateTimeField(required=False)
    to_at = serializers.DateTimeField(required=False)
    def validate(self,data):
        if data.get('from_at') and data.get('to_at'):
            validate_interval(data['from_at'],data['to_at'])
        return data


class FreeSlotsQuerySerializer(StrictSerializer):
    date = serializers.DateField()
    master_id = serializers.PrimaryKeyRelatedField(queryset=MasterProfile.objects.all(),required=False)
