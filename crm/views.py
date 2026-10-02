from django.db import transaction
from django.db.models import Q, Avg
from rest_framework import viewsets, mixins, generics, serializers
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError, PermissionDenied
from drf_spectacular.utils import extend_schema, OpenApiParameter
from crm.models import *
from crm.serializers import *
from crm.filters import OrderFilter
from crm.services.access import is_admin, profile, orders_for, clients_for
from crm.services import orders, schedule, transfers, dashboard, notifications
from accounts.serializers import MasterSerializer


def validate(view, serializer_class):
    s = serializer_class(data=view.request.data,context={'request':view.request})
    s.is_valid(raise_exception=True)
    return s.validated_data


class ClientViewSet(mixins.ListModelMixin,mixins.CreateModelMixin,mixins.RetrieveModelMixin,mixins.UpdateModelMixin,viewsets.GenericViewSet):
    serializer_class = ClientSerializer
    search_fields = ['name','phone']
    http_method_names = ['get','post','patch','head','options']
    def get_queryset(self):
        if getattr(self,'swagger_fake_view',False):
            return Client.objects.none()
        return clients_for(self.request.user)
    def perform_create(self,serializer):
        serializer.save(created_by=self.request.user)
    @extend_schema(responses=OrderSerializer(many=True))
    @action(detail=True,methods=['get'])
    def orders(self,request,pk=None):
        qs = orders_for(request.user).filter(client=self.get_object())
        page = self.paginate_queryset(qs)
        return self.get_paginated_response(OrderSerializer(page, many=True,context={'request':request}).data)


class OrderViewSet(mixins.ListModelMixin,mixins.CreateModelMixin,mixins.RetrieveModelMixin,mixins.UpdateModelMixin,viewsets.GenericViewSet):
    serializer_class = OrderSerializer
    filterset_class = OrderFilter
    search_fields = ['title','client__name','client__phone','address']
    ordering_fields = ['start_at','created_at','updated_at']
    http_method_names = ['get','post','patch','head','options']
    def get_queryset(self):
        if getattr(self,'swagger_fake_view',False):
            return Order.objects.none()
        return orders_for(self.request.user).prefetch_related('status_history','payments')
    def perform_create(self,serializer):
        serializer.instance = orders.create_order(self.request.user,**serializer.validated_data)
    def perform_update(self,serializer):
        serializer.instance = orders.edit_order(serializer.instance,self.request.user,serializer.validated_data)
    def mutation(self,service,data):
        order = service(self.get_object(),self.request.user,**data)
        return Response(self.get_serializer(order).data)
    @extend_schema(request=EmptySerializer,responses=OrderSerializer)
    @action(detail=True,methods=['post'])
    def confirm(self,request,pk=None):
        return self.mutation(orders.confirm_order,validate(self,EmptySerializer))
    @extend_schema(request=EmptySerializer,responses=OrderSerializer)
    @action(detail=True,methods=['post'])
    def start(self,request,pk=None):
        return self.mutation(orders.start_order,validate(self,EmptySerializer))
    @extend_schema(request=EmptySerializer,responses=OrderSerializer)
    @action(detail=True,methods=['post'])
    def complete(self,request,pk=None):
        return self.mutation(orders.complete_order,validate(self,EmptySerializer))
    @extend_schema(request=PaidSerializer,responses=OrderSerializer)
    @action(detail=True,methods=['post'],url_path='mark-paid')
    def mark_paid(self,request,pk=None):
        return self.mutation(orders.mark_paid,validate(self,PaidSerializer))
    @extend_schema(request=CancelSerializer,responses=OrderSerializer)
    @action(detail=True,methods=['post'])
    def cancel(self,request,pk=None):
        return self.mutation(orders.cancel_order,validate(self,CancelSerializer))
    @extend_schema(request=RescheduleSerializer,responses=OrderSerializer)
    @action(detail=True,methods=['post'])
    def reschedule(self,request,pk=None):
        return self.mutation(orders.reschedule_order,validate(self,RescheduleSerializer))
    @extend_schema(methods=['GET'],responses=TransferSerializer(many=True))
    @extend_schema(methods=['POST'],request=OfferSerializer,responses={201:TransferSerializer})
    @action(detail=True,methods=['get','post'])
    def transfers(self,request,pk=None):
        order = self.get_object()
        if request.method == 'POST':
            transfer = transfers.offer(order,request.user,**validate(self,OfferSerializer))
            return Response(TransferSerializer(transfer).data,status=201)
        return Response(TransferSerializer(order.transfers.all(),many=True).data)
    @extend_schema(responses=MasterSerializer(many=True))
    @action(detail=True,methods=['get'],url_path='transfer-candidates')
    def transfer_candidates(self,request,pk=None):
        order = self.get_object()
        if not order.master_id:
            return Response([])
        # Admin-only diagnostics: masters cannot browse/select other masters.
        if not is_admin(request.user):
            raise PermissionDenied('Система подбирает мастера автоматически')
        return Response(MasterSerializer(transfers.candidates(order),many=True).data)
    @extend_schema(methods=['GET'],responses=PaymentSerializer(many=True))
    @extend_schema(methods=['POST'],request=PaymentSerializer,responses={201:PaymentSerializer})
    @action(detail=True,methods=['get','post'])
    def payments(self,request,pk=None):
        order = self.get_object()
        if request.method == 'POST':
            payment = orders.record_payment(order,request.user,**validate(self,PaymentSerializer))
            return Response(PaymentSerializer(payment).data,status=201)
        return Response(PaymentSerializer(order.payments.all(),many=True).data)


class ScheduleViewSet(mixins.ListModelMixin,viewsets.GenericViewSet):
    serializer_class = BlockSerializer
    def get_queryset(self):
        if getattr(self,'swagger_fake_view',False):
            return ScheduleBlock.objects.none()
        qs = ScheduleBlock.objects.all()
        if not is_admin(self.request.user):
            qs = qs.filter(master=profile(self.request.user))
        s = DateRangeSerializer(data={
            key:self.request.query_params[value] for key,value in [('from_at','from'),('to_at','to')]
            if value in self.request.query_params})
        s.is_valid(raise_exception=True)
        if s.validated_data.get('from_at'):
            qs = qs.filter(end_at__gt=s.validated_data['from_at'])
        if s.validated_data.get('to_at'):
            qs = qs.filter(start_at__lt=s.validated_data['to_at'])
        return qs.order_by('start_at','id')
    @extend_schema(parameters=[OpenApiParameter('from',type={'type':'string','format':'date-time'}),OpenApiParameter('to',type={'type':'string','format':'date-time'})])
    def list(self,*args,**kwargs):
        return super().list(*args,**kwargs)
    @extend_schema(request=CheckSerializer,responses=AvailableSerializer)
    @action(detail=False,methods=['post'])
    def check(self,request):
        d = validate(self,CheckSerializer)
        return Response({'available':schedule.check_availability(d['master_id'].pk,d['start_at'],d['end_at'])})
    @extend_schema(parameters=[OpenApiParameter('date',type={'type':'string','format':'date'},required=True),OpenApiParameter('master_id',type={'type':'string','format':'uuid'})],responses=SlotSerializer(many=True))
    @action(detail=False,methods=['get'],url_path='free-slots')
    def free_slots(self,request):
        s = FreeSlotsQuerySerializer(data=request.query_params)
        s.is_valid(raise_exception=True)
        master = s.validated_data.get('master_id')
        if not is_admin(request.user):
            if master and master.pk != profile(request.user).pk:
                raise PermissionDenied()
            master = profile(request.user)
        if not master:
            raise ValidationError({'master_id':'Обязательное поле'})
        return Response(SlotSerializer(schedule.free_slots(master.pk,s.validated_data['date']),many=True).data)


class BlockViewSet(mixins.CreateModelMixin,mixins.UpdateModelMixin,mixins.DestroyModelMixin,viewsets.GenericViewSet):
    serializer_class = BlockSerializer
    http_method_names = ['post','patch','delete','head','options']
    def get_queryset(self):
        qs = ScheduleBlock.objects.exclude(type='ORDER')
        if getattr(self,'swagger_fake_view',False):
            return qs.none()
        return qs if is_admin(self.request.user) else qs.filter(master=profile(self.request.user))
    def perform_create(self,serializer):
        serializer.instance = schedule.create_manual_block(**serializer.validated_data)
    def perform_update(self,serializer):
        serializer.instance = schedule.update_manual_block(serializer.instance,serializer.validated_data)
    def perform_destroy(self,instance):
        schedule.delete_manual_block(instance)


class TransferViewSet(mixins.ListModelMixin,mixins.RetrieveModelMixin,viewsets.GenericViewSet):
    serializer_class = TransferSerializer
    filterset_fields = ['status']
    def get_queryset(self):
        qs = Transfer.objects.select_related('order','from_master','to_master')
        if getattr(self,'swagger_fake_view',False):
            return qs.none()
        if not is_admin(self.request.user):
            m = profile(self.request.user)
            qs = qs.filter(Q(from_master=m)|Q(to_master=m))
        return qs
    @action(detail=False,methods=['get'])
    def incoming(self,request):
        qs = self.filter_queryset(self.get_queryset().filter(status='OFFERED'))
        if not is_admin(request.user):
            qs = qs.filter(to_master=profile(request.user))
        return self.get_paginated_response(self.get_serializer(self.paginate_queryset(qs),many=True).data)
    @extend_schema(request=EmptySerializer,responses=TransferSerializer)
    @action(detail=True,methods=['post'])
    def accept(self,request,pk=None):
        validate(self,EmptySerializer)
        return Response(self.get_serializer(transfers.accept(self.get_object(),request.user)).data)
    @extend_schema(request=EmptySerializer,responses=TransferSerializer)
    @action(detail=True,methods=['post'])
    def decline(self,request,pk=None):
        validate(self,EmptySerializer)
        return Response(self.get_serializer(transfers.decline(self.get_object(),request.user)).data)


class NotificationViewSet(mixins.ListModelMixin,viewsets.GenericViewSet):
    serializer_class = NotificationSerializer
    filterset_fields = ['is_read']
    def get_queryset(self):
        if getattr(self,'swagger_fake_view',False):
            return Notification.objects.none()
        qs = Notification.objects.all()
        return qs if is_admin(self.request.user) else qs.filter(user=self.request.user)
    @extend_schema(request=EmptySerializer,responses=NotificationSerializer)
    @action(detail=True,methods=['post'])
    def read(self,request,pk=None):
        validate(self,EmptySerializer)
        return Response(self.get_serializer(notifications.mark_read(self.get_object())).data)


class DashboardView(generics.GenericAPIView):
    serializer_class = SummarySerializer
    @extend_schema(parameters=[OpenApiParameter('period',type=str,enum=['day','week','month'])],responses=SummarySerializer)
    def get(self,request):
        return Response(SummarySerializer(dashboard.summary_for_master(request.user,request.query_params.get('period','week'))).data)


class SpecializationViewSet(viewsets.ModelViewSet):
    queryset = Specialization.objects.all()
    serializer_class = SpecializationSerializer
    search_fields = ['name']
    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self,'swagger_fake_view',False):
            return qs.none()
        return qs if is_admin(self.request.user) else qs.filter(is_active=True)
    def check_permissions(self,request):
        super().check_permissions(request)
        if request.method not in ['GET','HEAD','OPTIONS'] and not is_admin(request.user):
            raise PermissionDenied()


class MasterViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = MasterSerializer
    def get_queryset(self):
        qs = MasterProfile.objects.prefetch_related('skills')
        if getattr(self,'swagger_fake_view',False):
            return qs.none()
        return qs if is_admin(self.request.user) else qs.filter(user=self.request.user)


class ReviewViewSet(mixins.ListModelMixin,mixins.RetrieveModelMixin,mixins.CreateModelMixin,viewsets.GenericViewSet):
    serializer_class = ReviewSerializer
    def get_queryset(self):
        qs = Review.objects.all()
        if getattr(self,'swagger_fake_view',False):
            return qs.none()
        return qs if is_admin(self.request.user) else qs.filter(master=profile(self.request.user))
    @transaction.atomic
    def perform_create(self,serializer):
        if not is_admin(self.request.user):
            raise PermissionDenied('Создание внутренней оценки доступно администратору')
        order = Order.objects.select_for_update().get(pk=serializer.validated_data['order'].pk)
        if order.status not in ['COMPLETED','PAID'] or not order.master_id:
            raise ValidationError('Оценка доступна только для завершённого заказа')
        schedule.lock_masters(order.master_id)
        serializer.save(master=order.master)
        rating = Review.objects.filter(master=order.master).aggregate(value=Avg('score'))['value']
        MasterProfile.objects.filter(pk=order.master_id).update(internal_rating=rating)
