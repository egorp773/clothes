import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    required this.category,
    required this.categoryConfidence,
    required this.timingsMs,
    required this.candidateCount,
    required this.cached,
  });

  final List<Product> products;
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

class VisualSearchService {
  VisualSearchService({
    String? baseUrl,
    http.Client? client,
    String? Function()? accessTokenProvider,
  }) : baseUrl = (baseUrl ?? AppConfig.productAnalyzerUrl).replaceAll(
         RegExp(r'/$'),
         '',
       ),
       _client = client ?? http.Client(),
       _accessTokenProvider =
           accessTokenProvider ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken);

  final String baseUrl;
  final http.Client _client;
  final String? Function() _accessTokenProvider;

  Future<VisualSearchResult> search(
    XFile image, {
    VisualSearchFilters filters = const VisualSearchFilters(),
  }) async {
    final token = _accessTokenProvider();
    final bytes = await image.readAsBytes();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/visual-search'))
          ..fields['filters'] = jsonEncode(filters.toJson())
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: image.name,
              contentType: MediaType.parse(_mimeType(image)),
            ),
          );
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    late http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const VisualSearchException(
        'Поиск по фото временно недоступен. Попробуйте позже.',
      );
    }
    final response = await http.Response.fromStream(streamed);
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
    final rows = payload['products'];
    final products = rows is List
        ? rows
              .whereType<Map>()
              .map((raw) {
                final row = Map<String, dynamic>.from(raw);
                return Product.fromSupabase({
                  ...row,
                  'id': row['product_id'],
                  'image': row['main_image'] ?? row['matched_image_url'],
                });
              })
              .toList(growable: false)
        : <Product>[];
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
      category: payload['category'] as String? ?? '',
      categoryConfidence:
          (payload['category_confidence'] as num?)?.toDouble() ?? 0,
      timingsMs: timings,
      candidateCount: (payload['candidate_count'] as num?)?.toInt() ?? 0,
      cached: payload['cached'] as bool? ?? false,
    );
  }

  Future<void> indexProduct(String productId) async {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) return;
    try {
      await _client
          .post(
            Uri.parse('$baseUrl/v1/products/$productId/embeddings'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // Search indexing is best-effort and never blocks publication.
    }
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

  void close() => _client.close();
}
