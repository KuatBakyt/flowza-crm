# Source: https://www.gov.kz/memleket/entities/almaty/activities/27965
ALMATY_DISTRICTS = [
    'Алатауский', 'Алмалинский', 'Ауэзовский', 'Бостандыкский',
    'Жетысуский', 'Медеуский', 'Наурызбайский', 'Турксибский',
]


def service_districts(master):
    if master.districts:
        return master.districts
    if normalize_city(master.city) == 'алматы':
        return ALMATY_DISTRICTS
    return []


def normalize_city(value):
    normalized = ' '.join(value.strip().casefold().split())
    return 'алматы' if normalized in {'алматы', 'almaty', 'алма-ата'} else normalized


def serves_territory(master, source, district):
    if not normalize_city(master.city) or normalize_city(master.city) != normalize_city(source.city):
        return False
    normalize = lambda value: ' '.join(value.strip().casefold().split()).replace('ё', 'е')
    return not master.districts or not district or normalize(district) in {
        normalize(value) for value in master.districts}
