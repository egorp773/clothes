# Chat smoke test (two accounts)

This runbook validates a deployed **staging** chat backend. Do not use real
customer accounts and do not apply migrations to production as part of this
test.

## Preconditions

- The pending migration chain has passed on a clean local/staging database.
- Both builds use the same `SUPABASE_URL` project and current anon key.
- Account A and account B have active Auth sessions and marketplace access.
- Account B owns a visible product; account A does not own it.
- Realtime contains `chat_messages`, `message_threads`, and
  `chat_thread_member_state`.
- For push checks, both devices have distinct registered tokens and account B
  has not muted the conversation.

Record for every run: build SHA, platform pair, Supabase project ref, UTC start
time, thread id, both user ids, and any debug chat diagnostic error code. Never
record access/refresh tokens or private message text.

## Product conversation and first message

1. Keep account B open on the inbox on client B.
2. On client A, open B's product and tap **Write to seller** once.
3. Verify one product conversation opens and the initial message appears as
   pending, then sent.
4. On client B, verify the thread and message appear without refresh or app
   restart, and unread is exactly one.
5. Open the thread on B. Verify unread becomes zero only for B.
6. Reply from B. Verify A receives the reply without refresh.
7. Tap **Write to seller** again and simultaneously from a second A client.
   Verify both clients resolve to the same thread and no duplicate initial
   message is created for the same `client_message_id`.

## Direct conversation

1. On A, find B from the user search and create a direct conversation.
2. Simultaneously attempt the inverse creation from B to A.
3. Verify both clients receive the same thread id.
4. Send a first and second message in quick succession from A.
5. Verify ordering is stable on both clients and survives both app restarts.
6. Verify a direct conversation with self is rejected with `validation_error`.

## Outbox, retry, and session refresh

1. Disable networking on A and send a unique text.
2. Verify the text remains visible as failed and is not cleared from the UI.
3. Force-close and reopen A. Verify the failed entry is still available only
   under account A.
4. Restore networking and retry. Verify the same `client_message_id` is used
   and exactly one server message exists.
5. Repeat while the access token is close to expiry; verify refresh completes
   and the message is not duplicated.
6. Start a send and sign out before completion. Sign in as B on the same
   client and verify A's outbox/messages never appear in B's local state.

## Realtime reconnect and gap sync

1. With the thread open on A, background A and keep B active.
2. Send two messages from B. Verify A does not mark them read while backgrounded.
3. Disable/re-enable networking on A, then foreground it.
4. Verify one Realtime channel is recreated and gap sync restores both messages
   without duplicates.
5. Verify unread is correct before opening the thread and becomes zero after
   the visible thread is marked read.
6. Send another message after recovery and verify it arrives immediately.

## History pagination

1. Use a staging thread with more than 100 messages, including messages sharing
   the same timestamp.
2. Open it and verify only the latest page is requested initially.
3. Scroll to the top twice. Verify older pages load using `(created_at, id)` and
   scroll position does not jump.
4. Verify no duplicate or missing row exists at either page boundary.

## Images and video

1. Send a supported image on each client type in the matrix below.
2. Verify pending/send state, rendering on B, and rendering after signed URL
   expiry/restart.
3. Repeat with a supported video below the configured bucket limit.
4. Simulate a timeout immediately after upload. Retry the message and verify
   one DB row and one referenced Storage object remain.
5. Simulate message validation failure. Verify cleanup removes only the proven
   unreferenced object and cannot remove another member's file.
6. Sign out during upload and verify the entry is failed/retryable and does not
   leak into the next account.

## Edit, soft delete, reply, and push

1. Reply to an existing message and verify the reply target is from the same
   thread on both clients.
2. Edit A's message; verify Realtime updates B without adding a row.
3. Soft-delete A's message; verify the placeholder remains and evidence/history
   is not physically removed.
4. Verify A cannot edit or delete B's message.
5. Close/background A, send from B, and verify exactly one push reaches A.
6. Tap the push and verify the correct thread is fetched and opened.
7. Mute the thread on A and verify later messages still persist/realtime-sync
   but do not generate push.
8. Temporarily break push provider configuration in staging. Verify the chat
   message remains sent and recoverable even though push reports failure.

## Security negatives

- A third account C cannot select A/B's thread or messages.
- C cannot invoke `send_chat_message` for that thread.
- A cannot provide B as `sender_id`; the server derives the actor from JWT.
- A cannot add itself to an unrelated thread through direct table insert.
- A cannot reduce B's unread counter or mutate B's thread state.
- A cannot read, sign, overwrite, or delete another thread's media object.
- Product chat resolves seller id from the server product row, not the request.

## Platform matrix

Run the full text/realtime/restart path for:

- Android + Android
- Web + Android
- Web + Web

Run iOS + Android and iOS + iOS when an iOS build/signing environment is
available. Media picker, background reconnect, APNs delivery, and push deep
links require real devices; emulator-only results are not sufficient for the
production gate.

The release gate passes only when all observed message ids, client message ids,
unread transitions, and Storage paths are consistent across both clients and
the server diagnostics query reports no new anomalies.
