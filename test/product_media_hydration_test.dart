import 'package:clothes/core/product_media_hydration.dart';
import 'package:clothes/features/listing_edit/data/listing_edit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses storage and expired signed product image references', () {
    final canonical = parseProductMediaObject(
      'storage://product-images/user-id/listing-id/main.jpg',
    );
    expect(canonical?.bucket, 'product-images');
    expect(canonical?.objectPath, 'user-id/listing-id/main.jpg');

    final signed = parseProductMediaObject(
      'https://project.supabase.co/storage/v1/object/sign/product-images/'
      'seller%2Flisting%2Fold.jpg?token=expired',
    );
    expect(signed?.bucket, 'product-images');
    expect(signed?.objectPath, 'seller/listing/old.jpg');
  });

  test(
    'hydrates all product media fields and caches duplicate signing',
    () async {
      final calls = <String>[];
      final hydrated = await hydrateProductMediaSnapshot(
        {
          'main_image': 'storage://product-images/seller/listing/main.jpg',
          'image': 'storage://product-images/seller/listing/main.jpg',
          'images': [
            'storage://product-images/seller/listing/main.jpg',
            'https://cdn.example/gallery.jpg',
          ],
          'outfit_images': ['storage://outfit-images/seller/outfit/look.webp'],
        },
        signer: (bucket, objectPath) async {
          calls.add('$bucket/$objectPath');
          return 'https://signed.example/$bucket/$objectPath?fresh=1';
        },
      );

      expect(
        hydrated['main_image'],
        'https://signed.example/product-images/seller/listing/main.jpg?fresh=1',
      );
      expect(hydrated['image'], hydrated['main_image']);
      expect(hydrated['images'], [
        hydrated['main_image'],
        'https://cdn.example/gallery.jpg',
      ]);
      expect(hydrated['outfit_images'], [
        'https://signed.example/outfit-images/seller/outfit/look.webp?fresh=1',
      ]);
      expect(calls, hasLength(2));
    },
  );

  test(
    'recognized private reference fails closed when signing fails',
    () async {
      final resolved = await resolveProductMediaReference(
        'storage://product-images/seller/listing/main.jpg',
        signer: (_, _) => throw StateError('network unavailable'),
      );
      expect(resolved, isEmpty);

      final untouched = await resolveProductMediaReference(
        'https://cdn.example/main.jpg',
        signer: (_, _) => throw StateError('must not run'),
      );
      expect(untouched, 'https://cdn.example/main.jpg');
    },
  );

  test(
    'listing edit snapshot is hydrated before Product is constructed',
    () async {
      final product =
          await ListingEditRepository.productFromAuthoritativeSnapshot(
            {
              'id': '11111111-1111-1111-1111-111111111111',
              'seller_id': '22222222-2222-2222-2222-222222222222',
              'title': 'Jacket',
              'main_image':
                  'storage://product-images/22222222-2222-2222-2222-222222222222/'
                  '11111111-1111-1111-1111-111111111111/00-main.jpg',
              'images': [
                'storage://product-images/22222222-2222-2222-2222-222222222222/'
                    '11111111-1111-1111-1111-111111111111/00-main.jpg',
              ],
            },
            signer: (bucket, objectPath) async =>
                'https://signed.example/$bucket/$objectPath?token=fresh',
          );

      expect(product.image, startsWith('https://signed.example/'));
      expect(product.images.single, product.image);
      expect(product.image, isNot(startsWith('storage://')));
    },
  );
}
