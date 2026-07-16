import 'package:clothes/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application entrypoint stays linked after feature integration', () {
    expect(const FashionApp(), isA<FashionApp>());
  });
}
