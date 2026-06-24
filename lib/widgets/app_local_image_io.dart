import 'dart:io';

import 'package:flutter/material.dart';

Widget buildAppLocalImage({
  required String path,
  double? width,
  double? height,
  required BoxFit fit,
  required Alignment alignment,
  required Widget Function() placeholder,
}) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    errorBuilder: (context, error, stackTrace) => placeholder(),
  );
}
