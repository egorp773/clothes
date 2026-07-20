import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_config.dart';
import '../models/listing_draft.dart';

class ListingPublishException implements Exception {
  const ListingPublishException(this.userMessage, [this.cause]);

  final String userMessage;
  final Object? cause;

  @override
  String toString() => 'ListingPublishException($userMessage, $cause)';
}

class ListingDeliveryDefaults {
  const ListingDeliveryDefaults({
    this.addresses = const [],
    this.deliveryMethods = const [],
  });

  final List<ListingAddress> addresses;
  final List<String> deliveryMethods;
}

enum ListingPublicationDisposition { published, heldForReview }

class ListingPublishResult {
  const ListingPublishResult(this.disposition);

  final ListingPublicationDisposition disposition;

  bool get isPublished =>
      disposition == ListingPublicationDisposition.published;
}

class ListingPublishRepository {
  ListingPublishRepository({
    required this.sellerName,
    required this.sellerHandle,
    required this.fallbackCity,
    this.assertCanPublish,
  });

  static const _draftsKeyPrefix = 'listing_publish_drafts_v1';
  static const _addressesKeyPrefix = 'listing_publish_addresses_v1';
  static const _deliveryKeyPrefix = 'listing_publish_delivery_v1';
  static const _bucketName = 'listing-drafts';

  final String sellerName;
  final String sellerHandle;
  final String fallbackCity;
  final Future<String?> Function()? assertCanPublish;

  SharedPreferences? _preferences;

  SupabaseClient? get _client =>
      SupabaseConfig.isInitialized ? SupabaseConfig.client : null;

  String get sellerId => _client?.auth.currentUser?.id ?? '';

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<List<ListingDraft>> loadLocalDrafts() async {
    // Drafts contain photos, declarations and delivery data. SharedPreferences
    // is not an appropriate persistence boundary for that material. Until an
    // encrypted draft store is introduced, recovery is deliberately disabled.
    await _purgeLegacySensitivePreferences();
    await _purgeLegacyDraftDirectories();
    return const [];
  }

  Future<void> saveLocalDraft(ListingDraft draft) async {
    await _purgeLegacySensitivePreferences();
    draft.updatedAt = DateTime.now().toUtc();
  }

  Future<void> removeLocalDraft(String draftId) =>
      _purgeLegacySensitivePreferences();

  Future<ListingPhoto> stagePhoto({
    required ListingDraft draft,
    required XFile source,
  }) async {
    final id = const Uuid().v4();
    try {
      if (kIsWeb) {
        final bytes = await source.readAsBytes();
        final mime = _mimeType(source.name, source.path);
        return ListingPhoto(
          id: id,
          localPath: 'data:$mime;base64,${base64Encode(bytes)}',
        );
      }

      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        path.join(support.path, 'listing_drafts', draft.id),
      );
      await directory.create(recursive: true);
      final extension = _extension(source.name, source.path);
      final targetPath = path.join(directory.path, '$id$extension');
      final sourceFile = File(source.path);
      if (source.path.isNotEmpty && await sourceFile.exists()) {
        await sourceFile.copy(targetPath);
      } else {
        await File(targetPath).writeAsBytes(await source.readAsBytes());
      }
      return ListingPhoto(id: id, localPath: targetPath);
    } catch (error, stackTrace) {
      debugPrint('Listing photo staging error: $error\n$stackTrace');
      throw ListingPublishException(
        'Не удалось сохранить фотографию на устройстве',
        error,
      );
    }
  }

  Future<void> ensureRemoteDraft(ListingDraft draft) async {
    await _saveRemoteDraft(draft);
  }

  @visibleForTesting
  static String canonicalDraftStoragePath({
    required String userId,
    required String listingId,
    required String fileName,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedListingId = listingId.trim();
    final normalizedFileName = fileName.trim();
    if (normalizedUserId.isEmpty ||
        normalizedListingId.isEmpty ||
        normalizedFileName.isEmpty ||
        normalizedUserId.contains('/') ||
        normalizedListingId.contains('/') ||
        normalizedFileName.contains('/') ||
        normalizedFileName.contains('\\') ||
        normalizedFileName == '.' ||
        normalizedFileName == '..') {
      throw ArgumentError('Invalid canonical listing draft path');
    }
    return '$normalizedUserId/$normalizedListingId/$normalizedFileName';
  }

  static bool isOwnedDraftStoragePath({
    required String storagePath,
    required String userId,
    required String listingId,
  }) =>
      storagePath.startsWith('${userId.trim()}/${listingId.trim()}/') &&
      storagePath.split('/').length == 3;

  Future<bool> uploadPhoto(ListingDraft draft, ListingPhoto photo) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return false;
    if (photo.remoteUrl.isNotEmpty) return true;

    photo.uploadStatus = ListingPhotoUploadStatus.uploading;
    try {
      final bytes = await _readPhotoBytes(photo.localPath);
      final extension = _extension(photo.localPath, photo.localPath);
      final storagePath = canonicalDraftStoragePath(
        userId: user.id,
        listingId: draft.id,
        fileName: '${photo.id}$extension',
      );
      await client.storage
          .from(_bucketName)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
      photo.storagePath = storagePath;
      // A private object path is an upload receipt, not a public URL. The
      // publish Edge function promotes/copies it and returns display URLs.
      photo.remoteUrl = storagePath;
      photo.uploadStatus = ListingPhotoUploadStatus.uploaded;
      await syncRemoteDraft(draft);
      debugPrint('Listing photo uploaded: ${photo.id}');
      return true;
    } catch (error, stackTrace) {
      photo.uploadStatus = ListingPhotoUploadStatus.failed;
      debugPrint('Listing photo upload error: $error\n$stackTrace');
      return false;
    }
  }

  Future<void> deletePhoto(ListingDraft draft, ListingPhoto photo) async {
    if (draft.status == ListingStatus.published) return;
    final client = _client;
    final userId = client?.auth.currentUser?.id ?? '';
    if (client != null &&
        photo.storagePath.isNotEmpty &&
        isOwnedDraftStoragePath(
          storagePath: photo.storagePath,
          userId: userId,
          listingId: draft.id,
        )) {
      try {
        await client.storage.from(_bucketName).remove([photo.storagePath]);
      } catch (error, stackTrace) {
        debugPrint('Listing photo remote delete error: $error\n$stackTrace');
      }
    }
    await _deleteLocalPhoto(photo.localPath);
  }

  Future<void> syncRemoteDraft(ListingDraft draft) async {
    await _saveRemoteDraft(draft);
  }

  Future<void> _saveRemoteDraft(ListingDraft draft) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw const ListingPublishException(
        'Для сохранения черновика требуется защищённое подключение',
      );
    }
    try {
      await client.rpc(
        'save_listing_draft',
        params: {
          'p_listing_id': draft.id,
          'p_payload': _publishableListingPayload(draft),
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Safe listing draft sync error: $error\n$stackTrace');
      throw ListingPublishException(
        'Не удалось безопасно сохранить черновик',
        error,
      );
    }
  }

  Future<ListingDeliveryDefaults> loadDeliveryDefaults() async {
    await _purgeLegacySensitivePreferences();
    const localAddresses = <ListingAddress>[];
    const localDelivery = <String>[];
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return ListingDeliveryDefaults(
        addresses: localAddresses,
        deliveryMethods: localDelivery,
      );
    }
    try {
      final responses = await Future.wait<dynamic>([
        client
            .from('listing_addresses')
            .select()
            .eq('user_id', user.id)
            .order('is_default', ascending: false),
        client
            .from('listing_publish_preferences')
            .select('delivery_methods')
            .eq('user_id', user.id)
            .maybeSingle(),
      ]);
      final addresses = (responses[0] as List<dynamic>)
          .whereType<Map>()
          .map(
            (item) => ListingAddress.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      final preferences = responses[1];
      final methods = preferences is Map
          ? (preferences['delivery_methods'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList()
          : localDelivery;
      // Delivery details must not be copied into SharedPreferences. The
      // server-owned rows above are the only persistence boundary until an
      // encrypted local store is introduced.
      await _saveLocalAddresses(addresses);
      return ListingDeliveryDefaults(
        addresses: addresses.isEmpty ? localAddresses : addresses,
        deliveryMethods: methods,
      );
    } catch (error, stackTrace) {
      debugPrint('Listing delivery defaults error: $error\n$stackTrace');
      return ListingDeliveryDefaults(
        addresses: localAddresses,
        deliveryMethods: localDelivery,
      );
    }
  }

  Future<ListingAddress> saveAddress({required ListingDraft draft}) async {
    final address = ListingAddress(
      id: draft.shippingAddressId.isEmpty
          ? const Uuid().v4()
          : draft.shippingAddressId,
      city: draft.city.trim(),
      address: draft.shippingAddress.trim(),
      isDefault: draft.saveAddressAsDefault,
    );
    var addresses = await _loadLocalAddresses();
    if (address.isDefault) {
      addresses = addresses
          .map(
            (item) => ListingAddress(
              id: item.id,
              city: item.city,
              address: item.address,
            ),
          )
          .toList();
    }
    addresses.removeWhere((item) => item.id == address.id);
    addresses.insert(0, address);
    await _saveLocalAddresses(addresses);

    final client = _client;
    final user = client?.auth.currentUser;
    if (client != null && user != null) {
      try {
        if (address.isDefault) {
          await client
              .from('listing_addresses')
              .update({'is_default': false})
              .eq('user_id', user.id);
        }
        await client.from('listing_addresses').upsert({
          ...address.toJson(),
          'user_id': user.id,
        }, onConflict: 'id');
        await client.from('listing_publish_preferences').upsert({
          'user_id': user.id,
          'delivery_methods': draft.deliveryMethods,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id');
      } catch (error, stackTrace) {
        debugPrint('Listing address sync error: $error\n$stackTrace');
      }
    }
    return address;
  }

  Future<void> deleteDraft(ListingDraft draft) async {
    if (draft.status == ListingStatus.published) return;
    for (final photo in List<ListingPhoto>.of(draft.photos)) {
      await deletePhoto(draft, photo);
    }
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client.rpc(
          'archive_own_listing',
          params: {'p_listing_id': draft.id},
        );
      } catch (error, stackTrace) {
        debugPrint('Listing draft archive error: $error\n$stackTrace');
        throw ListingPublishException(
          'Не удалось удалить серверный черновик',
          error,
        );
      }
    }
    await removeLocalDraft(draft.id);
    await _deleteDraftDirectory(draft.id);
  }

  Future<ListingPublishResult> publish(ListingDraft draft) async {
    final validationError = draft.validateForPublish();
    if (validationError != null) {
      throw ListingPublishException(validationError);
    }
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw const ListingPublishException(
        'Для публикации нужно подключение к интернету',
      );
    }
    final eligibilityError = await assertCanPublish?.call();
    if (assertCanPublish == null || eligibilityError != null) {
      throw ListingPublishException(
        eligibilityError ?? 'Не удалось проверить право продавца на публикацию',
      );
    }

    final savedAddress = await saveAddress(draft: draft);
    draft.shippingAddressId = savedAddress.id;
    await _saveRemoteDraft(draft);
    var disposition = ListingPublicationDisposition.published;
    try {
      final response = await client.functions.invoke(
        'publish-listing',
        body: buildPublishRequestBody(draft),
      );
      final data = response.data;
      final published =
          response.status >= 200 &&
          response.status < 300 &&
          data is Map &&
          (data['published'] == true || data['status'] == 'published');
      final heldForReview =
          response.status >= 200 &&
          response.status < 300 &&
          data is Map &&
          data['held_for_review'] == true &&
          data['published'] != true;
      if (!published && !heldForReview) {
        throw StateError('Publication was not confirmed by the server');
      }
      disposition = heldForReview
          ? ListingPublicationDisposition.heldForReview
          : ListingPublicationDisposition.published;
      final publishedImages =
          (data['images'] as List<dynamic>? ??
                  (data['listing'] is Map
                      ? (data['listing'] as Map)['images'] as List<dynamic>?
                      : null) ??
                  (data['result'] is Map &&
                          (data['result'] as Map)['media'] is List
                      ? ((data['result'] as Map)['media'] as List)
                            .whereType<Map>()
                            .map(
                              (item) =>
                                  'storage://product-images/'
                                  '${item['final_path'] ?? ''}',
                            )
                            .where(
                              (value) => value != 'storage://product-images/',
                            )
                            .toList()
                      : null) ??
                  const [])
              .whereType<String>()
              .toList(growable: false);
      final displayImages = await Future.wait(
        publishedImages.map(_resolvePublishedImage),
      );
      if (displayImages.length == draft.photos.length) {
        for (var index = 0; index < draft.photos.length; index++) {
          draft.photos[index].remoteUrl = displayImages[index];
        }
      }
    } catch (error, stackTrace) {
      debugPrint('publish-listing Edge error: $error\n$stackTrace');
      throw ListingPublishException(
        'Не удалось опубликовать объявление. Черновик сохранён',
        error,
      );
    }

    draft.status = disposition == ListingPublicationDisposition.published
        ? ListingStatus.published
        : ListingStatus.ready;
    draft.updatedAt = DateTime.now().toUtc();
    try {
      await removeLocalDraft(draft.id);
    } catch (error, stackTrace) {
      // The server publication already succeeded. A local cleanup failure must
      // not turn that success into a second publish attempt.
      debugPrint('Published listing cleanup error: $error\n$stackTrace');
    }
    if (disposition == ListingPublicationDisposition.published) {
      unawaited(_preparePublishedProduct(draft.id));
    }
    debugPrint('Listing published: ${draft.id}');
    return ListingPublishResult(disposition);
  }

  Future<void> _preparePublishedProduct(String productId) async {
    await _queueBackgroundRemoval(productId);
  }

  Future<void> _queueBackgroundRemoval(String productId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.functions.invoke(
        'process-product-image',
        body: {'product_id': productId},
      );
    } catch (error, stackTrace) {
      debugPrint('Background removal queue error: $error\n$stackTrace');
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildPublishRequestBody(ListingDraft draft) => {
    'listing_id': draft.id,
    'confirmation_version': draft.sellerConfirmationVersion,
    'confirmations': draft.sellerConfirmationsPayload,
  };

  static Map<String, dynamic> _publishableListingPayload(
    ListingDraft draft,
  ) => {
    'title': draft.title.trim(),
    // Public product columns are a seller-confirmed projection. Pending ML
    // proposals remain exclusively in `listing_analysis`.
    'description': draft.confirmedDescription,
    'price': draft.price,
    'size': draft.size,
    'condition': draft.condition,
    'section': draft.section,
    'category': draft.category,
    'subcategory': draft.subcategory,
    'item_type': draft.itemType,
    'gender': draft.gender,
    'audience': draft.gender,
    'primary_color': draft.primaryColor,
    'secondary_colors': draft.confirmedSecondaryColors,
    'color': draft.primaryColor,
    'brand': draft.brand,
    'material': draft.confirmedValue('material', draft.material),
    'pattern': draft.confirmedValue('pattern', draft.pattern),
    'season': draft.confirmedValue('season', draft.season),
    'style': draft.confirmedValue('style', draft.style),
    'fit': draft.confirmedValue('fit', draft.fit),
    'sleeve_length': draft.confirmedValue('sleeve_length', draft.sleeveLength),
    'closure': draft.confirmedValue('closure', draft.closure),
    'has_defects': draft.defectsReviewed && draft.hasDefects,
    'defects_reviewed': draft.defectsReviewed,
    'defects_description': draft.defectsReviewed && draft.hasDefects
        ? draft.defectDescription.trim()
        : '',
    'city': draft.city,
    'location': draft.city,
    'shipping_address_id': draft.shippingAddressId.isEmpty
        ? null
        : draft.shippingAddressId,
    'delivery_methods': draft.deliveryMethods,
  };

  Future<String> _resolvePublishedImage(String reference) async {
    const prefix = 'storage://product-images/';
    if (!reference.startsWith(prefix)) return reference;
    final objectPath = reference.substring(prefix.length);
    if (objectPath.isEmpty) return '';
    try {
      return await _client!.storage
          .from('product-images')
          .createSignedUrl(objectPath, 60 * 60);
    } catch (error, stackTrace) {
      // Publication is already committed. A transient display URL failure
      // must never invite the user to publish the same listing again.
      debugPrint('Published image URL resolution error: $error\n$stackTrace');
      return reference;
    }
  }

  Future<List<ListingAddress>> _loadLocalAddresses() async {
    await _purgeLegacySensitivePreferences();
    return const [];
  }

  Future<void> _saveLocalAddresses(List<ListingAddress> addresses) =>
      _purgeLegacySensitivePreferences();

  Future<void> _purgeLegacySensitivePreferences() async {
    final preferences = await _prefs;
    final keys = preferences
        .getKeys()
        .where(
          (key) =>
              key.startsWith(_draftsKeyPrefix) ||
              key.startsWith(_addressesKeyPrefix) ||
              key.startsWith(_deliveryKeyPrefix),
        )
        .toList(growable: false);
    for (final key in keys) {
      await preferences.remove(key);
    }
  }

  Future<void> _purgeLegacyDraftDirectories() async {
    if (kIsWeb) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(path.join(support.path, 'listing_drafts'));
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error, stackTrace) {
      debugPrint('Legacy listing draft purge error: $error\n$stackTrace');
    }
  }

  Future<Uint8List> _readPhotoBytes(String source) async {
    if (source.startsWith('data:image/')) {
      return base64Decode(source.substring(source.indexOf(',') + 1));
    }
    return File(source).readAsBytes();
  }

  Future<void> _deleteLocalPhoto(String source) async {
    if (kIsWeb || source.isEmpty || source.startsWith('data:')) return;
    try {
      final file = File(source);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _deleteDraftDirectory(String draftId) async {
    if (kIsWeb) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        path.join(support.path, 'listing_drafts', draftId),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  String _extension(String name, String fallbackPath) {
    final candidate = path.extension(name).isNotEmpty
        ? path.extension(name)
        : path.extension(fallbackPath);
    final normalized = candidate.toLowerCase();
    return const {
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.heic',
        }.contains(normalized)
        ? normalized
        : '.jpg';
  }

  String _mimeType(String name, String fallbackPath) {
    switch (_extension(name, fallbackPath)) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
