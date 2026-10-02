from django.urls import path
from .views import BotOrderView

urlpatterns = [path('orders/', BotOrderView.as_view(), name='bot-orders')]
