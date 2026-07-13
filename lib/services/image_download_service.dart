import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

class ImageDownloadService {
  const ImageDownloadService._();

  static Future<void> save(String source, {required String name}) async {
    final bytes = await _load(source.trim());
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Unable to load image');
    }
    await ImageGallerySaverPlus.saveImage(bytes, name: name, quality: 100);
  }

  static Future<Uint8List?> _load(String source) async {
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma == -1) return null;
      return base64Decode(source.substring(comma + 1));
    }
    if (source.startsWith('assets/')) {
      final data = await rootBundle.load(source);
      return data.buffer.asUint8List();
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final response = await http.get(Uri.parse(source));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    }
    return null;
  }
}
