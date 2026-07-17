# Clothes

Flutter-клиент C2C-маркетплейса одежды и образов. В репозитории также находятся
Supabase migrations/Edge Functions, сервис визуального анализа и release/legal
чек-листы.

## Локальный запуск

Требуемая версия Flutter для CI: `3.44.4` (Dart `3.12.x`).

```text
flutter pub get
flutter run
```

Runtime-параметры задаются через `--dart-define-from-file`. Начальная форма —
`config/release.dart-defines.example.json`; рабочий файл с production-значениями
не коммитится.

```text
flutter run --dart-define-from-file=config/release.dart-defines.json
```

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
миграций должны быть уникальными. Перед production обязательны отдельный staging,
dry-run, RLS/grants tests и резервная копия.

Первый файл `20260710000000_core_schema_baseline.sql` воспроизводит историческую
схему для чистого проекта. В уже существующем проекте, где эта схема создавалась
до появления migration history, baseline нельзя повторно накатывать вслепую:
сначала нужно сверить schema drift и отметить его applied через контролируемый
`supabase migration repair`, затем проверить `supabase db push --dry-run`.

Live checkout, ЮKassa и провайдеры доставки остаются выключены feature flags до
договоров, sandbox certification и полного reconciliation/refund/return E2E.

## Документация

- `docs/production_readiness.md` — архитектура интеграций и список P0-блокеров.
- `docs/release_checklist.md` — App Store / Google Play и signing checklist.
- `docs/legal_release_plan_ru.md` — юридический рабочий план и официальные источники.
- `docs/account_deletion.md` — контракт безопасного удаления аккаунта.

Текущий код — активная pre-release версия. Наличие UI оплаты или доставки не
означает готовность принимать реальные деньги или создавать отправления.
