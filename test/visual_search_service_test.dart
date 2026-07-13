import 'dart:convert';
import 'dart:typed_data';

import 'package:clothes/features/visual_search/visual_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('parses real visual search response into catalog products', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/visual-search');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response(
        jsonEncode({
          'category': 'clothing',
          'category_confidence': 0.8,
          'candidate_count': 200,
          'cached': false,
          'timings_ms': {'total': 640},
          'products': [
            {
              'product_id': 'product-1',
              'title': 'Худи',
              'price': 4500,
              'main_image': 'https://example.com/hoodie.jpg',
              'images': ['https://example.com/hoodie.jpg'],
              'category': 'clothing',
              'brand': 'nike',
              'size': 'm',
              'condition': 'excellent',
              'primary_color': 'black',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = VisualSearchService(
      baseUrl: 'https://analyzer.example',
      client: client,
      accessTokenProvider: () => 'token',
    );
    final result = await service.search(
      XFile.fromData(
        Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
        mimeType: 'image/jpeg',
        name: 'query.jpg',
      ),
    );

    expect(result.products.single.id, 'product-1');
    expect(result.products.single.priceValue, 4500);
    expect(result.timingsMs['total'], 640);
    expect(result.candidateCount, 200);
  });

  test('calls backend without a user session', () async {
    final service = VisualSearchService(
      baseUrl: 'https://analyzer.example',
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'category': 'clothing',
            'category_confidence': 0.0,
            'candidate_count': 0,
            'cached': false,
            'timings_ms': {'total': 1},
            'products': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessTokenProvider: () => null,
    );

    final result = await service.search(
      XFile.fromData(
        Uint8List.fromList(const [1]),
        mimeType: 'image/jpeg',
        name: 'query.jpg',
      ),
    );
    expect(result.products, isEmpty);
  });

  test(
    'reuses supplied image bytes instead of reading the source again',
    () async {
      final service = VisualSearchService(
        baseUrl: 'https://analyzer.example',
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'category': 'clothing',
              'category_confidence': 0.0,
              'candidate_count': 0,
              'cached': false,
              'timings_ms': {'total': 1},
              'products': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'stale-token',
      );

      final result = await service.search(
        XFile('definitely-missing-visual-search-source.jpg'),
        imageBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
      );

      expect(result.products, isEmpty);
    },
  );

  test('parses normalized visual search object regions', () async {
    final service = VisualSearchService(
      baseUrl: 'https://analyzer.example',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/visual-search/regions');
        return http.Response(
          jsonEncode({
            'width': 800,
            'height': 1200,
            'regions': [
              {
                'id': 'region-1',
                'label': 'jacket',
                'confidence': 0.91,
                'bbox': [0.1, 0.2, 0.7, 0.8],
              },
              {
                'id': 'region-2',
                'label': null,
                'confidence': 0.82,
                'bbox': [0.72, 0.4, 0.96, 0.9],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessTokenProvider: () => null,
    );

    final result = await service.detectRegions(
      XFile.fromData(
        Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'image/jpeg',
        name: 'query.jpg',
      ),
    );

    expect(result.imageSize.width, 800);
    expect(result.regions, hasLength(2));
    expect(result.regions.first.label, 'jacket');
    expect(result.regions.first.bounds.left, 0.1);
    expect(result.regions.last.bounds.bottom, 0.9);
  });
}
