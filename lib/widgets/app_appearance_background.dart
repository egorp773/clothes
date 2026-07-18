import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import 'appearance_wallpaper_image.dart';

class AppAppearanceBackground extends StatelessWidget {
  const AppAppearanceBackground({
    super.key,
    required this.settings,
    required this.child,
  });

  final AppAppearanceSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final isCustom = settings.theme == AppThemePreference.custom;
    final rootColor = isCustom
        ? settings.backgroundColor.withValues(alpha: 1)
        : palette.page.withValues(alpha: 1);

    return BackdropGroup(
      child: ColoredBox(
        color: rootColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isCustom && settings.background == AppBackgroundStyle.photo)
              _PhotoWallpaper(settings: settings),
            if (isCustom && settings.background == AppBackgroundStyle.pattern)
              AppAppearancePattern(
                style: settings.pattern,
                color: settings.patternColor,
                intensity: settings.patternIntensity,
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class _PhotoWallpaper extends StatelessWidget {
  const _PhotoWallpaper({required this.settings});

  final AppAppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final wallpaper = buildAppearanceWallpaperImage(settings.wallpaperPath);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (wallpaper != null)
            ImageFiltered(
              enabled: settings.photoBlur > 0.01,
              imageFilter: ImageFilter.blur(
                sigmaX: settings.photoBlur,
                sigmaY: settings.photoBlur,
              ),
              child: Transform.scale(
                scale: settings.photoBlur > 0.01 ? 1.04 : 1,
                child: wallpaper,
              ),
            ),
          ColoredBox(
            color: settings.backgroundColor.withValues(
              alpha: settings.photoDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight seamless appearance motif that can fill either the app
/// background or a constrained preview tile.
class AppAppearancePattern extends StatelessWidget {
  const AppAppearancePattern({
    super.key,
    required this.style,
    required this.color,
    required this.intensity,
    this.child,
  });

  final AppPatternStyle style;
  final Color color;
  final double intensity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AppearancePatternPainter(
          style: style,
          color: color,
          intensity: intensity,
        ),
        isComplex: true,
        child: child,
      ),
    );
  }
}

class _AppearancePatternPainter extends CustomPainter {
  const _AppearancePatternPainter({
    required this.style,
    required this.color,
    required this.intensity,
  });

  final AppPatternStyle style;
  final Color color;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = intensity.clamp(0.0, 1.0).toDouble();
    if (strength <= 0 || size.isEmpty) return;

    final primaryPaint = Paint()
      ..color = color.withValues(alpha: color.a * strength * 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final secondaryPaint = Paint()
      ..color = color.withValues(alpha: color.a * strength * 0.13)
      ..style = PaintingStyle.fill;

    switch (style) {
      case AppPatternStyle.dots:
        for (double y = 14; y < size.height; y += 28) {
          final offset = ((y / 28).round().isEven) ? 0.0 : 14.0;
          for (double x = 10 + offset; x < size.width; x += 28) {
            canvas.drawCircle(Offset(x, y), 1.35, secondaryPaint);
          }
        }
      case AppPatternStyle.diagonal:
        for (double x = -size.height; x < size.width; x += 30) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            primaryPaint,
          );
        }
      case AppPatternStyle.waves:
        final path = Path();
        for (double y = 18; y < size.height; y += 34) {
          path.moveTo(0, y);
          for (double x = 0; x < size.width; x += 44) {
            path.cubicTo(x + 11, y - 6, x + 33, y + 6, x + 44, y);
          }
        }
        canvas.drawPath(path, primaryPaint);
      case AppPatternStyle.grid:
        for (double x = 0; x < size.width; x += 34) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), primaryPaint);
        }
        for (double y = 0; y < size.height; y += 34) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), primaryPaint);
        }
        for (double y = 17; y < size.height; y += 34) {
          for (double x = 17; x < size.width; x += 34) {
            canvas.drawCircle(
              Offset(x, y),
              0.9 + math.sin((x + y) / 60).abs() * 0.5,
              secondaryPaint,
            );
          }
        }
      case AppPatternStyle.doodles:
        _paintDoodles(canvas, size, primaryPaint, secondaryPaint);
      case AppPatternStyle.confetti:
        _paintConfetti(canvas, size, primaryPaint, secondaryPaint);
      case AppPatternStyle.bubbles:
        _paintBubbles(canvas, size, primaryPaint, secondaryPaint);
    }
  }

  void _paintDoodles(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint fillPaint,
  ) {
    const cellWidth = 54.0;
    const cellHeight = 48.0;
    var row = 0;
    for (
      double y = -cellHeight;
      y < size.height + cellHeight;
      y += cellHeight
    ) {
      final shift = row.isOdd ? cellWidth / 2 : 0.0;
      var column = 0;
      for (
        double x = -cellWidth + shift;
        x < size.width + cellWidth;
        x += cellWidth
      ) {
        final center = Offset(x + cellWidth / 2, y + cellHeight / 2);
        switch ((row * 3 + column * 5).abs() % 5) {
          case 0:
            _drawSparkle(canvas, center, linePaint);
          case 1:
            _drawHanger(canvas, center, linePaint);
          case 2:
            _drawLeaf(canvas, center, linePaint);
          case 3:
            _drawButton(canvas, center, linePaint, fillPaint);
          case 4:
            _drawStitch(canvas, center, linePaint, fillPaint);
        }
        column++;
      }
      row++;
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - 8)
      ..quadraticBezierTo(center.dx, center.dy - 2, center.dx + 7, center.dy)
      ..quadraticBezierTo(center.dx, center.dy + 2, center.dx, center.dy + 8)
      ..quadraticBezierTo(center.dx, center.dy + 2, center.dx - 7, center.dy)
      ..quadraticBezierTo(center.dx, center.dy - 2, center.dx, center.dy - 8);
    canvas.drawPath(path, paint);
  }

  void _drawHanger(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - 4)
      ..cubicTo(
        center.dx - 1,
        center.dy - 9,
        center.dx + 6,
        center.dy - 10,
        center.dx + 5,
        center.dy - 5,
      )
      ..cubicTo(
        center.dx + 5,
        center.dy - 2,
        center.dx + 1,
        center.dy - 2,
        center.dx,
        center.dy,
      )
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - 10, center.dy + 7)
      ..quadraticBezierTo(
        center.dx,
        center.dy + 10,
        center.dx + 10,
        center.dy + 7,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawLeaf(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 8, center.dy + 6)
      ..quadraticBezierTo(
        center.dx - 7,
        center.dy - 7,
        center.dx + 8,
        center.dy - 7,
      )
      ..quadraticBezierTo(
        center.dx + 7,
        center.dy + 7,
        center.dx - 8,
        center.dy + 6,
      )
      ..moveTo(center.dx - 6, center.dy + 4)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + 6, center.dy - 5);
    canvas.drawPath(path, paint);
  }

  void _drawButton(
    Canvas canvas,
    Offset center,
    Paint linePaint,
    Paint fillPaint,
  ) {
    canvas.drawCircle(center, 7.5, linePaint);
    canvas.drawCircle(center + const Offset(-2.3, -2.3), 1.05, fillPaint);
    canvas.drawCircle(center + const Offset(2.3, -2.3), 1.05, fillPaint);
    canvas.drawCircle(center + const Offset(-2.3, 2.3), 1.05, fillPaint);
    canvas.drawCircle(center + const Offset(2.3, 2.3), 1.05, fillPaint);
  }

  void _drawStitch(
    Canvas canvas,
    Offset center,
    Paint linePaint,
    Paint fillPaint,
  ) {
    final path = Path()
      ..moveTo(center.dx - 9, center.dy + 4)
      ..cubicTo(
        center.dx - 5,
        center.dy - 7,
        center.dx + 2,
        center.dy + 8,
        center.dx + 9,
        center.dy - 4,
      );
    canvas.drawPath(path, linePaint);
    canvas.drawCircle(center + const Offset(-9, 4), 1.35, fillPaint);
    canvas.drawCircle(center + const Offset(9, -4), 1.35, fillPaint);
  }

  void _paintConfetti(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint fillPaint,
  ) {
    const cell = 38.0;
    var row = 0;
    for (double y = -cell; y < size.height + cell; y += cell) {
      final shift = row.isOdd ? cell / 2 : 0.0;
      var column = 0;
      for (double x = -cell + shift; x < size.width + cell; x += cell) {
        final center = Offset(x + cell / 2, y + cell / 2);
        final motif = (row * 7 + column * 3).abs() % 5;
        switch (motif) {
          case 0:
            canvas.drawLine(
              center + const Offset(-4, 3),
              center + const Offset(4, -3),
              linePaint,
            );
          case 1:
            canvas.drawCircle(center, 3.2, linePaint);
          case 2:
            final diamond = Path()
              ..moveTo(center.dx, center.dy - 4)
              ..lineTo(center.dx + 3.2, center.dy)
              ..lineTo(center.dx, center.dy + 4)
              ..lineTo(center.dx - 3.2, center.dy)
              ..close();
            canvas.drawPath(diamond, fillPaint);
          case 3:
            canvas.drawLine(
              center + const Offset(-4, 0),
              center + const Offset(4, 0),
              linePaint,
            );
            canvas.drawLine(
              center + const Offset(0, -4),
              center + const Offset(0, 4),
              linePaint,
            );
          case 4:
            canvas.drawArc(
              Rect.fromCircle(center: center, radius: 5),
              math.pi * 0.15,
              math.pi * 1.15,
              false,
              linePaint,
            );
        }
        column++;
      }
      row++;
    }
  }

  void _paintBubbles(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint fillPaint,
  ) {
    const stepX = 58.0;
    const stepY = 50.0;
    var row = 0;
    for (double y = -stepY; y < size.height + stepY; y += stepY) {
      final shift = row.isOdd ? stepX / 2 : 0.0;
      var column = 0;
      for (double x = -stepX + shift; x < size.width + stepX; x += stepX) {
        final center = Offset(x + stepX / 2, y + stepY / 2);
        final radius = 7.0 + ((row + column).abs() % 3) * 2.5;
        canvas.drawCircle(center, radius, linePaint);
        canvas.drawCircle(
          center + Offset(radius * 0.72, -radius * 0.55),
          2.2,
          fillPaint,
        );
        if ((row + column).isEven) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius - 3),
            math.pi * 0.9,
            math.pi * 0.65,
            false,
            linePaint,
          );
        }
        column++;
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _AppearancePatternPainter oldDelegate) {
    return style != oldDelegate.style ||
        color != oldDelegate.color ||
        intensity != oldDelegate.intensity;
  }
}
