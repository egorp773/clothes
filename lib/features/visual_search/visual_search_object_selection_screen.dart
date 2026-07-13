import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

import 'visual_search_service.dart';

class VisualSearchObjectSelectionResult {
  const VisualSearchObjectSelectionResult.crop(this.cropBounds)
    : useWholePhoto = false;

  const VisualSearchObjectSelectionResult.wholePhoto()
    : cropBounds = null,
      useWholePhoto = true;

  final Rect? cropBounds;
  final bool useWholePhoto;
}

class VisualSearchObjectSelectionScreen extends StatefulWidget {
  const VisualSearchObjectSelectionScreen({
    super.key,
    required this.previewBytes,
    required this.imageSize,
    required this.regions,
  });

  final Uint8List previewBytes;
  final Size imageSize;
  final List<VisualSearchRegion> regions;

  @override
  State<VisualSearchObjectSelectionScreen> createState() =>
      _VisualSearchObjectSelectionScreenState();
}

class _VisualSearchObjectSelectionScreenState
    extends State<VisualSearchObjectSelectionScreen> {
  int? _selectedIndex;
  bool _manual = false;
  bool _manualAdjusted = false;
  Rect _manualBounds = const Rect.fromLTRB(0.16, 0.16, 0.84, 0.82);
  Offset? _manualDragStart;

  bool get _canSubmit => _manual ? _manualAdjusted : _selectedIndex != null;

  Rect get _selectedBounds =>
      _manual ? _manualBounds : widget.regions[_selectedIndex!].bounds;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        _buildPhoto(),
        Positioned(
          left: 14,
          top: MediaQuery.paddingOf(context).top + 10,
          child: _SelectionRoundButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Назад',
            onTap: () => Navigator.pop(context),
          ),
        ),
        Align(alignment: Alignment.bottomCenter, child: _buildBottomPanel()),
      ],
    ),
  );

  Widget _buildPhoto() => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      final fitted = applyBoxFit(BoxFit.contain, widget.imageSize, viewport);
      final imageRect = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & viewport,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: imageRect,
            child: Image.memory(
              widget.previewBytes,
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
          if (_manual)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                final point = _normalizedPoint(
                  details.localPosition,
                  imageRect,
                );
                if (point == null) return;
                _manualDragStart = point;
                setState(() => _manualBounds = Rect.fromPoints(point, point));
              },
              onPanUpdate: (details) {
                final start = _manualDragStart;
                final point = _normalizedPoint(
                  details.localPosition,
                  imageRect,
                );
                if (start == null || point == null) return;
                setState(() {
                  _manualBounds = Rect.fromPoints(start, point);
                  _manualAdjusted = true;
                });
              },
              onPanEnd: (_) {
                _manualDragStart = null;
                if (_manualBounds.width >= 0.06 &&
                    _manualBounds.height >= 0.06) {
                  return;
                }
                final center = _manualBounds.center;
                setState(() {
                  _manualBounds = Rect.fromCenter(
                    center: center,
                    width: 0.34,
                    height: 0.34,
                  ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
                  _manualAdjusted = true;
                });
              },
              child: CustomPaint(
                painter: _ManualSelectionPainter(
                  imageRect: imageRect,
                  selectionRect: _mapRect(_manualBounds, imageRect),
                ),
              ),
            )
          else
            ...widget.regions.indexed.map((entry) {
              final index = entry.$1;
              final region = entry.$2;
              final selected = index == _selectedIndex;
              return Positioned.fromRect(
                rect: _mapRect(region.bounds, imageRect),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: selected ? 0.95 : 0.52,
                        ),
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: Color(0x4D9EEBFF),
                                blurRadius: 16,
                              ),
                            ]
                          : null,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xB31A1A1C),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _regionTitle(region, index),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      );
    },
  );

  Widget _buildBottomPanel() => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          18,
          15,
          18,
          14 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE8171719),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Что ищем?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _manual
                  ? 'Проведите по вещи, чтобы выделить её'
                  : 'Выберите вещь на фото',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            if (!_manual) ...[
              const SizedBox(height: 13),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.regions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final selected = index == _selectedIndex;
                    return ChoiceChip(
                      label: Text(_regionTitle(widget.regions[index], index)),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedIndex = index),
                      showCheckmark: false,
                      side: BorderSide(
                        color: Colors.white.withValues(
                          alpha: selected ? 0.9 : 0.18,
                        ),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      selectedColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: const StadiumBorder(),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _canSubmit
                    ? () => Navigator.pop(
                        context,
                        VisualSearchObjectSelectionResult.crop(_selectedBounds),
                      )
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white24,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'Найти похожее',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const VisualSearchObjectSelectionResult.wholePhoto(),
                    ),
                    child: const Text(
                      'Искать по всему фото',
                      maxLines: 1,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _manual = !_manual;
                      _manualAdjusted = false;
                      _selectedIndex = null;
                    }),
                    child: Text(
                      _manual ? 'К найденным вещам' : 'Выбрать вручную',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Offset? _normalizedPoint(Offset point, Rect imageRect) {
    if (!imageRect.contains(point)) return null;
    return Offset(
      ((point.dx - imageRect.left) / imageRect.width).clamp(0, 1),
      ((point.dy - imageRect.top) / imageRect.height).clamp(0, 1),
    );
  }

  Rect _mapRect(Rect normalized, Rect imageRect) => Rect.fromLTRB(
    imageRect.left + normalized.left * imageRect.width,
    imageRect.top + normalized.top * imageRect.height,
    imageRect.left + normalized.right * imageRect.width,
    imageRect.top + normalized.bottom * imageRect.height,
  );

  String _regionTitle(VisualSearchRegion region, int index) {
    final label = region.label?.trim().toLowerCase();
    return switch (label) {
      'jacket' => 'Куртка',
      'coat' => 'Пальто',
      'jeans' => 'Джинсы',
      'trousers' => 'Брюки',
      'bag' => 'Сумка',
      'backpack' => 'Рюкзак',
      'sneakers' => 'Кроссовки',
      'shoes' => 'Обувь',
      'dress' => 'Платье',
      'shirt' => 'Рубашка',
      'tshirt' => 'Футболка',
      'hoodie' => 'Худи',
      'skirt' => 'Юбка',
      'upper_clothing' => 'Верх',
      'lower_clothing' => 'Низ',
      'full_clothing' => 'Одежда',
      _ => 'Предмет ${index + 1}',
    };
  }
}

class _SelectionRoundButton extends StatelessWidget {
  const _SelectionRoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: const Color(0x80171719),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    ),
  );
}

class _ManualSelectionPainter extends CustomPainter {
  const _ManualSelectionPainter({
    required this.imageRect,
    required this.selectionRect,
  });

  final Rect imageRect;
  final Rect selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRRect(
        RRect.fromRectAndRadius(selectionRect, const Radius.circular(16)),
      );
    canvas.drawPath(shade, Paint()..color = const Color(0x66000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(selectionRect, const Radius.circular(16)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ManualSelectionPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.selectionRect != selectionRect;
}

Future<XFile> cropVisualSearchImage(XFile source, Rect bounds) async {
  final bytes = await source.readAsBytes();
  final cropped = await compute(_cropJpeg, {
    'bytes': bytes,
    'left': bounds.left,
    'top': bounds.top,
    'right': bounds.right,
    'bottom': bounds.bottom,
  });
  return XFile.fromData(
    cropped,
    mimeType: 'image/jpeg',
    name: 'visual-search-crop.jpg',
  );
}

Future<XFile> normalizeVisualSearchImage(
  XFile source, {
  int maxSide = 1600,
}) async {
  final bytes = await source.readAsBytes();
  final normalized = await compute(_normalizeJpeg, {
    'bytes': bytes,
    'maxSide': maxSide,
  });
  return XFile.fromData(
    normalized,
    mimeType: 'image/jpeg',
    name: 'visual-search-photo.jpg',
  );
}

Uint8List _cropJpeg(Map<String, Object> input) {
  final decoded = image_lib.decodeImage(input['bytes']! as Uint8List);
  if (decoded == null) throw StateError('Unable to decode image');
  final image = image_lib.bakeOrientation(decoded);
  final left = ((input['left']! as double) * image.width).floor().clamp(
    0,
    image.width - 1,
  );
  final top = ((input['top']! as double) * image.height).floor().clamp(
    0,
    image.height - 1,
  );
  final right = ((input['right']! as double) * image.width).ceil().clamp(
    left + 1,
    image.width,
  );
  final bottom = ((input['bottom']! as double) * image.height).ceil().clamp(
    top + 1,
    image.height,
  );
  final cropped = image_lib.copyCrop(
    image,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  return Uint8List.fromList(image_lib.encodeJpg(cropped, quality: 92));
}

Uint8List _normalizeJpeg(Map<String, Object> input) {
  final decoded = image_lib.decodeImage(input['bytes']! as Uint8List);
  if (decoded == null) throw StateError('Unable to decode image');
  var image = image_lib.bakeOrientation(decoded);
  final maxSide = input['maxSide']! as int;
  if (image.width > maxSide || image.height > maxSide) {
    image = image_lib.copyResize(
      image,
      width: image.width >= image.height ? maxSide : null,
      height: image.height > image.width ? maxSide : null,
      interpolation: image_lib.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(image_lib.encodeJpg(image, quality: 90));
}
