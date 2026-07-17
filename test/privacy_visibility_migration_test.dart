import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final moderation = File(
    'supabase/migrations/20260717140000_admin_moderation_foundation.sql',
  ).readAsStringSync();
  final catalog = File(
    'supabase/migrations/20260717143000_catalog_relevance_and_similar_products.sql',
  ).readAsStringSync();
  final outfitAuthors = File(
    'supabase/migrations/20260717152000_outfit_author_avatars.sql',
  ).readAsStringSync();
  final privacy = File(
    'supabase/migrations/20260717154000_privacy_visibility_and_view_retention.sql',
  ).readAsStringSync();
  final schema = File('supabase/schema.sql').readAsStringSync();

  test(
    'hidden products are excluded from public policy and catalogue RPCs',
    () {
      expect(
        privacy,
        contains(
          "status = 'published'\n      and not coalesce(is_hidden, false)",
        ),
      );
      expect(
        schema,
        contains("status = 'published' and not coalesce(is_hidden, false)"),
      );
      expect(
        'not coalesce(product.is_hidden, false)'.allMatches(catalog),
        hasLength(2),
      );
      expect(catalog, contains('not coalesce(candidate.is_hidden, false)'));
    },
  );

  test(
    'catalogue SECURITY DEFINER RPCs enforce bilateral block visibility',
    () {
      expect('security definer'.allMatches(catalog), hasLength(2));
      expect(
        'public.users_are_blocked(auth.uid(), product.seller_id)'.allMatches(
          catalog,
        ),
        hasLength(2),
      );
      expect(
        catalog,
        contains('public.users_are_blocked(auth.uid(), candidate.seller_id)'),
      );
    },
  );

  test('block lookup cannot enumerate relationships between other users', () {
    expect(
      moderation,
      contains('auth.uid() in (first_user_id, second_user_id)'),
    );
    expect(moderation, contains('select auth.uid() is not null'));
    expect(
      privacy,
      contains('from public.blocked_users blocked'),
      reason: 'Internal order enforcement must not depend on caller-bound RPC',
    );
  });

  test('shipping address removal is guarded by a private-source preflight', () {
    final preflight = privacy.indexOf(
      'shipping_address_privacy_preflight_failed',
    );
    final cleanup = privacy.indexOf(
      "update public.products\nset shipping_address = ''",
    );

    expect(preflight, greaterThanOrEqualTo(0));
    expect(cleanup, greaterThan(preflight));
    expect(privacy, contains('shipping_address_private_source_required'));
    expect(privacy, contains('published_shipping_address_required'));
    expect(
      privacy,
      contains("array['cdek', 'russian_post', 'yandex_delivery']::text[]"),
    );
    expect(
      privacy,
      contains(
        'shipping_address, shipping_address_id, seller_id, status, '
        'delivery_methods',
      ),
    );
    expect(schema, contains('shipping_address_privacy_preflight_failed'));
    expect(schema, contains('shipping_address_private_source_required'));
  });

  test('orphan view cleanup is followed by authoritative recounts', () {
    final productDelete = privacy.indexOf(
      'delete from public.product_views view_event',
    );
    final outfitDelete = privacy.indexOf(
      'delete from public.outfit_views view_event',
    );
    final productRecount = privacy.indexOf(
      'update public.products product\nset views_count =',
      productDelete,
    );
    final outfitRecount = privacy.indexOf(
      'update public.outfits outfit\nset views_count =',
      outfitDelete,
    );

    expect(productRecount, greaterThan(productDelete));
    expect(outfitRecount, greaterThan(outfitDelete));
    expect(privacy, contains('product_views_viewer_id_fkey'));
    expect(privacy, contains('outfit_views_viewer_id_fkey'));
    expect(privacy, contains('on delete cascade'));
  });

  test('outfit author snapshots cannot be replaced by UPDATE payloads', () {
    const protectedTrigger =
        'before insert or update of author_name, author_handle, '
        'author_avatar_url';

    expect(outfitAuthors, contains(protectedTrigger));
    expect(outfitAuthors, contains('new.author_name := old.author_name;'));
    expect(outfitAuthors, contains('new.author_handle := old.author_handle;'));
    expect(
      outfitAuthors,
      contains('new.author_avatar_url := old.author_avatar_url;'),
    );
    expect(schema, contains(protectedTrigger));
    expect(schema, contains('author_avatar_url text not null default'));
    expect(
      outfitAuthors,
      contains(
        "where not exists (\n  select 1\n  from public.profiles profile\n"
        '  where profile.id = outfit.owner_id',
      ),
    );
    expect(schema, contains("author_name = 'Автор'"));
    expect(schema, contains("author_handle = '@user'"));
  });
}
