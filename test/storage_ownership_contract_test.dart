import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile product media uploads stay in owner-scoped namespaces', () {
    final repository = File('lib/data/app_repository.dart').readAsStringSync();
    final listingRepository = File(
      'lib/features/listing_publish/data/listing_publish_repository.dart',
    ).readAsStringSync();

    expect(repository, contains("folder: 'avatars/\$currentUserId'"));
    expect(repository, contains("folder: 'accessories/\${user!.id}'"));
    expect(repository, isNot(contains("folder: 'accessories/default'")));
    expect(
      listingRepository,
      contains("'users/\${user.id}/listings/\${draft.id}/"),
    );
  });

  test('shared accessory catalogue cannot be written by a mobile user', () {
    final repository = File('lib/data/app_repository.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20260717155100_product_media_storage_ownership.sql',
    ).readAsStringSync();

    expect(
      repository,
      contains("_authError = 'Общие аксессуары добавляются после модерации'"),
    );
    expect(
      migration,
      contains("scope = 'private' and owner_id = (select auth.uid())"),
    );
  });
}
