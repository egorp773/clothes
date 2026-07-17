import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import 'appearance_wallpaper_codec.dart';

Future<String?> storeAppearanceWallpaper(XFile wallpaper) async {
  try {
    final bytes = await optimizedAppearanceWallpaper(
      wallpaper,
      maxDimension: 1280,
      quality: 76,
    );
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

Future<void> deleteAppearanceWallpaper(String source) async {}
