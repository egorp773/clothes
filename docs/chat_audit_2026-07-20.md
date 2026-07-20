# Chat reliability and security audit — 2026-07-20

Scope: Flutter client, Supabase migrations/RLS/RPC/Realtime, private chat
media, and `send-message-push`. Production was inspected read-only and was not
modified.

## Executive diagnosis

| Check | Actual state | Problem | Resolution |
|---|---|---|---|
| Flutter/server schema | Linked project is migrated only through `20260719190000`; the repository has later pending migrations | Runtime code and deployed contracts can differ | Stage the full ordered chain; never push the pending chain blind to production |
| Thread creation | Flutter directly upserts `message_threads` | Client controls participants/product metadata; concurrent creation has no authoritative winner | Server `create_or_get_*` RPCs with advisory locks and a unique conversation key |
| Message send | Flutter separately upserts a thread and then `chat_messages` | First message, preview, and unread are not one transaction | Idempotent `send_chat_message` transaction returning the stored row |
| Message identity | `chat_messages.id` doubles as the optimistic id | A timeout cannot be reconciled reliably | Separate `client_message_id` and unique `(thread, sender, client id)` |
| Legacy messages | Normalized rows coexist with `message_threads.messages` JSONB | The first backfill is unsafe to rerun for entries without ids | Stable legacy source key; keep JSONB read-only until a later verified removal |
| Realtime | One channel exists for chat tables | Error/timeout is logged but not reconnected; no gap cursor | One lifecycle-aware channel plus post-connect gap sync |
| Snapshot sync | Every polling pass loads every message in every thread | High load and a stale snapshot can erase a newer incoming Realtime event | Thread summaries separately; latest page on open; cursor history/gap merge |
| Outbox | `_saveThreadsLocal` removes the cache | Pending/failed text and retry identity are lost on restart | Small per-user outbox only; server remains the source of delivered messages |
| Unread | Recomputed by downloading all messages | Race-prone and expensive | Per-user server counter and last-read pointer, mutated only by RPC |
| Chat media | Private bucket/path contract exists | Ambiguous send timeout can delete an object already referenced by a committed row | Reconcile by client id before cleanup; server-verified unreferenced cleanup |
| Push | JWT/membership/sender/mute checks exist in Edge | Live lacks later push-dedupe migration; failed claims were terminal | Retry-aware atomic claim; push remains outside the message transaction |
| Group creation | Client sends `p_client_thread_id`; draft SQL named the same argument `p_group_avatar` | PostgREST cannot resolve the RPC by named arguments | RPC now accepts and validates the client UUID and returns the same group on retry |
| Unread Realtime | Server increments unread and Flutter also incremented on message INSERT | State/message callback ordering could show unread `2` for one message | Flutter no longer owns the counter; member-state RPC/table is authoritative |
| History pagination | Cursor queries existed but the chat screen never requested them | Messages older than the first 50 were unreachable | Top-scroll loads `(created_at,id)` pages and preserves scroll position |
| Push recipients | Edge Function derived recipients from legacy `member_ids` | A stale/left legacy member could receive a notification | Recipients now come only from active `chat_thread_members` rows |

The primary failure is a split-brain write path: client-side table writes,
Realtime events, and a periodic full snapshot all compete to update the same
in-memory thread. This is not safely repairable with a UI-only retry.

## Confirmed live state

The Supabase CLI is linked to project `clothes` (reference
`hbwzxtwcjlsfldjcqudt`). A read-only migration comparison showed that remote
migrations stop at `20260719190000`; local migrations beginning at
`20260719200000` are pending. Read-only database statistics estimated:

- 7 `message_threads` rows;
- 40 `chat_messages` rows;
- 17 `chat_thread_member_state` rows.

The remote schema dump could not run because the local Docker engine is not
available. Therefore policies, grants, publication membership, and data
anomalies must be confirmed by `supabase/diagnostics/chat_health_check.sql` in
the SQL editor or staging. The diagnostic is metadata/data read-only.

## Concrete failure paths

### Partially created product conversation

The client creates a thread and sends its canned first message in separate
requests. If the thread insert commits but the message response fails, the
local thread is discarded while the empty remote thread remains. The next
attempt finds that thread and does not recreate the first message.

### Incoming message disappears temporarily

A full synchronization starts, then an incoming Realtime insert is applied.
When the older full response commits, the existing merge preserves only local
outgoing messages. The new incoming message can disappear until another poll.

### Ambiguous media timeout

An object upload and message insert can both commit, while the client loses the
HTTP response. The previous recovery path treats that as an insert failure and
deletes the object. The durable message then references a missing private file.

### Restart loses retryable text

Delivered history is correctly recoverable from Supabase, but there is no
durable outbox. Pending and failed messages are removed with the generic chat
cache and cannot be retried with the same id after restart.

## Target compatibility model

- `message_threads` stores summary/identity, not a rewritten message array.
- `chat_thread_members` is the canonical membership relation; legacy
  `member_ids` remains during rollout.
- `chat_messages` is append-oriented and has a distinct client id.
- `chat_thread_member_state` is the existing equivalent of
  `chat_thread_user_state` and owns unread/read/preferences.
- Flutter creates threads and messages only through authenticated RPCs.
- Realtime is the fast path; cursor sync is the recovery path.
- Local storage contains only a bounded, user-scoped outbox, never signed URLs
  or the complete history.
- Storage rows keep bucket/path. Signed URLs are generated at read time.
- Push failure cannot roll back or downgrade a persisted chat message.

## Deployment gate

1. Run a clean migration reset and pgTAP in CI/staging.
2. Run the read-only health diagnostic against staging, then review every
   anomaly before constraints/grant changes.
3. Deploy Flutter compatible with both old reads and new RPC responses.
4. Apply the ordered migration chain to staging only.
5. Deploy Edge functions and required secrets.
6. Execute `docs/chat_smoke_test.md` with two real test accounts/devices.
7. Re-run the health diagnostic and compare counts/duplicates/orphans.
8. Schedule a separately approved production window and rollback checkpoint.

Rollback procedure: `docs/chat_rollback.md`. It deliberately avoids dropping
the additive columns/tables or deleting the normalized/backfilled messages.

Passing `flutter analyze` alone is not a release decision. The production gate
requires the SQL/RLS tests and observed two-client Realtime/restart behavior.
