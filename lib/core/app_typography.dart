import 'package:flutter/material.dart';

/// Project typography rule:
/// Montserrat only. Prices use Bold, subtitles use SemiBold, all other text uses Medium.
abstract final class AppTypography {
  static const String fontFamily = 'Montserrat';

  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
