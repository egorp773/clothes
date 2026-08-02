import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

typedef HeicJpegCompressor = Future<Uint8List?> Function(Uint8List bytes);

class NormalizedUploadImage {
  const NormalizedUploadImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

/// Normalizes formats that are commonly returned by iOS photo pickers.
///
/// Existing web-friendly images stay byte-for-byte intact. HEIC/HEIF is
/// decoded by the platform image stack and encoded as an orientation-correct
/// JPEG, so Storage never receives HEIC bytes under a `.jpg` path.
class UploadImageNormalizer {
  const UploadImageNormalizer._();

  static Future<NormalizedUploadImage> fromXFile(
    XFile file, {
    HeicJpegCompressor? heicCompressor,
  }) async {
    return fromBytes(
      await file.readAsBytes(),
      fileName: file.name.isEmpty ? file.path : file.name,
      heicCompressor: heicCompressor,
    );
  }

  static Future<NormalizedUploadImage> fromBytes(
    Uint8List bytes, {
    String fileName = '',
    HeicJpegCompressor? heicCompressor,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('Image is empty');
    }
    if (_isJpeg(bytes)) {
      return NormalizedUploadImage(
        bytes: bytes,
        extension: '.jpg',
        contentType: 'image/jpeg',
      );
    }
    if (_isPng(bytes)) {
      return NormalizedUploadImage(
        bytes: bytes,
        extension: '.png',
        contentType: 'image/png',
      );
    }
    if (_isWebp(bytes)) {
      return NormalizedUploadImage(
        bytes: bytes,
        extension: '.webp',
        contentType: 'image/webp',
      );
    }
    if (_isGif(bytes)) {
      return NormalizedUploadImage(
        bytes: bytes,
        extension: '.gif',
        contentType: 'image/gif',
      );
    }

    final lowerName = fileName.toLowerCase();
    final needsHeicDecode =
        _isHeic(bytes) ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.heif');
    if (!needsHeicDecode) {
      throw const FormatException('Unsupported image format');
    }

    final jpeg = await (heicCompressor ?? _compressHeicToJpeg)(bytes);
    if (jpeg == null || jpeg.isEmpty || !_isJpeg(jpeg)) {
      throw const FormatException('Unable to decode HEIC/HEIF image');
    }
    return NormalizedUploadImage(
      bytes: jpeg,
      extension: '.jpg',
      contentType: 'image/jpeg',
    );
  }

  static Future<Uint8List?> _compressHeicToJpeg(Uint8List bytes) async {
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 88,
      format: CompressFormat.jpeg,
      autoCorrectionAngle: true,
      keepExif: false,
    );
    return compressed.isEmpty ? null : compressed;
  }

  static bool _isJpeg(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;

  static bool _isPng(List<int> bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  static bool _isWebp(List<int> bytes) =>
      bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 12) == 'WEBP';

  static bool _isGif(List<int> bytes) =>
      bytes.length >= 6 &&
      (_ascii(bytes, 0, 6) == 'GIF87a' || _ascii(bytes, 0, 6) == 'GIF89a');

  static bool _isHeic(List<int> bytes) {
    if (bytes.length < 12 || _ascii(bytes, 4, 8) != 'ftyp') return false;
    final end = bytes.length < 40 ? bytes.length : 40;
    final brands = <String>{
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'mif1',
      'msf1',
    };
    for (var offset = 8; offset + 4 <= end; offset += 4) {
      if (brands.contains(_ascii(bytes, offset, offset + 4))) return true;
    }
    return false;
  }

  static String _ascii(List<int> bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));
}
