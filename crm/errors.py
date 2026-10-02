import logging
from django.db import IntegrityError
from rest_framework.response import Response
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework.exceptions import APIException, ValidationError
from rest_framework.views import exception_handler as drf_handler


class Conflict(APIException):
    status_code = 409
    default_code = 'schedule_conflict'
    default_detail = 'Время уже занято'


def exception_handler(exc, context):
    if isinstance(exc, DjangoValidationError):
        exc = ValidationError(getattr(exc,'message_dict',None) or exc.messages)
    if isinstance(exc, IntegrityError):
        logging.getLogger(__name__).exception('Database integrity conflict')
        return Response({'code':'integrity_conflict','message':'Конфликт данных','fields':{}},status=409)
    response = drf_handler(exc, context)
    if response is not None:
        fields = response.data if isinstance(response.data, dict) and 'detail' not in response.data else {}
        codes = exc.get_codes() if hasattr(exc,'get_codes') else 'error'
        code = codes if isinstance(codes,str) else 'validation_error'
        message = str(response.data.get('detail','Проверьте поля запроса')) if isinstance(response.data,dict) else 'Проверьте поля запроса'
        response.data = {'code':code,'message':message,'fields':fields}
    if response is None:
        logging.getLogger(__name__).exception('Unhandled API exception')
        return Response({'code':'server_error','message':'Внутренняя ошибка сервера','fields':{}},status=500)
    return response
