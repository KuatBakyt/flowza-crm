from rest_framework import generics, status
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError, InvalidToken
from drf_spectacular.utils import extend_schema
from .serializers import LoginSerializer, TokenPairSerializer, LogoutSerializer, MeSerializer


class LoginView(generics.GenericAPIView):
    serializer_class = LoginSerializer
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'login'
    def get_authenticate_header(self,request):
        return 'Bearer'
    @extend_schema(responses=TokenPairSerializer)
    def post(self,request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data)


class LogoutView(generics.GenericAPIView):
    serializer_class = LogoutSerializer
    @extend_schema(responses={204:None})
    def post(self,request):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            token = RefreshToken(s.validated_data['refresh'])
            if str(token['user_id']) != str(request.user.pk):
                raise InvalidToken('Токен другого пользователя')
            token.blacklist()
        except TokenError as exc:
            raise InvalidToken(str(exc))
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(generics.RetrieveUpdateAPIView):
    serializer_class = MeSerializer
    http_method_names = ['get','patch','head','options']
    def get_object(self):
        return self.request.user
