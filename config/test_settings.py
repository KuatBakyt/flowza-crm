import os
os.environ.setdefault('DJANGO_SECRET_KEY','test-secret-key-only-for-local-test-suite-123456789')
os.environ.setdefault('DATABASE_URL','sqlite:///:memory:')
from .settings import *
ALLOWED_HOSTS = ['testserver','localhost']
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
