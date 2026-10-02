from crm.models import Notification


def create_notification(user, type, title, body='', payload=None, dedup_key=None):
    fields = dict(user=user,type=type,title=title,body=body,payload=payload or {})
    if dedup_key:
        return Notification.objects.get_or_create(dedup_key=dedup_key,defaults=fields)[0]
    return Notification.objects.create(**fields)


def mark_read(notification):
    notification.is_read = True
    notification.save(update_fields=['is_read'])
    return notification
