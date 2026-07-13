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
    this.regionsFuture,
  });

  final Uint8List previewBytes;
  final Size imageSize;
  final List<VisualSearchRegion> regions;
  final Future<List<VisualSearchRegion>>? regionsFuture;

  @override
  State<VisualSearchObjectSelectionScreen> createState() =>
      _VisualSearchObjectSelectionScreenState();
}

class _VisualSearchObjectSelectionScreenState
    extends State<VisualSearchObjectSelectionScreen> {
  static const _accentColor = Color(0xFFFFD166);

  late List<VisualSearchRegion> _regions;
  int? _selectedIndex;
  bool _manual = true;
  bool _regionsLoading = false;
  Rect? _manualBounds;
  Offset? _manualDragStart;

  bool get _hasManualSelection {
    final bounds = _manualBounds;
    return bounds != null && bounds.width >= 0.06 && bounds.height >= 0.06;
  }

  bool get _canSubmit => _manual ? _hasManualSelection : _selectedIndex != null;

  Rect get _selectedBounds =>
      _manual ? _manualBounds! : _regions[_selectedIndex!].bounds;

  @override
  void initState() {
    super.initState();
    _regions = widget.regions;
    _regionsLoading = widget.regionsFuture != null;
    _loadSuggestedRegions();
  }

  Future<void> _loadSuggestedRegions() async {
    final future = widget.regionsFuture;
    if (future == null) return;
    List<VisualSearchRegion> regions;
    try {
      regions = await future;
    } catch (_) {
      regions = const [];
    }
    if (!mounted) return;
    setState(() {
      _regions = regions;
      _regionsLoading = false;
      if (_selectedIndex case final index? when index >= regions.length) {
        _selectedIndex = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Column(
      children: [
        Expanded(
          child: Stack(
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
            ],
          ),
        ),
        _buildBottomPanel(),
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
              key: const Key('visual-search-selection-photo'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
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
                setState(() => _manualBounds = Rect.fromPoints(start, point));
              },
              onPanEnd: (_) {
                _manualDragStart = null;
                final bounds = _manualBounds;
                if (bounds == null) return;
                if (bounds.width >= 0.06 && bounds.height >= 0.06) {
                  return;
                }
                final center = bounds.center;
                setState(
                  () => _manualBounds = Rect.fromCenter(
                    center: center,
                    width: 0.34,
                    height: 0.34,
                  ).intersect(const Rect.fromLTWH(0, 0, 1, 1)),
                );
              },
              child: CustomPaint(
                painter: _ManualSelectionPainter(
                  imageRect: imageRect,
                  selectionRect: _manualBounds == null
                      ? null
                      : _mapRect(_manualBounds!, imageRect),
                ),
              ),
            )
          else
            Positioned.fromRect(
              rect: imageRect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _selectRegionAt(details.localPosition, imageRect.size),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ..._regions.indexed.map((entry) {
                      final index = entry.$1;
                      final region = entry.$2;
                      final selected = index == _selectedIndex;
                      return Positioned.fromRect(
                        rect: _mapRect(
                          region.bounds,
                          Offset.zero & imageRect.size,
                        ),
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 170),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _accentColor.withValues(alpha: 0.16)
                                  : Colors.black.withValues(alpha: 0.08),
                              border: Border.all(
                                color: selected
                                    ? _accentColor
                                    : Colors.white.withValues(alpha: 0.9),
                                width: selected ? 3 : 2,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                const BoxShadow(
                                  color: Color(0xB3000000),
                                  blurRadius: 7,
                                  spreadRadius: 1,
                                ),
                                if (selected)
                                  const BoxShadow(
                                    color: Color(0x66FFD166),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                              ],
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
                                  color: selected
                                      ? _accentColor
                                      : const Color(0xE61A1A1C),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected) ...[
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Colors.black,
                                      ),
                                      const SizedBox(width: 3),
                                    ],
                                    Flexible(
                                      child: Text(
                                        _regionTitle(region, index),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildBottomPanel() => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(
      18,
      14,
      18,
      14 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: const Color(0xFF171719),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      border: Border(
        top: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 20,
          offset: Offset(0, -6),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _manual ? 'Выделите вещь вручную' : 'Выберите вещь на фото',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _manual
              ? _hasManualSelection
                    ? 'Если рамка неточная, просто нарисуйте её заново'
                    : 'Проведите пальцем по одной вещи на фото'
              : 'Нажмите на рамку или выберите пункт ниже',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.12),
            border: Border.all(color: _accentColor.withValues(alpha: 0.72)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.touch_app_rounded, color: _accentColor, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Ручной выбор точнее. ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: 'Автоопределение может ошибаться.'),
                    ],
                  ),
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SelectionModeButton(
                icon: Icons.crop_free_rounded,
                label: 'Выбрать вручную',
                selected: _manual,
                onTap: _enableManualSelection,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SelectionModeButton(
                icon: Icons.auto_awesome_rounded,
                label: _regionsLoading
                    ? 'Ищем вещи…'
                    : _regions.isEmpty
                    ? 'Автовыбор недоступен'
                    : 'Автовыбор',
                selected: !_manual,
                onTap: _regionsLoading || _regions.isEmpty
                    ? null
                    : _enableAutomaticSelection,
              ),
            ),
          ],
        ),
        if (!_manual) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _regions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = index == _selectedIndex;
                return ChoiceChip(
                  label: Text(_regionTitle(_regions[index], index)),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedIndex = index),
                  showCheckmark: false,
                  side: BorderSide(
                    color: selected
                        ? _accentColor
                        : Colors.white.withValues(alpha: 0.68),
                    width: selected ? 2 : 1.5,
                  ),
                  backgroundColor: const Color(0xFF303034),
                  selectedColor: _accentColor,
                  labelStyle: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: const StadiumBorder(),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
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
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.14),
              disabledForegroundColor: Colors.white54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Text(
              _manual ? 'Найти выделенную вещь' : 'Найти выбранную вещь',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(
              context,
              const VisualSearchObjectSelectionResult.wholePhoto(),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.62)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.fullscreen_rounded, size: 19),
            label: const Text(
              'Искать по всему фото',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );

  Offset? _normalizedPoint(Offset point, Rect imageRect) {
    if (!imageRect.contains(point)) return null;
    return Offset(
      ((point.dx - imageRect.left) / imageRect.width).clamp(0, 1),
      ((point.dy - imageRect.top) / imageRect.height).clamp(0, 1),
    );
  }

  void _selectRegionAt(Offset point, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final normalized = Offset(
      (point.dx / imageSize.width).clamp(0, 1),
      (point.dy / imageSize.height).clamp(0, 1),
    );
    int? bestIndex;
    var bestArea = double.infinity;
    var bestConfidence = -double.infinity;
    for (final entry in _regions.indexed) {
      final region = entry.$2;
      if (!region.bounds.contains(normalized)) continue;
      final area = region.bounds.width * region.bounds.height;
      if (area < bestArea ||
          (area == bestArea && region.confidence > bestConfidence)) {
        bestIndex = entry.$1;
        bestArea = area;
        bestConfidence = region.confidence;
      }
    }
    if (bestIndex != null && bestIndex != _selectedIndex) {
      setState(() => _selectedIndex = bestIndex);
    }
  }

  void _enableManualSelection() {
    if (_manual) return;
    setState(() {
      _manual = true;
      final selectedIndex = _selectedIndex;
      if (selectedIndex != null) {
        _manualBounds = _regions[selectedIndex].bounds;
      }
    });
  }

  void _enableAutomaticSelection() {
    if (!_manual || _regions.isEmpty) return;
    setState(() {
      _manual = false;
      _selectedIndex ??= _bestRegionIndex();
    });
  }

  int _bestRegionIndex() {
    var bestIndex = 0;
    for (var index = 1; index < _regions.length; index++) {
      if (_regions[index].confidence > _regions[bestIndex].confidence) {
        bestIndex = index;
      }
    }
    return bestIndex;
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

class _SelectionModeButton extends StatelessWidget {
  const _SelectionModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected
          ? _VisualSearchObjectSelectionScreenState._accentColor
          : Colors.white.withValues(alpha: onTap == null ? 0.04 : 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? _VisualSearchObjectSelectionScreenState._accentColor
                  : Colors.white.withValues(alpha: onTap == null ? 0.1 : 0.3),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? Colors.black
                    : Colors.white.withValues(alpha: onTap == null ? 0.38 : 1),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? Colors.black
                        : Colors.white.withValues(
                            alpha: onTap == null ? 0.38 : 1,
                          ),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
  final Rect? selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    final selected = selectionRect;
    if (selected == null || selected.isEmpty) return;
    final roundedSelection = RRect.fromRectAndRadius(
      selected,
      const Radius.circular(14),
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRRect(roundedSelection);
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
      roundedSelection,
      Paint()..color = const Color(0x1FFFD166),
    );
    canvas.drawRRect(
      roundedSelection,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawRRect(
      roundedSelection,
      Paint()
        ..color = _VisualSearchObjectSelectionScreenState._accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    final handleShadow = Paint()..color = Colors.black.withValues(alpha: 0.82);
    final handle = Paint()
      ..color = _VisualSearchObjectSelectionScreenState._accentColor;
    for (final corner in [
      selected.topLeft,
      selected.topRight,
      selected.bottomLeft,
      selected.bottomRight,
    ]) {
      canvas
        ..drawCircle(corner, 6.5, handleShadow)
        ..drawCircle(corner, 4.5, handle);
    }
  }

  @override
  bool shouldRepaint(covariant _ManualSelectionPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.selectionRect != selectionRect;
}

Future<XFile> cropVisualSearchImage(
  XFile source,
  Rect bounds, {
  Uint8List? imageBytes,
}) async {
  final bytes = imageBytes ?? await source.readAsBytes();
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
  int maxSide = 1024,
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

Future<Size> visualSearchImageSize(Uint8List bytes) async {
  final dimensions = await compute(_decodeImageSize, bytes);
  return Size(dimensions[0].toDouble(), dimensions[1].toDouble());
}

List<int> _decodeImageSize(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) throw StateError('Unable to decode image');
  final image = image_lib.bakeOrientation(decoded);
  return [image.width, image.height];
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
  return Uint8List.fromList(image_lib.encodeJpg(image, quality: 88));
}
