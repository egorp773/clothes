import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat mutations are restricted to narrow server contracts', () {
    final migration = File(
      'supabase/migrations/20260717153000_chat_integrity_and_member_state.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains('revoke update on public.message_threads from authenticated'),
    );
    expect(
      migration,
      contains('revoke update on public.chat_messages from authenticated'),
    );
    expect(
      migration,
      contains(
        'revoke insert, update on public.chat_thread_member_state '
        'from authenticated',
      ),
    );
    expect(migration, contains('update_chat_thread_settings'));
    expect(migration, contains('edit_chat_message'));
    expect(migration, contains('delete_chat_message'));
    expect(migration, contains('chat_attachment_owner_mismatch'));
    expect(migration, contains("new.last_message := '';"));
    expect(migration, contains('new.updated_at := now();'));

    final legacyBackfill = migration.indexOf('with legacy_thread_state as');
    final legacyDrop = migration.indexOf('drop column if exists is_pinned');
    expect(legacyBackfill, greaterThanOrEqualTo(0));
    expect(legacyDrop, greaterThan(legacyBackfill));
    expect(migration, contains("to_jsonb(thread)->>'draft'"));
    expect(migration, contains('thread.created_by = any(thread.member_ids)'));
    expect(migration, contains('thread.buyer_id = any(thread.member_ids)'));
    expect(migration, isNot(contains("new.draft := '';")));
  });

  test('Flutter repository does not directly mutate server chat rows', () {
    final repository = File('lib/data/app_repository.dart').readAsStringSync();

    expect(repository, isNot(contains('_syncLastMessagePreview')));
    expect(
      repository,
      isNot(
        contains(
          ".from('message_threads')\n          .update({'draft': draft})",
        ),
      ),
    );
    expect(repository, contains("'update_chat_thread_settings'"));
    expect(repository, contains("'edit_chat_message'"));
    expect(repository, contains("'delete_chat_message'"));
  });

  test('authoritative chat commands are idempotent and match client RPCs', () {
    final migration = File(
      'supabase/migrations/20260720200000_chat_server_authority.sql',
    ).readAsStringSync();
    final remote = File(
      'lib/features/chat/chat_remote_data_source.dart',
    ).readAsStringSync();

    expect(migration, contains('p_client_thread_id text'));
    expect(remote, contains("'p_client_thread_id': clientThreadId"));
    expect(migration, contains("hashtextextended('chat:group:' || thread_id"));
    expect(migration, contains('if not thread_has_messages then'));
    expect(
      migration,
      contains(
        'on public.chat_messages (thread_id, sender_id, client_message_id)',
      ),
    );
  });

  test(
    'message push respects mute, validates sender, and bounds device fan-out',
    () {
      final function = File(
        'supabase/functions/send-message-push/index.ts',
      ).readAsStringSync();

      expect(function, contains('.from("chat_thread_member_state")'));
      expect(function, contains('.from("chat_thread_members")'));
      expect(function, contains('!muted.has(recipientId)'));
      expect(function, contains('message.sender_id !== senderId'));
      expect(function, contains('maxPushTokensPerRecipient = 5'));
      expect(function, contains('parsePushClaimResponse(data)'));
      expect(function, isNot(contains('.select("id,sender_id,text')));
    },
  );
}
