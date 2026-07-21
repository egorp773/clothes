# Итоговый security/legal аудит C2C marketplace — 20 июля 2026

## Вердикт

Кодовая модель приведена к fail-closed C2C-архитектуре, но запуск с реальными
деньгами и доставкой остается **NO-GO**. Платформа технически отделена от
продавца вещи, однако юридическая роль определяется не названием в оферте, а
реальными договорами, денежным потоком и действиями оператора.

Этот документ — инженерный аудит, а не юридическое заключение. Исходные
доказательства проблем до исправлений сохранены в
`security_legal_audit_2026-07-19.md`.

## Охват

Проверены Flutter auth/legal gate, профили, listing publish, checkout, заказы,
споры, отзывы, чат, удаление аккаунта и локальные кэши; вся цепочка Supabase
migrations, RLS/grants, SECURITY DEFINER RPC, Edge Functions и Storage buckets;
product analyzer, CI, README и release/legal документы.

## P0, закрытые кодом

| Риск | Исполняемая граница после исправления |
|---|---|
| Пользователь выбирает «физлицо/юрлицо» при регистрации | Один `users`; отдельные `buyer_profiles`, `seller_accounts`, `business_profiles`; профессиональные seller types существуют в enum, но не получают entitlement |
| Несовершеннолетний совершает сделку | Дата проверяется серверной функцией; entitlement покупки/продажи требует 18+; клиент не может выставить `age_verified` |
| Общий текст согласия | `legal_documents`, immutable published versions и отдельные `user_consents`; три обязательных документа принимаются отдельно, marketing — только добровольный opt-in |
| Клиент меняет рейтинг, счетчики и moderation fields | Column grants отозваны, trigger/RPC допускают только пользовательские поля; агрегаты меняет сервер |
| Публикация без статуса продавца и деклараций | Edge command и транзакционный RPC требуют verified `private_individual`, возраст, актуальные согласия, отсутствие block/risk hold и ровно семь versioned confirmations |
| Магазин маскируется под частное лицо | `seller_risk_events`, score и сигналы частоты, новых/одинаковых вещей, фото, брендов и размеров; threshold скрывает объявления и ограничивает продажи |
| Заблокированный продавец остается в публичном каталоге | Единый `listing_is_public`, RLS и text/similar/visual search; деградация seller account атомарно скрывает listings без автоматического восстановления |
| Один пользователь меняет чужое product media | Draft/final buckets разделены; финальный путь `product-images/{user_id}/{listing_id}/{file}` создается только server publish; публичное чтение связано с публичностью listing |
| Владелец незаметно меняет уже одобренное объявление | Только allowlisted server edit command; материальное изменение создает immutable revision, немедленно скрывает карточку и переводит ее в `pending_moderation`; повторная публикация требует решения модератора, seller eligibility и risk check |
| Flutter назначает оплату или статус заказа | Прямые order mutations отозваны; state machine выполняет role-aware server command, provider-only payment transition пишет immutable event |
| Выплата уходит во время допустимого спора | `release_not_before >= completed_at + 48 hours`; active dispute блокирует eligibility/processing, live-payout flag остается выключенным |
| Нет споров | Typed reasons, participant command, private evidence ACL, moderator resolution/audit и payout freeze |
| Сообщения уничтожаются физически | Soft delete/tombstone, reports, user blocks, moderation action и immutable evidence layer |
| Удаление аккаунта уничтожает финансовую историю или ложно обещает успех | Recent-auth Edge workflow, active-obligation hold, Storage inventory, anonymization и явные retained categories; локальные данные очищаются только после финальной серверной квитанции |

## P0, которые нельзя закрыть одним репозиторием

1. **Оператор и договорная роль.** Нужны реальные реквизиты ООО/ИП, сторона
   пользовательского договора, контакты претензий/ПДн и письменная C2C/agency
   схема. В БД намеренно нет активных фиктивных legal versions, поэтому
   регистрация fail-closed.
2. **Локализация и контур ПДн.** Нужна подтвержденная первичная инфраструктура
   в РФ, карта получателей/поручений/трансграничных передач, уведомление
   Роскомнадзора и утвержденная модель угроз. Официальная форма уведомления
   описана [Роскомнадзором](https://82.rkn.gov.ru/directions/pers/p15375/), а
   требования к защите ИСПДн — в [Постановлении Правительства № 1119](https://government.ru/docs/6339/).
3. **Финальные документы и сроки.** Юрист оператора должен опубликовать terms,
   privacy policy, отдельное consent ПДн и необязательное marketing consent с
   постоянными URL/hash. Retention policies сейчас `draft`; без сроков,
   legal-hold и scheduled purge production запрещен. Изменения об отдельности
   согласия внесены [Федеральным законом № 156-ФЗ](https://publication.pravo.gov.ru/document/0001202506240021).
4. **Реальные расчеты.** Нет подписанного Safe Deal договора, проверяемого
   provider webhook endpoint, фактических refund/payout workers, outbox,
   reconciliation и кассовой матрицы. Средства продавца нельзя принимать на
   счет платформы или считать выплаченными по локальной строке БД.
5. **Доставка.** Не определены сторона договора с перевозчиком, отправитель,
   ответственность, возврат, страхование и реальные provider adapters.
6. **Независимая приемка.** Нужны staging clean reset, multi-user RLS E2E,
   pentest, restore drill, нагрузочные/abuse тесты и sandbox-проверка всех
   гонок payment/dispute/payout.
7. **Закон о платформенной экономике.** До общего вступления требований в силу
   1 октября 2026 года нужен отдельный gap analysis по
   [Федеральному закону № 289-ФЗ](https://publication.pravo.gov.ru/Document/View/0001202507310020).

## P1 — существенный остаточный риск

1. Возраст подтверждается серверной арифметикой по заявленной дате, но это еще
   не KYC/IDV. До роста лимитов нужно разделить `age_declared` и доказанную
   проверку документа/провайдера, минимизируя хранение копий документов.
2. Dispute evidence finalize теперь сам читает object, sniff-ит MIME, считает
   SHA-256, проверяет участника/спор и применяет лимит числа файлов. До production
   все еще нужны AV scan, immutable object version, общий storage quota и удаление
   orphan uploads по TTL.
3. Anti-fraud выполняется при публикации и после завершенной продажи. Нужен
   периодический job и отдельная переоценка после refund/chargeback. Для
   измененных фото требуется реальный server-side pHash/embedding similarity.
4. Публичные table composite responses все еще шире идеального DTO. Перед
   production следует перейти на явные public views/RPC и не выдавать analysis,
   internal moderation и operational timestamps.
5. Нужны quotas/rate limits для OAuth start/exchange, публикаций, чата,
   evidence и image processing, а также job dedupe/lease.
6. Нужна moderator/support панель с MFA, least privilege, апелляциями,
   санкциями по message/listing/user и неизменяемым журналом.
7. Push/analyzer/vendor потоки должны исключать лишний текст, EXIF и токены;
   внешний analyzer допустим только после vendor/transfer решения и egress
   allowlist.

## P2 — эксплуатационный долг

- утвердить SLO/алерты stuck orders, webhook lag, dispute SLA и risk queues;
- внедрить secret rotation, SBOM/dependency scanning и incident runbooks;
- формализовать backfill/republish для quarantined legacy listings/media;
- добавить release signing, environment protection, rollback и проверенный
  backup/restore cadence.

## Автоматические доказательства

`supabase/tests/c2c_security_hardening.sql` проверяет обязательные сценарии:
18+, независимые согласия, запрет изменения rating и чужого listing/media,
семь seller confirmations, blocked seller, запрет клиентского order status и
server deletion/anonymization. Workflow `backend_security.yml` делает clean
Supabase reset и pgTAP в CI, запускает Deno Edge tests и security tests
analyzer. Flutter tests проверяют idempotency удаления, auth/cache isolation,
checkout payload и UI-контракты.

Локальная Windows-машина без запущенного Docker не может доказать clean
`supabase db reset`; это обязательный CI/staging gate, а не основание считать
миграции проверенными.
