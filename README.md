# Clothes

Flutter-клиент и server-side контур C2C-маркетплейса одежды. Продавцом вещи
является пользователь, а не платформа: платформа предоставляет IT-сервис,
каталог, коммуникацию, модерацию, доставку и технологию безопасной сделки.
Репозиторий также содержит Supabase migrations/RLS/Edge Functions, сервис
визуального анализа и release/legal чек-листы.

## Статус запуска

**NO-GO для реальных платежей и доставки.** Серверные feature flags должны
оставаться выключенными, пока не закрыты внешние P0: оператор и финальные
документы, российская первичная инфраструктура ПДн, уведомления/договоры
обработки, договор Safe Deal, кассовая модель, подписанные webhook-интеграции,
reconciliation, pentest и юридическая экспертиза.

Код реализует fail-closed границы и provider-neutral модель, но не может сам
создать юридическое основание, договор или подтверждение локализации.

Исходный реестр рисков и итоговый статус исправлений:
`docs/security_legal_audit_2026-07-19.md` и
`docs/security_legal_audit_2026-07-20.md`.

## Роли и C2C-модель

- `users` — приватная учетная запись и допуск к сервису;
- `buyer_profiles` — возможность покупать после обязательных согласий и
  серверной проверки 18+;
- `seller_accounts` — отдельный допуск к продаже;
- `business_profiles` — задел для будущего B2C/профессионального режима.

Первая версия разрешает только `private_individual`. Типы `self_employed`,
`individual_entrepreneur` и `legal_entity` предусмотрены схемой, но не получают
право публикации. Seller account должен быть `verified`, не заблокирован
модерацией и не находиться на risk hold. Профессиональную торговлю нельзя
легализовать выбором чекбокса: риск оценивается по частоте и структуре
публикаций/продаж, повторяющимся товарам и изображениям.

## Какие данные хранятся

| Категория | Примеры | Видимость и назначение |
|---|---|---|
| Учетная запись | user id, auth identity, status | приватно; вход и контроль допуска |
| Возраст | дата рождения, результат/метод/время проверки | приватно; запрет сделок младше 18 |
| Публичный профиль | имя/псевдоним, аватар, город, server-owned рейтинг | каталог и доверие между сторонами |
| Seller account | тип, verification/moderation status, risk score/events | пользователь, модераторы и сервер |
| Согласия | тип и версия документа, время, IP, user-agent, отзыв | доказательство отдельного акцепта |
| Объявления | описание, состояние, фото, декларации и edit revisions | draft приватный; approved listing публичный; изменение скрыто до повторной модерации |
| Сделка | snapshot вещи/цены, события, payment/payout references | стороны и уполномоченные сотрудники |
| Доставка | получатель, контакт, ПВЗ/адрес | отдельно и только на нужной стадии |
| Спор | причина, описание, evidence, решения | стороны спора и модераторы |
| Чат/жалобы | сообщения, attachments, tombstones, reports | участники; evidence отдельно и ограниченно |
| Аудит | actor, действие, reason, request id, время | только уполномоченные роли |

Сроки хранения определяются утвержденным retention schedule. При удалении
аккаунта удаляемые ПДн стираются, а необходимые финансовые, спорные и audit
записи сохраняются ограниченный срок в псевдонимизированном виде. Пользователю
нельзя обещать безусловное физическое удаление всей истории.

## Локальный запуск

Требуемая версия Flutter для CI: `3.44.4` (Dart `3.12.x`).

```text
flutter pub get
```

Runtime-параметры задаются через `--dart-define-from-file`. Начальная форма —
`config/release.dart-defines.example.json`; рабочий файл с production-значениями
не коммитится.

```text
flutter run --dart-define-from-file=config/release.dart-defines.json
```

Без Supabase-конфигурации приложение намеренно не запускается. Только для
локальной debug-разработки офлайн-демо включается явно:

```text
flutter run --dart-define=ALLOW_UNSAFE_LOCAL_DEMO=true
```

В release-режиме этот флаг игнорируется.

`SUPABASE_ANON_KEY` является публичным клиентским ключом. `service_role`, ключи
платежей/доставки, APNs private key и Firebase service account разрешены только
в server/CI secret store.

## Quality gate

```text
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --release --no-codesign
```

Workflow `.github/workflows/mobile_quality.yml` выполняет тот же базовый gate на
ветке `master`. Подписанные AAB/IPA требуют принадлежащих владельцу продукта
идентификаторов и credentials и намеренно не собираются с debug-подписью.

## Supabase

Изменения схемы вносятся только новыми файлами в `supabase/migrations`; версии
миграций должны быть уникальными. `supabase/schema.sql` намеренно выведен из
эксплуатации: он не является snapshot или deployment path. Перед production
обязательны отдельный staging, reset с нуля, dry-run, реальные multi-user
RLS/grants tests, backup и проверенный restore.

Первый файл `20260710000000_core_schema_baseline.sql` воспроизводит историческую
схему для чистого проекта. В уже существующем проекте, где эта схема создавалась
до появления migration history, baseline нельзя повторно накатывать вслепую:
сначала нужно сверить schema drift и отметить его applied через контролируемый
`supabase migration repair`, затем проверить `supabase db push --dry-run`.

Live checkout, ЮKassa и провайдеры доставки остаются выключены feature flags до
договоров, sandbox certification и полного reconciliation/refund/dispute/return
E2E. Клиент никогда не подтверждает оплату, выплату или произвольный статус:
он отправляет только допустимую команду, а переход выполняет серверный автомат.

Канонический заказ:

```text
created -> paid -> seller_confirmed -> shipped -> received
        -> inspection -> completed

created/paid/seller_confirmed -> cancelled
paid/seller_confirmed/shipped/received/inspection -> dispute
```

Открытие спора замораживает выплату. Даже без спора выплата не становится
доступной раньше чем через 48 часов после `completed`; processing также требует
включенного server live-флага. Решение по спору принимает только уполномоченная
роль с обязательной записью в audit log. Фактические provider refund/payout в
репозитории пока не реализованы.

## Документация

- `docs/production_readiness.md` — архитектура интеграций и список P0-блокеров.
- `docs/release_checklist.md` — App Store / Google Play и signing checklist.
- `docs/legal_release_plan_ru.md` — юридический рабочий план и официальные источники.
- `docs/account_deletion.md` — контракт безопасного удаления аккаунта.
- `docs/security_legal_audit_2026-07-19.md` — полный P0/P1/P2 аудит до исправлений.
- `docs/security_legal_audit_2026-07-20.md` — статус исправлений и остаточные риски.

Текущий код — активная pre-release версия. Наличие UI оплаты или доставки не
означает готовность принимать реальные деньги или создавать отправления.
