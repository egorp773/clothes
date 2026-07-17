# Production readiness и архитектура интеграций

Срез репозитория и официальной документации на 2026-07-17. Это технический чек-лист, а не юридическое заключение. Перед запуском нужно повторно сверить тарифы, статусы и условия провайдеров: они меняются независимо от приложения.

## Вердикт

Приложение **пока нельзя выпускать с реальными оплатой и доставкой**. До закрытия P0 все live-флаги оплаты, выплат и перевозчиков должны оставаться выключенными на сервере. UI выбора доставки не означает, что интеграция существует.

Обозначения: ✅ есть в репозитории; ⚠️ есть частично или требует проверки в развернутом окружении; ❌ отсутствует либо блокирует релиз.

| Область | Статус на дату среза | Что нужно до production |
|---|---:|---|
| Версионируемые Supabase migrations и RLS для основных сущностей | ⚠️ | Новая цепочка закрывает основные chat/order/view/storage-политики, но еще не применена к связанному проекту; сначала staging, Security Advisor и сверка drift |
| Заказы | ⚠️ | `create_order(jsonb)` серверно фиксирует товар/цену, idempotency и резерв, а прямые записи клиента отозваны; до live нужны узкие RPC переходов, платежи, отправления и E2E в staging |
| ЮKassa / безопасная сделка | ❌ | Нет deal/payment/payout/refund ledger, webhook-обработки, сверки и договора |
| СДЭК, Почта России, Яндекс Доставка | ❌ | В коде есть названия способов, но нет серверных адаптеров, реальных ПВЗ, тарифов, отправлений и синхронизации статусов |
| Модерация UGC | ⚠️ | Есть foundation-таблицы ролей, жалоб, блокировок и аудита, а клиент умеет жаловаться/блокировать; нужны обязательная очередь до публикации, панель, SLA, апелляции и abuse-тесты |
| Удаленное управление баннерами | ⚠️ | Есть серверная модель versioned banners, роли и аудит; каталог пока использует локальные баннеры, нет отдельной панели, preview/publish/rollback UI и клиентского feature-flag rollout |
| Удаление аккаунта | ⚠️ | Клиент вызывает fail-closed Edge Function, которая удаляет owner Storage/UGC и Auth user; legacy direct RPC отозван. Нужны staging deploy/E2E, retention-решение и Apple token revocation после добавления Apple login |
| Социальный вход | ❌ | Есть Яндекс/VK/Telegram, но нет эквивалентного privacy-preserving login по guideline 4.8; предпочтительно добавить Sign in with Apple |
| iOS identity и push | ⚠️ | Debug/Release APNs entitlement разделен и FCM-клиент реализован, но остаются `com.example.clothes`, тестовый URL scheme, отсутствие App ID/APNs key/provisioning и release Firebase-конфигурации |
| Privacy | ❌ | Нужны публичная privacy policy, точные App Privacy answers и Xcode privacy report; app-level `PrivacyInfo.xcprivacy` в репозитории отсутствует |
| Release CI | ⚠️ | Один workflow на `master` запускает format/analyze/tests, Android debug и unsigned iOS compile; отсутствуют подписанные AAB/IPA, environments/secrets, TestFlight/internal-testing и device E2E gate |

Новая pending-миграция отзывает прямые `insert/update/delete` на `orders` и старый positional checkout RPC. Это станет реальной границей доверия только после успешного staging/production deploy и проверки grants. Следующий P0 — добавить узкие команды (`cancel`, `confirm_handoff`, `confirm_receipt`, `open_dispute`), проверяемые серверным автоматом состояний. `service_role` и ключи провайдеров запрещено помещать в Flutter, браузерную админку, логи и Git.

## Целевая граница доверия

```text
Flutter / Admin web
      | user JWT
      v
Supabase Edge API  ----->  Postgres transaction + RLS
      |                         |
      |                         +--> outbox / immutable audit
      v
PaymentProvider / DeliveryProvider adapters
      |
      +<---- provider webhook ---- Webhook inbox ----> async worker/reconcile
```

- Клиент передает намерение: товар, способ получения, выбранный ПВЗ и контакт. Сервер заново читает объявление, фиксирует цену/комиссию/вес/габариты, атомарно резервирует товар и создает заказ.
- Для ПВЗ хранить `provider`, неизменяемый `pickup_point_id` и snapshot отображаемого адреса. Уличный адрес получателя для такого заказа не обязателен. Для доставки до двери нужны структурированный адрес и, где требует провайдер, координаты.
- Деньги хранить целыми minor units (`amount_minor`, `RUB`), время — `timestamptz`/UTC, отображение — в локальной зоне устройства.
- Внешний статус никогда не записывает `orders.status` напрямую. Адаптер переводит его в каноническое событие, а доменный автомат решает, допустим ли переход.
- PII получателя отделить от публичного заказа, выдавать минимально необходимым ролям и только на нужной стадии. Логи не должны содержать телефон, адрес, токены, полные webhook payload или платежные реквизиты.
- Edge Functions подходят для коротких API/webhook операций; тяжелую обработку, retry и сверку выполнять асинхронным worker/очередью. Supabase прямо рекомендует проектировать функции короткими и идемпотентными.

Минимальные backend-сущности перед интеграцией: `orders`, `order_items`, `order_contacts`, `order_events`, `inventory_reservations`, `payment_deals`, `payment_operations`, `refunds`, `payouts`, `disputes`, `shipments`, `shipment_events`, `provider_webhook_inbox`, `outbox_jobs`, `feature_flags`, `admin_roles`, `admin_audit_log`. Историю финансовых и статусных событий делать append-only; исправления — компенсирующими событиями, не перезаписью прошлого.

## Канонические автоматы состояний

Заказ:

```text
draft -> awaiting_payment -> paid_held -> awaiting_handoff -> in_transit
      -> delivered -> acceptance_window -> completed

awaiting_payment ---------------------------> canceled
paid_held / awaiting_handoff / in_transit --> disputed
disputed -> refunding -> refunded
disputed -> completed
in_transit -> return_in_transit -> returned -> refunded
```

Платежную сделку хранить отдельно:

```text
none -> deal_open -> payment_pending -> funds_held
funds_held -> payout_pending -> paid_out -> deal_closed
funds_held -> refund_pending -> refunded -> deal_closed
payment_pending -> failed/canceled
```

Для ЮKassa отображать provider statuses в эти состояния, но не смешивать `payment`, `deal` и `payout`. ЮKassa требует `Idempotence-Key` для создания операций; один стабильный ключ относится к одной логической операции и повторно используется при сетевом retry. Для C2C-сценария безопасной сделки деньги продавцу выпускаются только после подтвержденного условия платформы, а возврат/спор — только через сервер.

Отправление:

```text
quote_selected -> creating -> created -> accepted -> picked_up -> in_transit
              -> ready_for_pickup -> delivered

creating/created -> canceled
accepted/in_transit -> delivery_failed -> returning -> returned
```

СДЭК, Почта России и два разных API Яндекс Доставки имеют собственные статусы. Хранить исходный код в `shipment_events`, а приложение читать только каноническое состояние. Не считать `delivered` достаточным для выплаты без продуктового правила: код выдачи/Proof of Delivery, окно приемки и открытый спор должны учитываться отдельно.

Модерация объявления:

```text
draft -> pending -> automated_review -> approved -> published
                              |-> manual_review -> approved/rejected/needs_changes
published -> reported -> visible/restricted/removed
```

## Идемпотентность, webhook и сверка

1. Для каждой исходящей операции создать внутренний UUID и unique constraint `(provider, operation_type, idempotency_key)`. Повтор после timeout не создает новую оплату, выплату или доставку.
2. Публичный webhook endpoint не доверяет Supabase JWT. Он проверяет механизм провайдера по его актуальной документации, сохраняет raw body hash и уникальный provider event/object key, быстро отвечает успехом, затем обрабатывает событие асинхронно.
3. Повтор webhook должен быть no-op. Переходы только монотонные и допустимые автоматом; старое событие не откатывает новое состояние.
4. Для ЮKassa проверять актуальный объект через API и допустимый IP, как требует ее документация. Для остальных провайдеров использовать только их документированный signature/token/status-check, не придумывать собственную «подпись».
5. Добавить периодическую сверку незавершенных payment/deal/payout/shipment, dead-letter queue, ручной replay с audit trail и ежедневную финансовую сверку с реестрами ЮKassa.
6. `HTTP 200` возвращать только после надежной фиксации входящего события. Метрики: duplicate rate, webhook lag, retry/dead-letter count, provider/API error rate, stuck orders, mismatch reconciliation.

## Feature flags и безопасный rollout

Проверка флагов обязательна на сервере; скрытая кнопка в клиенте не является защитой.

```text
checkout.live_enabled = false
payments.yookassa_safe_deal.enabled = false
delivery.cdek.enabled = false
delivery.russian_post.enabled = false
delivery.yandex_express.enabled = false
delivery.yandex_other_day.enabled = false
moderation.require_approval = true
remote_banners.enabled = false
```

У флага должны быть environment, версия, owner, reason, start/end, процент rollout, minimum app version и emergency kill switch. Порядок включения: unit/contract tests -> provider sandbox -> staging E2E -> сотрудники -> 1% -> 10% -> 100%, с автоматическим rollback по ошибкам и stuck-state SLO.

## Admin, модерация и удаленные баннеры

- Отдельная web-панель, отдельный домен, MFA и роли: `support_read`, `moderator`, `catalog_editor`, `finance_operator`, `ops_admin`, `owner`. Панель работает с user JWT; `service_role` остается только внутри серверных функций.
- Все изменения писать в неизменяемый audit: actor, роль, reason, before/after, request ID, IP/device metadata и время. Выплаты, крупные возвраты и изменение банковских реквизитов требуют step-up auth; для высоких сумм — принцип четырех глаз.
- Для Apple UGC до релиза обязательны фильтрация запрещенного контента, жалоба, своевременная реакция, блокировка пользователя и опубликованный контакт поддержки. Блокировка должна прекращать взаимную видимость объявлений и сообщений, а не только скрывать одну карточку.
- Очередь модерации: risk flags, жалобы, приоритет, SLA, assigned moderator, решение/reason, appeal и история. Новые объявления публиковать только после `approved`; emergency quarantine должен мгновенно убирать контент из каталога/поиска/шаров.
- Баннеры: `placement`, локализованный creative, проверенный media asset, allowlisted deep link, active window, аудитория, `draft/published/archived`, version и rollback. Публичная RLS отдает только активную опубликованную версию; произвольные HTML/JS и неразрешенные URL запрещены.

## App Store checklist

- [ ] Зарегистрировать финальные App ID/bundle ID и URL/universal-link domains; заменить `com.example.clothes` во всех target, redirect URI и OAuth кабинетах.
- [ ] Apple Developer organization, distribution certificate, App Store profile, production APNs key/capability и TestFlight archive. Firebase iOS config должен подаваться в release CI; сейчас dart-defines там отсутствуют.
- [ ] Добавить Sign in with Apple или другой эквивалентный login, который действительно выполняет требования guideline 4.8; проверить account linking и скрытый email. При удалении аккаунта отзывать Apple token, если этот вход добавлен.
- [ ] Удаление аккаунта доступно внутри приложения, удаляет аккаунт и связанный UGC, а законно сохраняемые документы перечислены пользователю вместе со сроком. RPC должен быть migration-backed и протестирован на deployed staging.
- [ ] Реализовать полный UGC report/filter/block/contact flow и предоставить App Review рабочий demo account, тестовые сценарии и доступный staging backend.
- [ ] Оплата физических вещей должна идти внешним платежным методом, а не IAP. Цифровые boosts/продвижение объявлений — отдельный продуктовый сценарий, для которого правила IAP нужно оценивать отдельно.
- [ ] Публичные Terms, Privacy Policy, Community Rules, prohibited-items policy, dispute/refund/delivery policy, support URL/email и процедура удаления данных.
- [ ] Заполнить App Privacy для приложения и всех SDK/провайдеров; получить Xcode Privacy Report, проверить required-reason APIs и валидные manifests всех SDK. Не добавлять фиктивный пустой `PrivacyInfo.xcprivacy`.
- [ ] Локализовать permission prompts и проверить camera/photo/push deep links, offline/error states, VoiceOver, Dynamic Type, iPad/orientation либо явно ограничить поддерживаемые устройства.
- [ ] Release gate: clean install/upgrade, auth providers, delete account, listing/report/block, chat/push, checkout sandbox, delivery sandbox, refund/dispute/return, background/timeout/retry, privacy export/delete, crash-free soak и restore drill.

Apple разрешает внешнюю оплату физических товаров, но требует специальной защиты для UGC, прозрачной privacy-информации и удаления аккаунта. Сторонние social login требуют эквивалентного варианта с минимальным сбором данных, возможностью скрыть email и без рекламного профилирования без согласия.

## Провайдеры: что подготовить и что блокирует live

| Провайдер | Серверный адаптер | Внешние блокеры до live |
|---|---|---|
| ЮKassa Safe Deal | deal, payment, payout token/widget, payout, refund, webhook, reconciliation | Подписанный договор Safe Deal, `shopId`/secret, test/live доступ, fee moment, срок сделки, комиссия, payout/KYC-сценарий продавца, 54-ФЗ/чеки и правила спора/возврата |
| CDEK API v2 | tariffs, ПВЗ, order, label, cancel/return, status sync | B2B-договор, production/test credentials, тип договора/тарифы, отправитель и склад, кто юридически создает C2C-отправление, страхование, возвраты, SLA |
| Почта России «Отправка» | address normalize, tariff, ОПС/ПВЗ, order/batch, labels, return, tracking | Договор и кабинет бизнес-отправителя, application token + user authorization key, точки сдачи/баланс/тариф, отдельный tracking access и лимиты, возвратный адрес |
| Яндекс Доставка | отдельные adapters для Express и «по России»: offer/quote, claim/order, accept, cancel/return, tracking | Договор, кабинет/manager, production Bearer token, склад/`platform_station_id`, выбранная продуктовая линия, геокодер/координаты, тарифы, тестовые и боевые контуры |

Ключевое бизнес-решение до кода доставки: кто является заказчиком/отправителем по договору — платформа или каждый продавец. От этого зависят credentials, этикетка, возврат, страхование, поддержка и раскрытие PII. Зафиксировать также комиссию платформы, момент выплаты, окно приемки, доказательство передачи, арбитраж и перечень запрещенных товаров.

## Supabase production checklist

- [ ] Отдельные dev/staging/prod projects; migrations проходят staging и применяются CI, а не вручную с ноутбука. Репозиторий сейчас не содержит `supabase/config.toml`, поэтому link/config/deploy path нужно стандартизировать.
- [ ] RLS на каждой таблице exposed schema и Storage, least privilege grants; views — `security_invoker` либо не exposed. Удалить широкую legacy-запись в произвольный non-`users/` путь `product-images`.
- [ ] Пользовательские запросы Edge Functions проверяют JWT и работают RLS-scoped client. External webhooks отключают Supabase JWT только намеренно и вместо него обязательно проверяют провайдера.
- [ ] Provider credentials, Firebase service account и Supabase secret key — только Edge Function Secrets/secret manager, отдельно по environment; rotation, owner и expiry inventory. `.env` не коммитить.
- [ ] Админские операции не используют service key в браузере. Роль проверяется сервером/RLS, финансовые действия имеют audit и idempotency.
- [ ] Security Advisor, MFA для GitHub/Supabase, backup/PITR и restore test, SMTP/domain, rate limits/abuse controls, observability/alerts, data retention/deletion и incident runbook.
- [ ] Contract/load tests для checkout, concurrent reservation, duplicate webhook, out-of-order events, provider timeout/5xx, retry, cancel/refund/return и reconciliation mismatch.

## Конкретные внешние данные, которые еще нужны от владельца

1. Юридическое лицо/ИП и договорная модель маркетплейса; оферта, агентская/комиссионная модель, решение по 54-ФЗ и персональным данным — после проверки профильными юристом и бухгалтером.
2. Договоры и sandbox/live credentials ЮKassa, СДЭК, Почты России и Яндекс Доставки; контакты менеджеров и согласованные SLA/возвраты.
3. Финальные название, bundle ID, домен, support/privacy URLs, Apple Developer Team, App Store Connect app record и production APNs/Firebase registrations.
4. Правила запрещенных товаров, модерации, жалоб, блокировок, споров, приемки, возврата и компенсаций; часы и SLA поддержки.
5. Production Supabase organization/project, billing/region/backup policy, список администраторов и владельцев секретов. Секреты передаются через secret manager, не через чат и не коммитом.

Без этих данных можно реализовать и протестировать только provider-neutral contracts, sandbox adapters и выключенные feature flags; честно включить реальные деньги и отправления нельзя.

## Официальные источники

### Apple

- [App Store Review Guidelines: UGC 1.2, physical goods 3.1.3(e), Login Services 4.8, privacy 5.1](https://developer.apple.com/app-store/review/guidelines/)
- [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Manage App Privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Privacy manifest files and required-reason APIs](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Third-party SDK privacy manifest/signature requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
- [Sign in with Apple](https://developer.apple.com/documentation/SigninwithApple)

### Оплата и доставка

- [ЮKassa: основы Безопасной сделки](https://yookassa.ru/developers/solutions-for-platforms/safe-deal/basics), [сделки и идемпотентность](https://yookassa.ru/developers/solutions-for-platforms/safe-deal/integration/deals), [выплаты](https://yookassa.ru/developers/solutions-for-platforms/safe-deal/integration/payouts), [webhooks](https://yookassa.ru/developers/using-api/webhooks)
- [CDEK: официальный API](https://api-docs.cdek.ru/) и [B2B/договор](https://partners.cdek.ru/)
- [Почта России: API «Отправка»](https://otpravka.pochta.ru/specification), [подключение кабинета](https://otpravka.pochta.ru/help/), [Tracking API и лимиты](https://info.pochta.ru/support/tracking/specification-question)
- [Яндекс Доставка: developer portal](https://yandex.ru/dev/logistics/api-go-delivery/), [Express quickstart](https://yandex.ru/support/delivery-profile/ru/api/express/quickstart), [методы/OpenAPI](https://yandex.ru/support/delivery-profile/ru/api/express/openapi/), [доставка по России](https://yandex.ru/support/delivery-profile/ru/api/other-day/)

### Supabase

- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Edge Function secrets](https://supabase.com/docs/guides/functions/secrets)
- [Securing Edge Functions and external webhooks](https://supabase.com/docs/guides/functions/auth)
- [Edge Functions architecture constraints](https://supabase.com/docs/guides/functions)
- [Production Checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
