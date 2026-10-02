from django.contrib.auth import authenticate
from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.tokens import RefreshToken
from accounts.models import User, normalize_phone
from crm.models import MasterProfile, MasterSpecialization
from django.db import transaction


class LoginSerializer(serializers.Serializer):
    phone = serializers.CharField(required=False)
    email = serializers.EmailField(required=False)
    password = serializers.CharField(write_only=True)

    def validate(self, data):
        if bool(data.get('phone')) == bool(data.get('email')):
            raise serializers.ValidationError('Укажите только phone или email')
        phone = normalize_phone(data['phone']) if data.get('phone') else None
        if data.get('email'):
            user = User.objects.filter(email__iexact=data['email']).first()
            phone = user.phone if user else ''
        user = authenticate(request=self.context.get('request'),phone=phone,password=data['password'])
        if user is None:
            raise AuthenticationFailed('Неверные данные для входа')
        refresh = RefreshToken.for_user(user)
        return {'access':str(refresh.access_token),'refresh':str(refresh)}


class TokenPairSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class SkillSerializer(serializers.ModelSerializer):
    class Meta:
        model = MasterSpecialization
        fields = ['id','specialization','experience_years','is_active']
        read_only_fields = fields


class MasterSerializer(serializers.ModelSerializer):
    skills = SkillSerializer(many=True,read_only=True)
    class Meta:
        model = MasterProfile
        fields = ['id','full_name','city','districts','is_available','internal_rating','completed_orders_count','skills']
        read_only_fields = ['id','internal_rating','completed_orders_count','skills']
    def validate_districts(self,value):
        if not isinstance(value,list) or any(not isinstance(v,str) or len(v)>100 for v in value):
            raise serializers.ValidationError('Ожидается список названий районов')
        return value


class MeSerializer(serializers.ModelSerializer):
    def to_internal_value(self,data):
        data = data.copy()
        if data.get('phone'):
            data['phone'] = normalize_phone(data['phone'])
        if data.get('email'):
            data['email'] = data['email'].lower()
        return super().to_internal_value(data)
    master_profile = MasterSerializer(required=False)
    class Meta:
        model = User
        fields = ['id','phone','email','role','master_profile']
        read_only_fields = ['id','role']
    def validate_phone(self,value):
        return normalize_phone(value)
    @transaction.atomic
    def update(self,instance,validated_data):
        master = validated_data.pop('master_profile',None)
        instance = super().update(instance,validated_data)
        if master is not None:
            profile = MasterProfile.objects.select_for_update().filter(user=instance).first()
            if profile is None:
                raise serializers.ValidationError({'master_profile':'Профиль создаёт администратор'})
            for key,value in master.items():
                setattr(profile,key,value)
            profile.save()
            instance._state.fields_cache.pop('master_profile',None)
        return instance
