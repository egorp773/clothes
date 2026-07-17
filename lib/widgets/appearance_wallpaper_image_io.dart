import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

Widget? buildAppearanceWallpaperImage(String source) {
  final normalized = source.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('data:image')) {
    try {
      final separator = normalized.indexOf(',');
      if (separator < 0) return null;
      return Image.memory(
        base64Decode(normalized.substring(separator + 1)),
        key: ValueKey(normalized.hashCode),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } catch (_) {
      return null;
    }
  }
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return Image.network(
      normalized,
      key: ValueKey(normalized),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
  return Image.file(
    File(normalized),
    key: ValueKey(normalized),
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
