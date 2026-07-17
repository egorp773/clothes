# Удаление аккаунта

Кнопка в приложении вызывает только Edge Function `delete-account`. Функция
определяет пользователя по Bearer JWT, постранично получает из закрытого RPC
принадлежащие ему объекты `product-images` и `chat-media`, а также все медиа из
тредов, которые будут удалены через `message_threads.buyer_id/seller_id ON
DELETE CASCADE`. Функция удаляет этот полный набор батчами, затем удаляет
объявления/образы с legacy `ON DELETE SET NULL` и вызывает
`auth.admin.deleteUser`. Такой порядок не оставляет недоступные Storage-объекты
других участников после каскадного удаления треда. `SUPABASE_SERVICE_ROLE_KEY`
существует только в секретах Edge Functions и никогда не передаётся клиенту.

Клиент работает fail-closed: при любом non-2xx, сетевой ошибке или ответе без
`deleted: true` он не очищает локальные данные и не выполняет локальный sign-out.
После подтверждённого успеха очищается только account-scoped состояние
удалённого пользователя.

Deploy:

```text
supabase db push
supabase functions deploy delete-account --project-ref <project-ref>
```

Для web production задайте список origins через секрет
`ACCOUNT_DELETION_ALLOWED_ORIGINS` (через запятую). Без него функция сохраняет
совместимость с mobile/web и отвечает `Access-Control-Allow-Origin: *`; доступ
всё равно требует действующий JWT.

Оставшийся release-blocker: Sign in with Apple пока не интегрирован. Перед его
включением нужно сохранять серверный Apple authorization code/refresh token и
при удалении аккаунта отзывать токен у Apple до удаления Supabase identity.
Простое удаление identity не выполняет обязательный Apple token revocation.
