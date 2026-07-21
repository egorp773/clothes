typedef StorageMediaSigner =
    Future<String> Function(String bucket, String objectPath);

class StorageMediaObject {
  const StorageMediaObject({required this.bucket, required this.objectPath});

  final String bucket;
  final String objectPath;
}

const productMediaBuckets = <String>{'product-images', 'outfit-images'};

/// Extracts the canonical Storage object from references persisted in product
/// snapshots. Signed/public URLs are deliberately parsed too so an expired URL
/// can be replaced instead of being passed back to an image widget.
StorageMediaObject? parseProductMediaObject(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return null;

  for (final bucket in productMediaBuckets) {
    final prefix = 'storage://$bucket/';
    if (normalized.startsWith(prefix)) {
      final objectPath = _safeObjectPath(normalized.substring(prefix.length));
      if (objectPath == null) return null;
      return StorageMediaObject(bucket: bucket, objectPath: objectPath);
    }
  }

  final uri = Uri.tryParse(normalized);
  if (uri != null && uri.hasScheme) {
    for (final bucket in productMediaBuckets) {
      for (final marker in <String>[
        '/storage/v1/object/public/$bucket/',
        '/storage/v1/object/sign/$bucket/',
        '/storage/v1/object/authenticated/$bucket/',
        '/storage/v1/object/$bucket/',
        '/storage/v1/render/image/public/$bucket/',
        '/storage/v1/render/image/sign/$bucket/',
      ]) {
        final markerIndex = uri.path.indexOf(marker);
        if (markerIndex < 0) continue;
        final objectPath = _safeObjectPath(
          uri.path.substring(markerIndex + marker.length),
        );
        if (objectPath == null) return null;
        return StorageMediaObject(bucket: bucket, objectPath: objectPath);
      }
    }
    return null;
  }

  if (_canonicalListingPath.hasMatch(normalized)) {
    final objectPath = _safeObjectPath(normalized);
    if (objectPath != null) {
      return StorageMediaObject(
        bucket: 'product-images',
        objectPath: objectPath,
      );
    }
  }
  return null;
}

Future<String> resolveProductMediaReference(
  String value, {
  required StorageMediaSigner signer,
}) async {
  final normalized = value.trim();
  final object = parseProductMediaObject(normalized);
  if (object == null) return normalized;
  try {
    final resolved = (await signer(object.bucket, object.objectPath)).trim();
    final uri = Uri.tryParse(resolved);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return resolved;
    }
  } catch (_) {
    // A recognizable private reference must never fall through to AppImage as
    // a local path. The empty value renders the normal image placeholder.
  }
  return '';
}

Future<Map<String, dynamic>> hydrateProductMediaSnapshot(
  Map<String, dynamic> source, {
  required StorageMediaSigner signer,
}) async {
  final result = Map<String, dynamic>.from(source);
  final cache = <String, Future<String>>{};

  Future<String> resolve(Object? raw) {
    final value = raw?.toString() ?? '';
    final object = parseProductMediaObject(value);
    if (object == null) return Future.value(value.trim());
    final cacheKey = '${object.bucket}\u0000${object.objectPath}';
    return cache.putIfAbsent(
      cacheKey,
      () => resolveProductMediaReference(value, signer: signer),
    );
  }

  for (final key in const <String>[
    'main_image',
    'image',
    'original_image',
    'cutout_image',
    'matched_image_url',
  ]) {
    if (result.containsKey(key)) result[key] = await resolve(result[key]);
  }
  for (final key in const <String>['images', 'outfit_images']) {
    final values = result[key];
    if (values is List) {
      result[key] = await Future.wait(values.map(resolve));
    }
  }
  return result;
}

String? _safeObjectPath(String encodedValue) {
  String decoded;
  try {
    decoded = Uri.decodeComponent(encodedValue).trim();
  } on FormatException {
    return null;
  }
  if (decoded.isEmpty || decoded.startsWith('/') || decoded.endsWith('/')) {
    return null;
  }
  final segments = decoded.split('/');
  if (segments.any(
    (segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains(RegExp(r'[\u0000-\u001f]')),
  )) {
    return null;
  }
  return decoded;
}

final _canonicalListingPath = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$',
  caseSensitive: false,
);
