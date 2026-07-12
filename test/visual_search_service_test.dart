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
      expect(request.headers['Authorization'], 'Bearer token');
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
}
