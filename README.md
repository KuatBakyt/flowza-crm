# Flowza CRM — Backend

Рабочий backend MVP CRM для мастеров по `TZ_CRM_ONLY_Django_REST_Flutter(1).docx`:
Python 3.12, Django REST Framework, PostgreSQL 16, JWT, Celery и Redis.
Flutter-интерфейс в этот этап не входит. API готов для его подключения.

## Запуск на Windows / PowerShell

Установите Git и Docker Desktop, включите Docker Desktop. В PowerShell:

```powershell
git clone https://github.com/KuatBakyt/flowza-crm.git
cd flowza-crm
Copy-Item .env.example .env
# Задайте свой DJANGO_SECRET_KEY в .env. Для production смените пароль БД.
docker compose build
docker compose up -d db redis
docker compose run --rm api python manage.py migrate
docker compose run --rm api python manage.py createsuperuser
docker compose up -d
```

При `createsuperuser` укажите телефон и собственный пароль. Готового пароля администратора нет.
Для macOS/Linux вместо `Copy-Item` используйте `cp .env.example .env`.

- Swagger: http://localhost:8000/api/docs/
- OpenAPI: http://localhost:8000/api/schema/
- ReDoc: http://localhost:8000/api/redoc/
- Django admin: http://localhost:8000/admin/

Администратор создаёт пользователей MASTER, их MasterProfile, Specialization и MasterSpecialization
через Django admin. Заказы, календарь, платежи, передачи и оценки изменяются через API;
в admin эти записи доступны только для просмотра, чтобы не обходить транзакционные сервисы.
Публичной регистрации нет. MASTER не может создавать аккаунты или повышать свою роль.

### Демо-данные (не для production)

```powershell
# Замените значение своим паролем, минимум 8 символов.
docker compose run --rm -e DEMO_PASSWORD="your-demo-password" api python manage.py seed_demo
```

Создаёт трёх мастеров (+77000000000, +77000000001, +77000000002), специализацию,
клиента и заказ. Повторный запуск не меняет пароли существующих пользователей.
Можно проверить передачу, зайдя сначала первым, затем вторым мастером.

## API / авторизация

Все прикладные endpoints находятся под `/api/v1/`. Swagger описывает поля запросов.
Запросы кроме login/refresh требуют `Authorization: Bearer <access>`.

```json
POST /api/v1/auth/login/
{"phone":"+77000000000","password":"your-demo-password"}
```

Вместо phone можно передать email; используйте ровно один идентификатор.
Ответ: `{"access":"...","refresh":"..."}`.
Access действует 15 минут, refresh — 7 дней (настраивается в `.env`).
При refresh сервер возвращает **новые access и refresh**: Flutter обязан сохранить оба.
Предыдущий refresh попадает в blacklist. Logout отзывает переданный refresh;
уже выпущенный access действует до истечения срока.

| Раздел | Endpoints |
|---|---|
| Авторизация | `POST auth/login/`, `POST auth/refresh/`, `POST auth/logout/`, `GET/PATCH me/` |
| Клиенты | `GET/POST clients/`, `GET/PATCH clients/{id}/`, `GET clients/{id}/orders/` |
| Заказы | `GET/POST orders/`, `GET/PATCH orders/{id}/` |
| Действия заказа | `POST orders/{id}/confirm/`, `start/`, `complete/`, `mark-paid/`, `cancel/`, `reschedule/` |
| Календарь | `GET schedule/?from=&to=`, `POST schedule/check/`, `GET schedule/free-slots/?date=YYYY-MM-DD` |
| Ручные блоки | `POST schedule/blocks/`, `PATCH/DELETE schedule/blocks/{id}/` |
| Передачи | `GET/POST orders/{id}/transfers/`, `GET transfers/`, `GET transfers/incoming/`, `GET transfers/{id}/`, `POST transfers/{id}/accept/`, `decline/` |
| Платежи | `GET/POST orders/{id}/payments/` |
| Оценки | `GET reviews/`, `GET reviews/{id}/`, `POST reviews/` (ADMIN) |
| Уведомления | `GET notifications/`, `POST notifications/{id}/read/` |
| Статистика | `GET dashboard/summary/?period=day\|week\|month` |
| Справочники | `GET specializations/`, `GET masters/`; изменение специализаций — ADMIN |

Заказы: фильтры `status`, `client`, `specialization`, `date_from`, `date_to` (ISO-8601),
`search` (название/клиент/адрес), `ordering=start_at`.
Клиенты: `search` по имени/телефону. Уведомления: `is_read`.
Списки пагинируются: `count`, `next`, `previous`, `results`; 20 записей на страницу.
История платежей/передач внутри заказа возвращается массивом.
Телефоны нормализуются: `8 (700) 000-00-00` → `+77000000000`.
Все даты API — ISO-8601, хранятся и обрабатываются в UTC.

### Статусы и календарь

Основной путь: `NEW → CONFIRMED → IN_PROGRESS → COMPLETED → PAID`.
`CONFIRMED → COMPLETED` также разрешён. Повторное завершение запрещено.
`status` и `final_price` нельзя менять через PATCH.

- confirm/start/complete: `{}`;
- mark-paid: `{"final_price":"10000.00"}`;
- cancel: `{"reason":"Клиент отменил","cancelled_by":"CLIENT"}` (либо MASTER);
- reschedule: `{"new_start_at":"2026-11-01T09:00:00Z","new_end_at":"2026-11-01T10:00:00Z"}`.

Подтверждение создаёт ORDER-блок. Перенос меняет его транзакционно, отмена удаляет.
Завершённые заказы сохраняют блок как историю фактически занятого времени.
Интервалы полуоткрытые: заказ 09:00–10:00 и заказ 10:00–11:00 не конфликтуют.
Заказ и ручная занятость конфликтуют независимо от типа блока.
Свободные слоты MVP рассчитаны в фиксированном рабочем окне **09:00–18:00 UTC**;
индивидуальные рабочие часы/часовые пояса мастеров можно добавить позже.
Предварительный `schedule/check/` не резервирует время — окончательная проверка выполняется в транзакции.
ADMIN передаёт master_id в check/free-slots; MASTER всегда проверяет свой календарь.
Удаление заказов через API запрещено для всех ролей.

### Автоматическая передача («Скольжение»)

Учтено уточнение владельца проекта: **мастер не выбирает другого мастера**.
`POST orders/{id}/transfers/` принимает только `{"reason":"..."}`; поле `to_master` запрещено.
Сервер выбирает активного мастера с той же специализацией, в том же городе,
обслуживающего район заказа и свободного в заданном интервале.
Приоритет: внутренний рейтинг, число завершённых заказов, UUID для стабильного порядка.
Пустой список районов означает весь город. Текущий мастер и отказавшиеся кандидаты исключаются.
Одновременно автоматически создаётся одно предложение; повторный запрос возвращает существующее.
Если получатель отказался, отправитель может повторить запрос, система выберет следующего кандидата.
Если кандидатов нет — `409 no_transfer_candidate`.
`GET orders/{id}/transfer-candidates/` оставлен только для диагностики ADMIN.

Предложение не резервирует слот. Получатель видит описание заказа во входящем предложении,
не получая доступа к истории/заметкам клиента до принятия.
Accept повторно проверяет слот и атомарно меняет мастера, переводит заказ в CONFIRMED,
перемещает календарный блок, отмечает предложение ACCEPTED, остальные OFFERED → EXPIRED.
При конфликте `409 transfer_slot_conflict`: все изменения откатываются.
Перенос, смена специализации/района/мастера или отмена делают прежние предложения EXPIRED.
Просроченные предложения закрывает Celery beat.

### Учёт денег и оценок

Это ручной учёт, без эквайринга и переводов денег.
Платёж: `{"amount":"10000.00","type":"FULL","status":"PAID"}`;
другие типы: PREPAYMENT, REFUND; статусы: PENDING, PAID, REFUNDED.
Для REFUND обязателен статус REFUNDED. Сумма положительная.
`mark-paid` меняет статус заказа и итоговую цену, **не создаёт запись Payment**.
Dashboard revenue = сумма PAID Payment минус REFUND/REFUNDED за период,
по заказам текущего мастера. Чтобы деньги попали в статистику, создайте запись платежа.
`new` считается по дате создания, `completed/cancelled` по updated_at,
`active` — все текущие активные заказы; period — последние 1/7/30 дней.
ADMIN видит общую статистику.

Внутреннюю оценку 1–5 создаёт ADMIN для завершённого заказа.
Рейтинг мастера пересчитывается атомарно. MASTER имеет только чтение своих оценок.
Worker/beat создают уведомления о заказах за час до начала; повторные уведомления исключены.
Внешняя доставка push/SMS/Telegram в этот этап не входит.

## Архитектура и безопасность

- `accounts/`: UUID User, телефон/email, JWT, профиль.
- `crm/models.py`: доменные модели, ограничения и индексы.
- `crm/services/`: отдельные модули orders/schedule/transfers/dashboard/notifications/access.
- `crm/views.py`: маршрутизация, сериализация и вызов сервисов.
- `crm/tasks.py`: Celery reminders/expiry.
- `tests/`: API, permissions, rollback, JWT и реальная PostgreSQL-конкурентность.

Вместо десяти небольших Django apps доменные модели объединены в один `crm` app;
бизнес-логика разделена по service modules. Это не меняет контракт API.
MASTER видит только свои заказы/календарь, созданных им или связанных с его заказами клиентов,
и передачи, в которых участвует. ADMIN видит всё. Чужой объект — 404/403.
Каждый сервис повторно проверяет владельца после блокировки строки заказа.
Все писатели календаря используют `transaction.atomic` и `select_for_update` на MasterProfile,
даже если календарь пустой. При передаче блокировки мастеров берутся в порядке UUID.

Ошибки API:
```json
{"code":"schedule_conflict","message":"Время уже занято","fields":{}}
```
400 — валидация; 401 — нет авторизации; 403 — запрет; 404 — ресурс недоступен;
409 — конфликт; 500 — ошибка сервера, подробности только в серверном логе.

## Проверки

Полный набор, включая параллельные транзакции на PostgreSQL:

```powershell
docker compose run --rm api python manage.py check
docker compose run --rm api python manage.py makemigrations --check --dry-run
docker compose run --rm api python manage.py spectacular --file /tmp/schema.yaml --validate --fail-on-warn
docker compose run --rm api python -m pytest
```

GitHub Actions выполняет миграции с чистой PostgreSQL 16, проверяет схему и запускает весь набор тестов.
Для быстрой локальной проверки без Docker/PostgreSQL:

```bash
python -m venv .venv
# Активируйте .venv для вашей ОС.
pip install -r requirements.txt
python -m pytest
```

При отсутствии DATABASE_URL test_settings использует SQLite; три теста конкурентных
транзакций пропускаются, так как SQLite не поддерживает нужные row locks.
SQLite предназначен только для тестов, не для эксплуатации.

## Эксплуатация

```powershell
docker compose logs -f api worker beat
docker compose down
# Резервная копия (Linux shell, пароль берётся из контейнера):
# docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > backup.sql
```

Миграции запускайте отдельной командой перед обновлением api/worker/beat.
Не запускайте несколько beat одновременно. Не используйте `down -v`, если нужна существующая БД.
Для staging/production: собственные секреты/пароль БД, DEBUG=false, реальные ALLOWED_HOSTS и CORS,
резервные копии, reverse proxy Nginx с TLS. Контейнер API слушает только localhost хоста.
`deploy/nginx.conf.example` — пример прокси; сертификаты и домен задаются на вашем сервере.
Если TLS завершается перед Django, настройте trusted proxy прежде чем включать SECURE_SSL_REDIRECT.
Размещение на сервере и staging HTTPS требуют сервера/домена и не выполнены этим репозиторием.
