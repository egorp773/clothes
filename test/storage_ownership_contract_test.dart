import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile product media uploads stay in owner-scoped namespaces', () {
    final repository = File('lib/data/app_repository.dart').readAsStringSync();
    final listingRepository = File(
      'lib/features/listing_publish/data/listing_publish_repository.dart',
    ).readAsStringSync();
    final mediaCommandMigration = File(
      'supabase/migrations/20260720191000_outfit_media_command.sql',
    ).readAsStringSync();
    final listingStorageMigration = File(
      'supabase/migrations/20260719201000_c2c_listing_risk_storage.sql',
    ).readAsStringSync();

    expect(repository, contains("'\${user.id}/avatar/\${_uuid.v4()}"));
    expect(repository, contains("'\${user!.id}/\$id/\${_uuid.v4()}"));
    expect(
      listingRepository,
      contains(
        "return '\$normalizedUserId/\$normalizedListingId/"
        "\$normalizedFileName';",
      ),
    );
    expect(
      listingRepository,
      contains("static const _bucketName = 'listing-drafts'"),
    );
    expect(mediaCommandMigration, contains("'/avatar/[^/]+\$'"));
    expect(
      mediaCommandMigration,
      contains(
        "'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-"
        "[0-9a-f]{12}/[^/]+\$'",
      ),
    );
    expect(listingStorageMigration, contains("bucket_id = 'listing-drafts'"));
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
