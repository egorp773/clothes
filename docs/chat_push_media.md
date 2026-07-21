# Chat media and push deployment

This runbook covers the private `chat-media` bucket, aborted-upload cleanup and
message push delivery. Repository changes do not deploy functions, alter the
hosted project, or set secrets automatically.

## Private chat media

Database rows store only:

- `bucket = chat-media`;
- `storage_path = threads/{thread_id}/{uploader_user_id}/{object_name}`.

Signed URLs are delivery credentials and must remain memory-only. They must not
be written to `chat_messages`, analytics, logs or a durable local cache.

`cleanup-chat-media` accepts an authenticated `POST` request no larger than
8 KiB:

```json
{
  "thread_id": "direct-user-a-user-b",
  "storage_path": "threads/direct-user-a-user-b/USER_UUID/OBJECT.jpg"
}
```

The function:

1. validates the Supabase JWT with Auth;
2. requires the uploader segment to equal `auth.uid()`;
3. verifies active membership in `chat_thread_members`;
4. falls back to legacy `message_threads.member_ids` only when the canonical
   table is absent, never when a canonical lookup is denied or malformed;
5. refuses cleanup when any `chat_messages.attachment` references the object;
6. removes the object through the privileged Storage API;
7. treats an already absent object as a successful idempotent cleanup.

The endpoint is for an upload that failed before message persistence. It must
not be used to implement message deletion; chat deletion is a soft-delete and
its evidence follows the approved retention policy.

There is an unavoidable check/remove race until the database upload-ticket
contract is installed. Production needs a `chat_media_uploads` ticket with an
atomic finalize command and a service-side TTL worker for crashes, force-kills
and logout during upload. Restoring a broad client DELETE Storage policy is not
an acceptable substitute.

Align the hosted Storage global upload limit with the bucket and Flutter client.
At the time of this runbook the bucket/client allow 100 MiB video while local
`supabase/config.toml` has a 20 MiB global limit.

## Message push

`send-message-push` accepts only `thread_id` and `message_id`. It verifies the
JWT, membership, message sender, delete state, recipient preferences and thread
mute before contacting FCM. Message text is neither selected for push nor
logged; notifications use a generic privacy-safe body.

Delivery is bounded to 49 recipients, five newest valid installations per
recipient, six concurrent token lookups and eight concurrent FCM requests.
Invalid FCM registrations are removed without logging token values.

The Edge Function accepts both claim RPC contracts:

- legacy UUID for a successful claim and `null` for a replay;
- structured response with `claimed: true` (or `should_deliver: true`) and a
  valid `attempt_id` for the caller that atomically owns delivery;
- `disposition: retry_later` plus optional `retry_after_seconds` for backoff.

A structured response must never return only `status = processing` as authority
to send; that could cause concurrent duplicate pushes. The current legacy SQL
does not reclaim a failed attempt. Retry after transient provider failure needs
a later additive SQL migration/worker that atomically returns
`claimed: true, disposition: retry_claimed` to exactly one worker.

Push failure remains outside the message transaction. It can mark only the push
attempt as failed and must never roll back or downgrade `chat_messages`.

## Secrets and configuration

Set Edge secrets separately for staging and production:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
FIREBASE_SERVICE_ACCOUNT_JSON
PUSH_ALLOWED_WEB_ORIGINS
CHAT_MEDIA_ALLOWED_WEB_ORIGINS
```

Instead of `FIREBASE_SERVICE_ACCOUNT_JSON`, the push function also accepts:

```text
FIREBASE_PROJECT_ID
FIREBASE_CLIENT_EMAIL
FIREBASE_PRIVATE_KEY
```

`SUPABASE_SERVICE_ROLE_KEY`, Firebase private keys and service-account JSON are
server secrets. Never put them in Flutter `--dart-define`, Web assets, logs or
the repository. `PUSH_ALLOWED_WEB_ORIGINS` and
`CHAT_MEDIA_ALLOWED_WEB_ORIGINS` are comma-separated exact origins, for example
`https://app.example.ru`; mobile requests do not send an Origin header.

The Firebase project in the Edge secret must be the same project that issued
the mobile FCM tokens. Web push is not currently configured by the Flutter
client and additionally requires a Web Firebase app, VAPID key and messaging
service worker.

## Staged deployment

1. Apply and validate the chat schema migrations in an isolated staging project.
2. Set staging Edge secrets.
3. Deploy `cleanup-chat-media` and `send-message-push` with JWT verification
   enabled from `supabase/config.toml`.
4. Confirm `chat-media` is private and verify Storage policies with two users.
5. Test cleanup for own unreferenced, referenced, foreign and non-member paths.
6. Test push with enabled, muted, disabled, invalid-token and provider-failure
   recipients.
7. Verify that an FCM failure does not change the persisted chat message.
8. Only after staging evidence and rollback preparation, schedule the production
   deployment separately.

Run local pure Edge tests with:

```text
deno test --allow-env supabase/functions/**/*_test.ts
```

Integration tests still require a migrated Supabase instance because unit tests
cannot prove Storage RLS, Realtime publication or two-account delivery.
