import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/app_config.dart';
import 'product_image_analyzer.dart';

class RemoteProductImageAnalyzer implements ProductImageAnalyzer {
  RemoteProductImageAnalyzer({
    String? baseUrl,
    http.Client? client,
    @Deprecated('User access tokens must not be sent to analyzer services.')
    String? Function()? accessTokenProvider,
    // Production intentionally has a single inference slot. A publication
    // request can briefly wait behind one durable enrichment job, so the
    // client timeout must exceed the server queue + inference budgets.
    this.timeout = const Duration(seconds: 75),
  }) : baseUrl = (baseUrl ?? AppConfig.productAnalyzerUrl).replaceAll(
         RegExp(r'/$'),
         '',
       ),
       _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<ProductAnalysisResult> analyze({
    required List<String> imageUrls,
    String? listingId,
  }) async {
    if (baseUrl.isEmpty) {
      throw const ProductImageAnalysisException(
        'Analyzer is disabled until a protected Edge proxy is configured',
      );
    }
    final sources = imageUrls
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(8)
        .toList(growable: false);
    if (sources.isEmpty) {
      throw const ProductImageAnalysisException('No images to analyze');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/v1/analyze'),
    );
    if (listingId != null && listingId.isNotEmpty) {
      request.fields['listing_id'] = listingId;
    }
    final mainSource = sources.first;
    if (mainSource.startsWith('http://') || mainSource.startsWith('https://')) {
      request.fields['main_image_url'] = mainSource;
    }
    // The server's synchronous path is intentionally main-photo only.
    // Detail/label photos are submitted afterwards, off the critical path.
    final loaded = await _loadSource(mainSource);
    request.files.add(
      http.MultipartFile.fromBytes(
        'files',
        loaded.bytes,
        filename: 'listing_1.${loaded.extension}',
        contentType: loaded.mediaType,
      ),
    );

    late http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } catch (error) {
      throw ProductImageAnalysisException(
        'Analyzer service is unavailable: ${error.runtimeType}',
      );
    }
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProductImageAnalysisException(
        'Analyzer returned HTTP ${response.statusCode}',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('Expected JSON object');
      final payload = Map<String, dynamic>.from(decoded);
      final analysisId = payload['analysis_id'] as String?;
      if (analysisId != null && sources.length > 1) {
        unawaited(_enqueueExtraImages(analysisId, sources.skip(1).toList()));
      }
      return ProductAnalysisResult.fromJson(payload);
    } catch (error) {
      throw ProductImageAnalysisException(
        'Invalid analyzer response: ${error.runtimeType}',
      );
    }
  }

  Future<void> _enqueueExtraImages(
    String analysisId,
    List<String> sources,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/v1/analyze/$analysisId/enrich'),
      );
      for (var index = 0; index < sources.length; index++) {
        final loaded = await _loadSource(sources[index]);
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            loaded.bytes,
            filename: 'detail_${index + 1}.${loaded.extension}',
            contentType: loaded.mediaType,
          ),
        );
      }
      if (request.files.isNotEmpty) {
        await _client.send(request).timeout(timeout);
      }
    } catch (_) {
      // Detail-shot enrichment is deliberately best-effort and must never
      // affect the result already shown in the publication form.
    }
  }

  Future<_LoadedImage> _loadSource(String source) async {
    if (source.startsWith('data:image/')) {
      final data = UriData.parse(source);
      return _LoadedImage(
        data.contentAsBytes(),
        _extensionForMime(data.mimeType),
        _mediaType(data.mimeType),
      );
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ProductImageAnalysisException(
          'Unable to read image: HTTP ${response.statusCode}',
        );
      }
      final mime =
          response.headers['content-type']?.split(';').first ?? 'image/jpeg';
      return _LoadedImage(
        response.bodyBytes,
        _extensionForMime(mime),
        _mediaType(mime),
      );
    }
    final bytes = await XFile(source).readAsBytes();
    final extension = source.split('.').last.toLowerCase();
    final normalized =
        const {'png', 'webp', 'heic', 'jpeg', 'jpg'}.contains(extension)
        ? extension
        : 'jpg';
    final mime = normalized == 'png'
        ? 'image/png'
        : normalized == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    return _LoadedImage(bytes, normalized, _mediaType(mime));
  }

  @override
  Future<ProductAnalysisResult?> getAnalysis(String analysisId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/v1/analyze/$analysisId'))
          .timeout(timeout);
      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map
          ? ProductAnalysisResult.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (_) {
      return null;
    }
  }

  String _extensionForMime(String mime) => switch (mime.toLowerCase()) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' || 'image/heif' => 'heic',
    _ => 'jpg',
  };

  MediaType _mediaType(String mime) {
    final parts = mime.split('/');
    return MediaType(
      parts.length == 2 ? parts[0] : 'image',
      parts.length == 2 ? parts[1] : 'jpeg',
    );
  }
}

class _LoadedImage {
  const _LoadedImage(this.bytes, this.extension, this.mediaType);

  final List<int> bytes;
  final String extension;
  final MediaType mediaType;
}
