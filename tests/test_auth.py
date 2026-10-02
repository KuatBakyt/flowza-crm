import pytest
from rest_framework.test import APIClient
from accounts.models import User
pytestmark = pytest.mark.django_db


def test_login_refresh_logout_and_reuse(data):
    api = APIClient()
    response = api.post('/api/v1/auth/login/',{'phone':'8 (700) 000-00-00','password':'strong-pass-123'},format='json')
    assert response.status_code == 200
    tokens = response.data
    api.credentials(HTTP_AUTHORIZATION='Bearer '+tokens['access'])
    assert api.get('/api/v1/me/').status_code == 200
    refreshed = api.post('/api/v1/auth/refresh/',{'refresh':tokens['refresh']},format='json')
    assert refreshed.status_code == 200
    assert api.post('/api/v1/auth/refresh/',{'refresh':tokens['refresh']},format='json').status_code == 401
    assert api.post('/api/v1/auth/logout/',{'refresh':refreshed.data['refresh']},format='json').status_code == 204
    assert api.post('/api/v1/auth/refresh/',{'refresh':refreshed.data['refresh']},format='json').status_code == 401


def test_email_login_inactive_wrong_password_and_unauthenticated(data):
    api = APIClient()
    assert api.get('/api/v1/orders/').status_code == 401
    assert api.post('/api/v1/auth/login/',{'email':'M0@FLOWZA.TEST','password':'strong-pass-123'},format='json').status_code == 200
    r = api.post('/api/v1/auth/login/',{'phone':data['users'][0].phone,'password':'wrong'},format='json')
    assert r.status_code == 401 and set(r.data) == {'code','message','fields'}
    User.objects.filter(pk=data['users'][0].pk).update(is_active=False)
    assert api.post('/api/v1/auth/login/',{'phone':data['users'][0].phone,'password':'strong-pass-123'},format='json').status_code == 401


def test_profile_cannot_escalate_and_updates_nested_profile(api,data):
    r = api.patch('/api/v1/me/',{'role':'ADMIN','master_profile':{'full_name':'Bakyt','is_available':False}},format='json')
    assert r.status_code == 200 and r.data['role'] == 'MASTER'
    assert r.data['master_profile']['full_name'] == 'Bakyt'
    assert not r.data['master_profile']['is_available']
    assert api.patch('/api/v1/me/',{'master_profile':{'districts':'invalid'}},format='json').status_code == 400
