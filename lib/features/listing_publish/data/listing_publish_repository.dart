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
import 'listing_catalogs.dart';
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

class ListingPublishRepository {
  ListingPublishRepository({
    required this.sellerName,
    required this.sellerHandle,
    required this.fallbackCity,
  });

  static const _draftsKeyPrefix = 'listing_publish_drafts_v1';
  static const _addressesKeyPrefix = 'listing_publish_addresses_v1';
  static const _deliveryKeyPrefix = 'listing_publish_delivery_v1';
  static const _bucketName = 'product-images';

  final String sellerName;
  final String sellerHandle;
  final String fallbackCity;

  SharedPreferences? _preferences;

  SupabaseClient? get _client =>
      SupabaseConfig.isInitialized ? SupabaseConfig.client : null;

  String get sellerId => _client?.auth.currentUser?.id ?? '';

  String get _ownerKey => sellerId.isEmpty ? 'local' : sellerId;
  String get _draftsKey => '${_draftsKeyPrefix}_$_ownerKey';
  String get _addressesKey => '${_addressesKeyPrefix}_$_ownerKey';
  String get _deliveryKey => '${_deliveryKeyPrefix}_$_ownerKey';

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<List<ListingDraft>> loadLocalDrafts() async {
    try {
      final encoded = (await _prefs).getString(_draftsKey);
      if (encoded == null || encoded.isEmpty) return [];
      final raw = jsonDecode(encoded);
      if (raw is! List) return [];
      final drafts = raw
          .whereType<Map>()
          .map((item) => ListingDraft.fromJson(Map<String, dynamic>.from(item)))
          .where(
            (draft) =>
                draft.status != ListingStatus.published &&
                draft.status != ListingStatus.archived &&
                draft.status != ListingStatus.sold,
          )
          .toList();
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return drafts;
    } catch (error, stackTrace) {
      debugPrint('Listing drafts read error: $error\n$stackTrace');
      return [];
    }
  }

  Future<void> saveLocalDraft(ListingDraft draft) async {
    if (draft.status == ListingStatus.published ||
        draft.status == ListingStatus.archived ||
        draft.status == ListingStatus.sold) {
      await removeLocalDraft(draft.id);
      return;
    }
    draft.updatedAt = DateTime.now().toUtc();
    final drafts = await loadLocalDrafts();
    drafts.removeWhere((item) => item.id == draft.id);
    drafts.insert(0, draft);
    final payload = drafts.take(20).map((item) => item.toJson()).toList();
    await (await _prefs).setString(_draftsKey, jsonEncode(payload));
  }

  Future<void> removeLocalDraft(String draftId) async {
    final drafts = await loadLocalDrafts();
    drafts.removeWhere((item) => item.id == draftId);
    await (await _prefs).setString(
      _draftsKey,
      jsonEncode(drafts.map((item) => item.toJson()).toList()),
    );
  }

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
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client
          .from('products')
          .upsert(_remotePayload(draft, user.id), onConflict: 'id');
    } catch (error, stackTrace) {
      debugPrint('Remote listing draft create error: $error\n$stackTrace');
    }
  }

  Future<bool> uploadPhoto(ListingDraft draft, ListingPhoto photo) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return false;
    if (photo.remoteUrl.isNotEmpty) return true;

    photo.uploadStatus = ListingPhotoUploadStatus.uploading;
    try {
      final bytes = await _readPhotoBytes(photo.localPath);
      final extension = _extension(photo.localPath, photo.localPath);
      final storagePath =
          'users/${user.id}/listings/${draft.id}/${photo.id}$extension';
      await client.storage
          .from(_bucketName)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
      photo.storagePath = storagePath;
      photo.remoteUrl = client.storage
          .from(_bucketName)
          .getPublicUrl(storagePath);
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
    if (client != null && photo.storagePath.isNotEmpty) {
      try {
        await client.storage.from(_bucketName).remove([photo.storagePath]);
      } catch (error, stackTrace) {
        debugPrint('Listing photo remote delete error: $error\n$stackTrace');
      }
    }
    await _deleteLocalPhoto(photo.localPath);
  }

  Future<void> syncRemoteDraft(ListingDraft draft) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client
          .from('products')
          .upsert(_remotePayload(draft, user.id), onConflict: 'id');
      if (draft.predictions.isNotEmpty) {
        final analysisRows = draft.predictions.values
            .map(
              (entry) => {
                'listing_id': draft.id,
                'field_name': entry.fieldName,
                'predicted_value': entry.predictedValue,
                'confirmed_value': entry.confirmedValue,
                'confidence': entry.confidence,
                'source': entry.source,
                'was_edited': entry.wasEdited,
                'user_confirmed': entry.userConfirmed,
                'model_version': entry.modelVersion,
              },
            )
            .toList();
        await client
            .from('listing_analysis')
            .upsert(analysisRows, onConflict: 'listing_id,field_name');
      }
      final attributes = _confirmedProductAttributes(draft);
      await Future.wait(
        attributes.map(
          (attribute) => client.rpc(
            'set_product_attribute',
            params: {
              'p_product_id': draft.id,
              'p_attribute_key': attribute.key,
              'p_value': attribute.value,
              'p_confirmed': true,
              'p_source': 'manual',
              'p_confidence': 1.0,
              'p_model_version': 'seller-publication-v1',
            },
          ),
        ),
      );
    } catch (error, stackTrace) {
      // The local copy remains authoritative while offline or before migration.
      debugPrint('Listing draft sync error: $error\n$stackTrace');
    }
  }

  Future<ListingDeliveryDefaults> loadDeliveryDefaults() async {
    final localAddresses = await _loadLocalAddresses();
    final localDelivery =
        (await _prefs).getStringList(_deliveryKey) ?? const <String>[];
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
      await _saveLocalAddresses(addresses);
      await (await _prefs).setStringList(_deliveryKey, methods);
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
    await (await _prefs).setStringList(_deliveryKey, draft.deliveryMethods);

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
    final client = _client;
    final user = client?.auth.currentUser;
    var remoteIsPublished = false;
    if (client != null && user != null) {
      try {
        final row = await client
            .from('products')
            .select('status')
            .eq('id', draft.id)
            .eq('seller_id', user.id)
            .maybeSingle();
        remoteIsPublished = row?['status'] == 'published';
      } catch (_) {
        // Continue local cleanup; storage deletion is still gated below.
      }
    }
    if (!remoteIsPublished) {
      for (final photo in List<ListingPhoto>.of(draft.photos)) {
        await deletePhoto(draft, photo);
      }
      if (client != null && user != null) {
        try {
          await client
              .from('products')
              .delete()
              .eq('id', draft.id)
              .eq('seller_id', user.id)
              .neq('status', 'published');
        } catch (error, stackTrace) {
          debugPrint('Remote listing draft delete error: $error\n$stackTrace');
        }
      }
    }
    await removeLocalDraft(draft.id);
    await _deleteDraftDirectory(draft.id);
  }

  Future<void> publish(ListingDraft draft) async {
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

    final savedAddress = await saveAddress(draft: draft);
    draft.shippingAddressId = savedAddress.id;
    await syncRemoteDraft(draft);
    try {
      await client.rpc('publish_listing', params: {'p_listing_id': draft.id});
    } catch (error, stackTrace) {
      debugPrint('publish_listing RPC error: $error\n$stackTrace');
      throw ListingPublishException(
        'Не удалось опубликовать объявление. Черновик сохранён',
        error,
      );
    }

    draft.status = ListingStatus.published;
    draft.updatedAt = DateTime.now().toUtc();
    await removeLocalDraft(draft.id);
    unawaited(_preparePublishedProduct(draft.id));
    debugPrint('Listing published: ${draft.id}');
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

  Map<String, dynamic> _remotePayload(ListingDraft draft, String userId) => {
    'id': draft.id,
    'seller_id': userId,
    'seller_name': sellerName,
    'seller_handle': sellerHandle,
    'status': draft.status == ListingStatus.published
        ? ListingStatus.published.value
        : ListingStatus.draft.value,
    'title': draft.title.trim(),
    'description': draft.description.trim(),
    'price': draft.price,
    'size': draft.size,
    'condition': draft.condition,
    'section': draft.section,
    'category': draft.category,
    'subcategory': draft.subcategory,
    'item_type': draft.itemType,
    'normalized_category': draft.normalizedCategory,
    'gender': draft.gender,
    'audience': draft.gender,
    'primary_color': draft.primaryColor,
    'secondary_colors': draft.secondaryColors,
    'color': draft.primaryColor,
    'brand': draft.brand,
    'normalized_brand': draft.brand,
    'material': draft.material,
    'pattern': draft.pattern,
    'season': draft.season,
    'style': draft.style,
    'fit': draft.fit,
    'sleeve_length': draft.sleeveLength,
    'closure': draft.closure,
    'has_defects': draft.hasDefects,
    'defects_description': draft.defectDescription.trim(),
    'city': draft.city,
    'location': draft.city,
    'shipping_address_id': draft.shippingAddressId.isEmpty
        ? null
        : draft.shippingAddressId,
    'shipping_address': draft.shippingAddress.trim(),
    'delivery_methods': draft.deliveryMethods,
    'images': draft.uploadedImageUrls,
    'main_image': draft.mainPhoto?.remoteUrl ?? '',
    'original_image': draft.mainPhoto?.remoteUrl ?? '',
    'analysis_status': draft.analysisStatus.value,
    'enrichment_status': 'enrichment_pending',
    'analysis_job_id': draft.analysisId.isEmpty ? null : draft.analysisId,
    'analysis_completed_at':
        draft.analysisStatus == ListingAnalysisStatus.completed
        ? DateTime.now().toUtc().toIso8601String()
        : null,
    'draft_step': draft.currentStep.name,
    'is_hidden': draft.status != ListingStatus.published,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  List<MapEntry<String, String>> _confirmedProductAttributes(
    ListingDraft draft,
  ) {
    final result = <MapEntry<String, String>>[];
    for (final definition in ListingCatalogs.attributesFor(
      draft.normalizedCategory,
    )) {
      final value = draft.categoryAttributes[definition.id] ?? '';
      final prediction = draft.predictions[definition.id];
      if (prediction?.userConfirmed != true && prediction?.wasEdited != true) {
        continue;
      }
      result.add(MapEntry(definition.id, value));
    }
    return result;
  }

  Future<List<ListingAddress>> _loadLocalAddresses() async {
    try {
      final encoded = (await _prefs).getString(_addressesKey);
      if (encoded == null || encoded.isEmpty) return [];
      final raw = jsonDecode(encoded);
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map(
            (item) => ListingAddress.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLocalAddresses(List<ListingAddress> addresses) =>
      _prefs.then(
        (preferences) => preferences.setString(
          _addressesKey,
          jsonEncode(addresses.map((item) => item.toJson()).toList()),
        ),
      );

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
