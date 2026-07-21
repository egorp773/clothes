import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/product_media_hydration.dart';
import '../../../core/supabase_config.dart';
import '../../../models/product.dart';

class ListingEditException implements Exception {
  const ListingEditException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'ListingEditException($message, $cause)';
}

class ListingEditRepository {
  static const _draftBucket = 'listing-drafts';
  static const _maxImages = 8;
  static const _maxImageBytes = 15 * 1024 * 1024;

  SupabaseClient? get _client =>
      SupabaseConfig.isInitialized ? SupabaseConfig.client : null;

  Future<Product> submit({
    required Product product,
    required String idempotencyKey,
    required Map<String, dynamic> changes,
    required List<XFile> replacementPhotos,
    required Map<String, bool> confirmations,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw const ListingEditException('Войдите, чтобы изменить объявление');
    }
    if (product.ownerId.isNotEmpty && product.ownerId != user.id) {
      throw const ListingEditException(
        'Можно редактировать только своё объявление',
      );
    }
    if (replacementPhotos.length > _maxImages) {
      throw const ListingEditException('Можно загрузить не больше 8 фото');
    }

    try {
      if (replacementPhotos.isNotEmpty) {
        await _replaceStagedPhotos(
          client: client,
          userId: user.id,
          listingId: product.id,
          idempotencyKey: idempotencyKey,
          photos: replacementPhotos,
        );
      }
      final confirmationVersion = await _activeConfirmationVersion(client);
      final response = await client.functions.invoke(
        'edit-listing',
        body: {
          'listing_id': product.id,
          'idempotency_key': idempotencyKey,
          'changes': changes,
          'replace_photos': replacementPhotos.isNotEmpty,
          'confirmation_version': confirmationVersion,
          'confirmations': confirmations,
        },
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        throw StateError('Authoritative edit was not accepted');
      }
      if (data['edited'] != true) {
        throw const ListingEditException('В объявлении нет изменений');
      }
      final snapshot = data['listing'];
      if (snapshot is! Map) {
        throw StateError('Edited listing snapshot is missing');
      }
      return productFromAuthoritativeSnapshot(
        Map<String, dynamic>.from(snapshot),
        signer: (bucket, objectPath) =>
            client.storage.from(bucket).createSignedUrl(objectPath, 60 * 60),
      );
    } on ListingEditException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['message']?.toString() : null;
      throw ListingEditException(
        _friendlyError(message ?? error.reasonPhrase ?? ''),
        error,
      );
    } catch (error, stackTrace) {
      debugPrint('Listing edit failed: $error\n$stackTrace');
      throw ListingEditException(
        'Не удалось отправить изменения. Попробуйте ещё раз.',
        error,
      );
    }
  }

  @visibleForTesting
  static Future<Product> productFromAuthoritativeSnapshot(
    Map<String, dynamic> snapshot, {
    required StorageMediaSigner signer,
  }) async {
    final hydrated = await hydrateProductMediaSnapshot(
      snapshot,
      signer: signer,
    );
    return Product.fromSupabase(hydrated);
  }

  Future<String> _activeConfirmationVersion(SupabaseClient client) async {
    final row = await client
        .from('seller_confirmation_versions')
        .select('version')
        .eq('status', 'active')
        .lte('effective_at', DateTime.now().toUtc().toIso8601String())
        .order('effective_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final version = row?['version']?.toString().trim() ?? '';
    if (version.isEmpty) {
      throw const ListingEditException(
        'Подтверждения продавца временно недоступны',
      );
    }
    return version;
  }

  Future<void> _replaceStagedPhotos({
    required SupabaseClient client,
    required String userId,
    required String listingId,
    required String idempotencyKey,
    required List<XFile> photos,
  }) async {
    final prefix = '$userId/$listingId';
    final existing = await client.storage.from(_draftBucket).list(path: prefix);
    final oldPaths = existing
        .where((item) => item.name.isNotEmpty)
        .map((item) => '$prefix/${item.name}')
        .toList(growable: false);
    if (oldPaths.isNotEmpty) {
      await client.storage.from(_draftBucket).remove(oldPaths);
    }
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty || bytes.length > _maxImageBytes) {
        throw const ListingEditException(
          'Каждое фото должно быть не больше 15 МБ',
        );
      }
      final extension = _safeExtension(photo.name, photo.path);
      final objectPath =
          '$prefix/${index.toString().padLeft(2, '0')}-'
          '$idempotencyKey$extension';
      await client.storage
          .from(_draftBucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentType(extension),
              cacheControl: '3600',
              upsert: false,
            ),
          );
    }
  }

  static String _safeExtension(String name, String sourcePath) {
    final extension = path
        .extension(name.isNotEmpty ? name : sourcePath)
        .toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' => '.jpg',
      '.png' => '.png',
      '.webp' => '.webp',
      _ => throw const ListingEditException(
        'Поддерживаются только JPEG, PNG и WebP',
      ),
    };
  }

  static String _contentType(String extension) => switch (extension) {
    '.jpg' => 'image/jpeg',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    _ => 'application/octet-stream',
  };

  static String _friendlyError(String code) {
    if (code.contains('listing_has_order_history')) {
      return 'Объявление нельзя менять после создания заказа';
    }
    if (code.contains('seller_not_eligible')) {
      return 'Продажи временно недоступны для этого аккаунта';
    }
    if (code.contains('listing_not_editable')) {
      return 'Это объявление сейчас нельзя редактировать';
    }
    if (code.contains('listing_publication_fields_incomplete')) {
      return 'Заполните обязательные поля объявления';
    }
    return 'Не удалось отправить изменения. Попробуйте ещё раз.';
  }
}
