import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase migration versions are unique and sortable', () {
    final files =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(files, isNotEmpty);

    final versions = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final match = RegExp(r'^(\d{14})_[a-z0-9_]+\.sql$').firstMatch(name);
      expect(match, isNotNull, reason: 'Invalid migration filename: $name');
      versions.add(match!.group(1)!);
    }

    expect(versions.toSet().length, versions.length);
    expect(versions, orderedEquals([...versions]..sort()));
  });

  test('account deletion cannot bypass owned storage cleanup', () {
    final baseline = File(
      'supabase/migrations/20260710000000_core_schema_baseline.sql',
    ).readAsStringSync();
    final checkoutMigration = File(
      'supabase/migrations/'
      '20260717133000_view_integrity_and_server_checkout.sql',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20260717155000_account_deletion_storage_contract.sql',
    ).readAsStringSync();

    for (final source in [baseline, checkoutMigration]) {
      expect(
        source,
        isNot(
          contains(
            'grant execute on function public.delete_current_user() '
            'to authenticated',
          ),
        ),
      );
    }
    expect(
      checkoutMigration,
      contains(
        'revoke all on function public.delete_current_user()\n'
        '  from public, anon, authenticated;',
      ),
    );
    expect(migration, contains('list_account_deletion_storage_objects'));
    expect(migration, contains('from public.message_threads doomed_thread'));
    expect(
      migration,
      contains("doomed_thread.id = split_part(stored.name, '/', 2)"),
    );
    expect(
      migration,
      contains(
        'p_user_id in (\n'
        '                doomed_thread.buyer_id,\n'
        '                doomed_thread.seller_id\n'
        '              )',
      ),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.delete_current_user()\n'
        '  from public, anon, authenticated;',
      ),
    );
  });

  test('seller reviews require one completed buyer order per product', () {
    final migration = File(
      'supabase/migrations/'
      '20260717155200_seller_review_integrity.sql',
    ).readAsStringSync();

    expect(migration, contains('seller_reviews_buyer_product_unique_idx'));
    expect(migration, contains('(buyer_id, product_id)'));
    expect(migration, contains("completed_order.status = 'completed'"));
    expect(
      migration,
      contains('completed_order.buyer_id = seller_reviews.buyer_id'),
    );
    expect(migration, contains('(select auth.uid()) = buyer_id'));
    expect(migration, contains('buyer_id <> seller_id'));
  });

  test('checkout migration normalizes legacy UUID order ids', () {
    final migration = File(
      'supabase/migrations/'
      '20260717151000_checkout_delivery_contract.sql',
    ).readAsStringSync();

    expect(migration, contains("and data_type <> 'text'"));
    expect(migration, contains('checkout_order_fk_restore'));
    expect(
      migration,
      contains('pg_get_constraintdef(constraint_info.oid, true)'),
    );
    expect(migration, contains('alter column id type text using id::text'));
    expect(
      migration,
      contains(
        'order_id text not null references public.orders(id) '
        'on delete cascade',
      ),
    );
  });
}
