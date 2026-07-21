# Chat rollout rollback (non-destructive)

Do not automatically reverse `20260720200000_chat_server_authority.sql` and do
not drop `chat_messages`, `chat_thread_members`, new columns, or backfilled
rows. The migration is additive; destructive SQL rollback would risk losing
messages written by the new client.

If staging validation fails:

1. Stop the mobile/web rollout and keep the database in place.
2. Restore the previous Flutter/Edge Function artifacts only.
3. Leave `message_threads.messages` intact and do not resume legacy client
   writes unless a reviewed compatibility patch explicitly requires it.
4. Revoke execute on a faulty new RPC only if it is actively corrupting data;
   do not revoke read access needed by the previous client.
5. Capture `chat_health_check.sql` output and affected thread/message ids
   without copying private message text.
6. Fix forward with a new dated migration. Never edit an already applied
   migration in production.

Before any production rollout, take a verified database backup/PITR checkpoint,
record the applied migration versions, deployed app/function versions and the
Supabase project ref. Restoring a database snapshot is a last resort requiring
separate approval because it can discard messages created after the snapshot.
