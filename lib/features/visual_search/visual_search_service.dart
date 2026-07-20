import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/product.dart';
import '../../core/app_config.dart';

class VisualSearchFilters {
  const VisualSearchFilters({
    this.minPrice,
    this.maxPrice,
    this.sizes = const [],
    this.brands = const [],
    this.conditions = const [],
    this.colors = const [],
  });

  final double? minPrice;
  final double? maxPrice;
  final List<String> sizes;
  final List<String> brands;
  final List<String> conditions;
  final List<String> colors;

  bool get isEmpty =>
      minPrice == null &&
      maxPrice == null &&
      sizes.isEmpty &&
      brands.isEmpty &&
      conditions.isEmpty &&
      colors.isEmpty;

  Map<String, dynamic> toJson() => {
    if (minPrice != null) 'min_price': minPrice,
    if (maxPrice != null) 'max_price': maxPrice,
    'sizes': sizes,
    'brands': brands,
    'conditions': conditions,
    'colors': colors,
  };
}

class VisualSearchResult {
  const VisualSearchResult({
    required this.products,
    this.similarProducts = const [],
    this.matchStatus = 'strong',
    this.bestSimilarity = 0,
    required this.category,
    required this.categoryConfidence,
    required this.timingsMs,
    required this.candidateCount,
    required this.cached,
  });

  final List<Product> products;
  final List<Product> similarProducts;
  final String matchStatus;
  final double bestSimilarity;
  final String category;
  final double categoryConfidence;
  final Map<String, int> timingsMs;
  final int candidateCount;
  final bool cached;
}

class VisualSearchException implements Exception {
  const VisualSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VisualSearchRegion {
  const VisualSearchRegion({
    required this.id,
    required this.bounds,
    required this.confidence,
    this.label,
  });

  final String id;
  final Rect bounds;
  final double confidence;
  final String? label;
}

class VisualSearchRegionsResult {
  const VisualSearchRegionsResult({
    required this.imageSize,
    required this.regions,
  });

  final Size imageSize;
  final List<VisualSearchRegion> regions;
}

class VisualSearchService {
  VisualSearchService({
    String? baseUrl,
    http.Client? client,
    @Deprecated('Visual search is public and must never receive a user JWT.')
    String? Function()? accessTokenProvider,
  }) : baseUrl = (baseUrl ?? AppConfig.productAnalyzerUrl).replaceAll(
         RegExp(r'/$'),
         '',
       ),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String baseUrl;
  http.Client _client;
  final bool _ownsClient;

  Future<VisualSearchRegionsResult> detectRegions(
    XFile image, {
    Uint8List? imageBytes,
  }) async {
    final bytes = imageBytes ?? await image.readAsBytes();
    late http.Response response;
    try {
      response = await _sendVisualSearchImage(
        path: '/v1/visual-search/regions',
        image: image,
        bytes: bytes,
        timeout: const Duration(seconds: 40),
      );
    } catch (_) {
      throw const VisualSearchException(
        'Не удалось определить вещи на фото. Попробуйте ещё раз.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const VisualSearchException(
        'Не удалось определить вещи на фото. Попробуйте ещё раз.',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const VisualSearchException('Сервис вернул некорректный ответ');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final width = (payload['width'] as num?)?.toDouble() ?? 1;
    final height = (payload['height'] as num?)?.toDouble() ?? 1;
    final regions = <VisualSearchRegion>[];
    final rows = payload['regions'];
    if (rows is List) {
      for (final raw in rows.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final bbox = row['bbox'];
        if (bbox is! List || bbox.length != 4) continue;
        final values = bbox.map((value) => (value as num).toDouble()).toList();
        regions.add(
          VisualSearchRegion(
            id: row['id']?.toString() ?? 'region-${regions.length + 1}',
            label: row['label']?.toString(),
            confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
            bounds: Rect.fromLTRB(
              values[0].clamp(0, 1),
              values[1].clamp(0, 1),
              values[2].clamp(0, 1),
              values[3].clamp(0, 1),
            ),
          ),
        );
      }
    }
    return VisualSearchRegionsResult(
      imageSize: Size(width, height),
      regions: regions,
    );
  }

  Future<VisualSearchResult> search(
    XFile image, {
    VisualSearchFilters filters = const VisualSearchFilters(),
    Uint8List? imageBytes,
  }) async {
    final bytes = imageBytes ?? await image.readAsBytes();
    late http.Response response;
    try {
      response = await _sendVisualSearchImage(
        path: '/v1/visual-search',
        image: image,
        bytes: bytes,
        fields: {'filters': jsonEncode(filters.toJson())},
        timeout: const Duration(seconds: 45),
      );
    } catch (_) {
      throw const VisualSearchException(
        'Поиск по фото временно недоступен. Попробуйте позже.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Не удалось выполнить поиск по фото';
      try {
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is Map && payload['detail'] is String) {
          message = payload['detail'] as String;
        }
      } catch (_) {}
      throw VisualSearchException(message);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const VisualSearchException('Сервис вернул некорректный ответ');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final products = _parseVisualSearchProducts(payload['products']);
    final similarProducts = _parseVisualSearchProducts(
      payload['similar_products'],
    );
    final timings = <String, int>{};
    final rawTimings = payload['timings_ms'];
    if (rawTimings is Map) {
      for (final entry in rawTimings.entries) {
        if (entry.value is num) {
          timings[entry.key.toString()] = (entry.value as num).round();
        }
      }
    }
    return VisualSearchResult(
      products: products,
      similarProducts: similarProducts,
      matchStatus:
          payload['match_status'] as String? ??
          (products.isEmpty ? 'none' : 'strong'),
      bestSimilarity: (payload['best_similarity'] as num?)?.toDouble() ?? 0,
      category: payload['category'] as String? ?? '',
      categoryConfidence:
          (payload['category_confidence'] as num?)?.toDouble() ?? 0,
      timingsMs: timings,
      candidateCount: (payload['candidate_count'] as num?)?.toInt() ?? 0,
      cached: payload['cached'] as bool? ?? false,
    );
  }

  Future<void> indexProduct(String productId) async {
    throw const VisualSearchException(
      'Индексация выполняется сервером после публикации товара',
    );
  }

  Future<http.Response> _sendVisualSearchImage({
    required String path,
    required XFile image,
    required Uint8List bytes,
    required Duration timeout,
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: image.name,
          contentType: MediaType.parse(_mimeType(image)),
        ),
      );
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed);
  }

  String _mimeType(XFile file) {
    final explicit = file.mimeType?.toLowerCase();
    if (explicit == 'image/png' ||
        explicit == 'image/webp' ||
        explicit == 'image/jpeg') {
      return explicit!;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void cancelActiveSearch() {
    if (!_ownsClient) return;
    _client.close();
    _client = http.Client();
  }

  void close() => _client.close();
}

List<Product> _parseVisualSearchProducts(Object? rawRows) {
  if (rawRows is! List) return const [];
  return rawRows
      .whereType<Map>()
      .map((raw) {
        final row = Map<String, dynamic>.from(raw);
        final images = (row['images'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .where((image) => image.trim().isNotEmpty)
            .toList(growable: false);
        final mainImage =
            <Object?>[
                  row['main_image'],
                  row['image'],
                  row['original_image'],
                  if (images.isNotEmpty) images.first,
                  row['matched_image_url'],
                ]
                .map((value) => value?.toString().trim() ?? '')
                .firstWhere((value) => value.isNotEmpty, orElse: () => '');
        return Product.fromSupabase({
          ...row,
          'id': row['product_id'],
          'image': mainImage,
          'main_image': mainImage,
          if (images.isEmpty && mainImage.isNotEmpty) 'images': [mainImage],
        });
      })
      .toList(growable: false);
}
