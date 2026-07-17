import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_appearance.dart';
import '../core/app_typography.dart';

Future<Color?> showAppColorPicker({
  required BuildContext context,
  required String title,
  required Color initialColor,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) =>
        AppColorPickerSheet(title: title, initialColor: initialColor),
  );
}

class AppColorPickerSheet extends StatefulWidget {
  const AppColorPickerSheet({
    super.key,
    required this.title,
    required this.initialColor,
  });

  final String title;
  final Color initialColor;

  @override
  State<AppColorPickerSheet> createState() => _AppColorPickerSheetState();
}

class _AppColorPickerSheetState extends State<AppColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);
  late final TextEditingController _hexController = TextEditingController(
    text: _hexValue(widget.initialColor),
  );

  Color get _color => _hsv.toColor().withValues(alpha: 1);

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor value, {bool syncHex = true}) {
    setState(() => _hsv = value);
    if (syncHex) _replaceHex(_hexValue(value.toColor()));
  }

  void _setSaturationAndValue(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _setHsv(
      _hsv
          .withSaturation((position.dx / size.width).clamp(0, 1))
          .withValue((1 - position.dy / size.height).clamp(0, 1)),
    );
  }

  void _setHue(double x, double width) {
    if (width <= 0) return;
    _setHsv(_hsv.withHue((x / width).clamp(0, 1) * 360));
  }

  void _handleHex(String raw) {
    if (raw.length != 6) return;
    final value = int.tryParse(raw, radix: 16);
    if (value == null) return;
    final color = Color(0xFF000000 | value);
    _setHsv(HSVColor.fromColor(color), syncHex: false);
  }

  void _replaceHex(String value) {
    _hexController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return AnimatedPadding(
      key: const Key('app-color-picker-sheet'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(18, 0, 18, keyboard + safeBottom + 18),
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 19,
                          fontWeight: AppTypography.bold,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.border, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: palette.shadow,
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, 218);
                    return Semantics(
                      label: 'Насыщенность и яркость цвета',
                      value:
                          '${(_hsv.saturation * 100).round()}%, ${(_hsv.value * 100).round()}%',
                      child: GestureDetector(
                        key: const Key('app-color-picker-sv'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _setSaturationAndValue(details.localPosition, size),
                        onPanStart: (details) =>
                            _setSaturationAndValue(details.localPosition, size),
                        onPanUpdate: (details) =>
                            _setSaturationAndValue(details.localPosition, size),
                        child: SizedBox(
                          height: size.height,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _SaturationValuePainter(
                                      hue: _hsv.hue,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: _hsv.saturation * size.width - 11,
                                  top: (1 - _hsv.value) * size.height - 11,
                                  child: _PickerThumb(color: _color),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 15),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return Semantics(
                      label: 'Оттенок цвета',
                      value: '${_hsv.hue.round()} градусов',
                      child: GestureDetector(
                        key: const Key('app-color-picker-hue'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _setHue(details.localPosition.dx, width),
                        onPanStart: (details) =>
                            _setHue(details.localPosition.dx, width),
                        onPanUpdate: (details) =>
                            _setHue(details.localPosition.dx, width),
                        child: SizedBox(
                          height: 34,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFF0000),
                                      Color(0xFFFFFF00),
                                      Color(0xFF00FF00),
                                      Color(0xFF00FFFF),
                                      Color(0xFF0000FF),
                                      Color(0xFFFF00FF),
                                      Color(0xFFFF0000),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: (_hsv.hue / 360) * width - 9,
                                child: Container(
                                  width: 18,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: HSVColor.fromAHSV(
                                      1,
                                      _hsv.hue,
                                      1,
                                      1,
                                    ).toColor(),
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x44000000),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('app-color-picker-hex'),
                  controller: _hexController,
                  onChanged: _handleHex,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                    _UpperCaseTextFormatter(),
                  ],
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: AppTypography.semiBold,
                    letterSpacing: 1.1,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'HEX',
                    prefixText: '#',
                    prefixStyle: TextStyle(color: palette.muted),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: const Key('app-color-picker-apply'),
                        onPressed: () => Navigator.pop(context, _color),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _color,
                          foregroundColor: _readableOn(_color),
                          overlayColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Готово'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerThumb extends StatelessWidget {
  const _PickerThumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
        ),
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) =>
      hue != oldDelegate.hue;
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

String _hexValue(Color color) => (color.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

Color _readableOn(Color color) {
  final luminance = color.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast
      ? const Color(0xFF121316)
      : Colors.white;
}
