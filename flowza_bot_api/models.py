from django.conf import settings
from django.db import models
from crm.models import Entity, Order


class BotOrderReceipt(Entity):
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    request_id = models.UUIDField()
    fingerprint = models.CharField(max_length=64)
    order = models.ForeignKey(Order, on_delete=models.PROTECT)
    response = models.JSONField()

    class Meta(Entity.Meta):
        constraints = [models.UniqueConstraint(fields=['actor', 'request_id'], name='flowza_bot_request_unique')]
