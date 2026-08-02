import 'dart:typed_data';

import 'package:clothes/core/upload_image_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UploadImageNormalizer', () {
    test('keeps JPEG bytes and reports a canonical MIME type', () async {
      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]);

      final result = await UploadImageNormalizer.fromBytes(bytes);

      expect(result.bytes, same(bytes));
      expect(result.extension, '.jpg');
      expect(result.contentType, 'image/jpeg');
    });

    test('decodes HEIC bytes to a real JPEG', () async {
      final heic = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...'ftyp'.codeUnits,
        ...'heic'.codeUnits,
        0,
        0,
        0,
        0,
      ]);
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0x01]);

      final result = await UploadImageNormalizer.fromBytes(
        heic,
        fileName: 'IMG_0001.HEIC',
        heicCompressor: (_) async => jpeg,
      );

      expect(result.bytes, jpeg);
      expect(result.extension, '.jpg');
      expect(result.contentType, 'image/jpeg');
    });

    test('does not accept renamed unsupported bytes', () async {
      await expectLater(
        UploadImageNormalizer.fromBytes(
          Uint8List.fromList([1, 2, 3, 4]),
          fileName: 'fake.jpg',
        ),
        throwsFormatException,
      );
    });

    test('fails when native HEIC decoding does not return JPEG', () async {
      final heic = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...'ftyp'.codeUnits,
        ...'heic'.codeUnits,
      ]);

      await expectLater(
        UploadImageNormalizer.fromBytes(
          heic,
          heicCompressor: (_) async => Uint8List.fromList([1, 2, 3]),
        ),
        throwsFormatException,
      );
    });
  });
}
