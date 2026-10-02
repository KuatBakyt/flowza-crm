# Source: https://www.gov.kz/memleket/entities/almaty/activities/27965
ALMATY_DISTRICTS = [
    'Алатауский', 'Алмалинский', 'Ауэзовский', 'Бостандыкский',
    'Жетысуский', 'Медеуский', 'Наурызбайский', 'Турксибский',
]


def service_districts(master):
    if master.districts:
        return master.districts
    if master.city.strip().casefold() in {'алматы', 'almaty', 'алма-ата'}:
        return ALMATY_DISTRICTS
    return []
