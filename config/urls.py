from django.contrib import admin
from django.urls import path,include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from drf_spectacular.views import SpectacularAPIView,SpectacularSwaggerView,SpectacularRedocView
from accounts.views import LoginView,LogoutView,MeView
from crm.views import ClientViewSet,OrderViewSet,ScheduleViewSet,BlockViewSet,TransferViewSet,NotificationViewSet,DashboardView,SpecializationViewSet,MasterViewSet,ReviewViewSet
router = DefaultRouter()
for prefix,view,basename in [
    ('clients',ClientViewSet,'client'),('orders',OrderViewSet,'order'),
    ('schedule/blocks',BlockViewSet,'block'),('schedule',ScheduleViewSet,'schedule'),
    ('transfers',TransferViewSet,'transfer'),('notifications',NotificationViewSet,'notification'),
    ('specializations',SpecializationViewSet,'specialization'),('masters',MasterViewSet,'master'),('reviews',ReviewViewSet,'review')]:
    router.register(prefix,view,basename=basename)
urlpatterns = [path('admin/',admin.site.urls),
    path('api/v1/auth/login/',LoginView.as_view()),path('api/v1/auth/refresh/',TokenRefreshView.as_view()),
    path('api/v1/auth/logout/',LogoutView.as_view()),path('api/v1/me/',MeView.as_view()),
    path('api/v1/dashboard/summary/',DashboardView.as_view()),path('api/v1/',include(router.urls)),
    path('api/schema/',SpectacularAPIView.as_view(),name='schema'),
    path('api/docs/',SpectacularSwaggerView.as_view(url_name='schema'),name='docs'),
    path('api/redoc/',SpectacularRedocView.as_view(url_name='schema'),name='redoc')]
