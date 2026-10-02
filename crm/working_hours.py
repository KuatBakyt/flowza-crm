from datetime import time
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from django.core.exceptions import ValidationError


def default_working_hours():
    return {str(day): [['09:00', '18:00']] for day in range(7)}


def validate_timezone(value):
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, TypeError):
        raise ValidationError('Укажите часовой пояс IANA, например Asia/Almaty')


def validate_working_hours(value):
    if not isinstance(value, dict) or set(value) != set(map(str, range(7))):
        raise ValidationError('Укажите дни 0–6 (понедельник–воскресенье)')
    for intervals in value.values():
        if not isinstance(intervals, list) or len(intervals) > 8:
            raise ValidationError('Не более 8 рабочих интервалов в день')
        previous = None
        for interval in intervals:
            if not isinstance(interval, list) or len(interval) != 2:
                raise ValidationError('Интервал: [HH:MM, HH:MM]')
            try:
                start, end = [time.fromisoformat(v) for v in interval]
                if any(len(v) != 5 for v in interval):
                    raise ValueError()
            except (ValueError, TypeError):
                raise ValidationError('Время должно быть в формате HH:MM')
            if start >= end or (previous is not None and start < previous):
                raise ValidationError('Интервалы должны идти по порядку и не пересекаться')
            previous = end
