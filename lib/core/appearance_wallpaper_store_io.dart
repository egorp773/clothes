import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'appearance_wallpaper_codec.dart';

Future<String?> storeAppearanceWallpaper(XFile wallpaper) async {
  try {
    final bytes = await optimizedAppearanceWallpaper(
      wallpaper,
      maxDimension: 1800,
      quality: 84,
    );
    final directory = await getApplicationDocumentsDirectory();
    final wallpaperDirectory = Directory(
      path.join(directory.path, 'appearance'),
    );
    await wallpaperDirectory.create(recursive: true);
    final name = 'wallpaper_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final file = File(path.join(wallpaperDirectory.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<void> deleteAppearanceWallpaper(String source) async {
  try {
    if (source.trim().isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final wallpaperDirectory = path.normalize(
      path.absolute(path.join(directory.path, 'appearance')),
    );
    final target = path.normalize(path.absolute(source));
    if (!path.isWithin(wallpaperDirectory, target)) return;
    final file = File(target);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A stale wallpaper must not prevent the new theme from being applied.
  }
}
