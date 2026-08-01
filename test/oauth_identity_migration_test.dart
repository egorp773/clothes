import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy OAuth identities are backfilled without replacing mappings', () {
    final migration = File(
      'supabase/migrations/'
      '20260801232047_backfill_legacy_oauth_identities.sql',
    ).readAsStringSync();

    for (final legacyId in ['yandex_id', 'vk_id', 'telegram_id']) {
      expect(migration, contains("raw_user_meta_data ->> '$legacyId'"));
    }
    expect(
      migration,
      contains("account.raw_user_meta_data ->> 'provider' = legacy.provider"),
    );
    expect(
      migration,
      contains('existing.provider_subject = candidate.provider_subject'),
    );
    expect(migration, contains('existing.user_id = candidate.user_id'));
    expect(
      migration,
      contains('partition by candidate.provider, candidate.provider_subject'),
    );
    expect(
      migration,
      contains('partition by candidate.provider, candidate.user_id'),
    );
    expect(
      migration,
      contains(
        'order by candidate.created_at asc nulls last, candidate.user_id',
      ),
    );
    expect(migration, contains('on conflict do nothing;'));
    expect(migration, isNot(contains('on conflict do update')));
  });
}
