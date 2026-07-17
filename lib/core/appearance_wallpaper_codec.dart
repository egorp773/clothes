import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

Future<Uint8List> optimizedAppearanceWallpaper(
  XFile wallpaper, {
  required int maxDimension,
  required int quality,
}) async {
  final bytes = await wallpaper.readAsBytes();
  return compute(
    _optimize,
    _WallpaperOptimization(
      bytes: bytes,
      maxDimension: maxDimension,
      quality: quality,
    ),
  );
}

Uint8List _optimize(_WallpaperOptimization request) {
  final decoded = image_lib.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;
  final oriented = image_lib.bakeOrientation(decoded);
  final resized =
      oriented.width > request.maxDimension ||
          oriented.height > request.maxDimension
      ? oriented.width >= oriented.height
            ? image_lib.copyResize(oriented, width: request.maxDimension)
            : image_lib.copyResize(oriented, height: request.maxDimension)
      : oriented;
  return Uint8List.fromList(
    image_lib.encodeJpg(resized, quality: request.quality),
  );
}

class _WallpaperOptimization {
  const _WallpaperOptimization({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
  });

  final Uint8List bytes;
  final int maxDimension;
  final int quality;
}
