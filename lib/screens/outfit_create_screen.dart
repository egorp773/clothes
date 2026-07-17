import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/created_outfit.dart';
import '../models/outfit_accessory.dart';
import '../models/product.dart';
import '../screens/new_outfit_screen.dart';
import '../services/background_removal_service.dart';
import '../widgets/app_image.dart';

typedef CreateOutfitAccessory =
    Future<OutfitAccessory?> Function(
      XFile imageFile, {
      required bool isDefault,
      required String title,
    });

class OutfitCreateScreen extends StatefulWidget {
  const OutfitCreateScreen({
    super.key,
    this.onClose,
    this.myProducts = const [],
    this.likedProducts = const [],
    this.defaultAccessories = const [],
    this.myAccessories = const [],
    this.onCreateAccessory,
    this.authorName = 'Автор',
    this.authorHandle = '@user',
    this.authorAvatarUrl = '',
    this.onPublish,
  });

  final VoidCallback? onClose;
  final List<Product> myProducts;
  final List<Product> likedProducts;
  final List<OutfitAccessory> defaultAccessories;
  final List<OutfitAccessory> myAccessories;
  final CreateOutfitAccessory? onCreateAccessory;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
  final Future<void> Function(CreatedOutfit outfit)? onPublish;

  @override
  State<OutfitCreateScreen> createState() => _OutfitCreateScreenState();
}

class _OutfitCreateScreenState extends State<OutfitCreateScreen> {
  static const double _outfitMediaWidth = 357;
  static const double _outfitMediaHeight = 520;
  static const double _outfitMediaAspectRatio =
      _outfitMediaWidth / _outfitMediaHeight;
  static const double _canvasItemWidthFactor = 0.42;
  static const double _canvasItemHeightFactor = 0.28;

  final ImagePicker _picker = ImagePicker();
  final List<Product> _privateProducts = [];
  final List<Product> _selectedProducts = [];
  final List<OutfitAccessory> _localDefaultAccessories = [];
  final List<OutfitAccessory> _localMyAccessories = [];
  final Map<String, _CanvasItemTransform> _itemTransforms = {};
  Color _canvasColor = Colors.white;

  List<Product> get _myItems => [..._privateProducts, ...widget.myProducts];
  List<OutfitAccessory> get _defaultAccessories => [
    ..._localDefaultAccessories,
    ...widget.defaultAccessories,
  ];
  List<OutfitAccessory> get _myAccessories => [
    ..._localMyAccessories,
    ...widget.myAccessories,
  ];

  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
      return;
    }
    Navigator.maybePop(context);
  }

  Product _latestProduct(Product product) {
    for (final item in _privateProducts) {
      if (item.id == product.id) return item;
    }
    return product;
  }

  void _addProduct(Product product) {
    final latestProduct = _latestProduct(product);
    if (_isProductProcessing(latestProduct)) return;
    setState(() {
      if (_selectedProducts.any((item) => item.id == latestProduct.id)) return;
      _itemTransforms[latestProduct.id] = _defaultItemTransform(
        _selectedProducts.length,
      );
      _selectedProducts.add(latestProduct);
    });
    Navigator.maybePop(context);
  }

  Future<void> _createClothingFromSource(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final product = Product(
      id: 'local-outfit-$timestamp',
      title: 'Вещь для образа',
      detailTitle: 'Вещь для образа',
      price: '',
      detailPrice: '',
      priceValue: 0,
      image: picked.path,
      category: 'Одежда',
      brand: '',
      size: '',
      color: '',
      condition: '',
      dotsOnDark: false,
      isHidden: true,
      isLocal: true,
      images: [picked.path],
      outfitImages: [picked.path],
    );

    setState(() {
      _privateProducts.insert(0, product);
    });

    _processCreatedClothing(product, picked);
  }

  void _processCreatedClothing(Product product, XFile imageFile) {
    unawaited(_removeCreatedClothingBackground(product, imageFile));
  }

  Future<void> _removeCreatedClothingBackground(
    Product product,
    XFile imageFile,
  ) async {
    try {
      final result = await removeBackgroundFromBytes(
        await imageFile.readAsBytes(),
        fileName: '${product.id}.png',
      );
      if (!mounted) return;
      setState(() {
        final index = _privateProducts.indexWhere(
          (item) => item.id == product.id,
        );
        if (index == -1) return;
        _privateProducts[index] = _privateProducts[index].copyWith(
          outfitImages: [result.preview],
        );
        final selectedIndex = _selectedProducts.indexWhere(
          (item) => item.id == product.id,
        );
        if (selectedIndex != -1) {
          _selectedProducts[selectedIndex] = _selectedProducts[selectedIndex]
              .copyWith(outfitImages: [result.preview]);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось подготовить вещь'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isProductProcessing(Product product) {
    final latestProduct = _latestProduct(product);
    return latestProduct.isLocal && latestProduct.outfitImages.isEmpty;
  }

  OutfitAccessory _latestAccessory(OutfitAccessory accessory) {
    for (final item in [..._localDefaultAccessories, ..._localMyAccessories]) {
      if (item.id == accessory.id) return item;
    }
    return accessory;
  }

  Product _accessoryAsProduct(OutfitAccessory accessory) {
    return Product(
      id: 'accessory-${accessory.id}',
      title: accessory.title,
      detailTitle: accessory.title,
      price: '',
      detailPrice: '',
      priceValue: 0,
      image: accessory.image,
      category: 'Аксессуар',
      brand: '',
      size: '',
      color: '',
      condition: '',
      ownerId: accessory.ownerId,
      dotsOnDark: false,
      isHidden: true,
      isLocal: accessory.isLocal,
      images: [accessory.image],
      outfitImages: [accessory.displayImage],
    );
  }

  void _addAccessory(OutfitAccessory accessory) {
    final latestAccessory = _latestAccessory(accessory);
    if (latestAccessory.isProcessing) return;
    final product = _accessoryAsProduct(latestAccessory);
    setState(() {
      if (_selectedProducts.any((item) => item.id == product.id)) return;
      _itemTransforms[product.id] = _defaultItemTransform(
        _selectedProducts.length,
      );
      _selectedProducts.add(product);
    });
    Navigator.maybePop(context);
  }

  Future<void> _createAccessoryFromSource({
    required ImageSource source,
    required bool isDefault,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    final title = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) =>
            _AccessoryTitleScreen(imagePath: picked.path, isDefault: isDefault),
      ),
    );
    if (title == null || !mounted) return;

    final cleanTitle = title.trim().isEmpty ? 'Аксессуар' : title.trim();
    final accessory = OutfitAccessory(
      id: 'local-accessory-${DateTime.now().microsecondsSinceEpoch}',
      title: cleanTitle,
      image: picked.path,
      cutoutImage: picked.path,
      scope: isDefault ? 'default' : 'private',
      ownerId: '',
      isLocal: true,
    );
    setState(() {
      final list = isDefault ? _localDefaultAccessories : _localMyAccessories;
      list.insert(0, accessory);
    });

    _processCreatedAccessory(
      accessory,
      imageFile: picked,
      isDefault: isDefault,
    );
    final createAccessory = widget.onCreateAccessory;
    if (createAccessory != null) {
      unawaited(
        createAccessory(picked, isDefault: isDefault, title: cleanTitle),
      );
    }
  }

  void _processCreatedAccessory(
    OutfitAccessory accessory, {
    required XFile imageFile,
    required bool isDefault,
  }) {
    unawaited(
      _removeCreatedAccessoryBackground(
        accessory,
        imageFile: imageFile,
        isDefault: isDefault,
      ),
    );
  }

  Future<void> _removeCreatedAccessoryBackground(
    OutfitAccessory accessory, {
    required XFile imageFile,
    required bool isDefault,
  }) async {
    try {
      final result = await removeBackgroundFromBytes(
        await imageFile.readAsBytes(),
        fileName: '${accessory.id}.png',
      );
      if (!mounted) return;
      setState(() {
        final list = isDefault ? _localDefaultAccessories : _localMyAccessories;
        final index = list.indexWhere((item) => item.id == accessory.id);
        if (index == -1) return;
        list[index] = list[index].copyWith(
          cutoutImage: result.preview,
          backgroundStatus: 'completed',
        );
        final productId = 'accessory-${accessory.id}';
        final selectedIndex = _selectedProducts.indexWhere(
          (item) => item.id == productId,
        );
        if (selectedIndex != -1) {
          _selectedProducts[selectedIndex] = _selectedProducts[selectedIndex]
              .copyWith(outfitImages: [result.preview]);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final list = isDefault ? _localDefaultAccessories : _localMyAccessories;
        final index = list.indexWhere((item) => item.id == accessory.id);
        if (index == -1) return;
        list[index] = list[index].copyWith(backgroundStatus: 'failed');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось подготовить аксессуар'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showClothesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClothesPickerSheet(
        myProducts: _myItems,
        likedProducts: widget.likedProducts,
        onProductTap: _addProduct,
        onCreateTap: () {
          Navigator.maybePop(context);
          Future<void>.delayed(const Duration(milliseconds: 120), () {
            if (!mounted) return;
            _createClothingFromSource(ImageSource.gallery);
          });
        },
        isProductProcessing: _isProductProcessing,
      ),
    );
  }

  void _showAccessoriesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccessoriesPickerSheet(
        defaultAccessories: _defaultAccessories,
        myAccessories: _myAccessories,
        onAccessoryTap: _addAccessory,
        onCreateTap: (isDefault) {
          Navigator.maybePop(context);
          Future<void>.delayed(const Duration(milliseconds: 120), () {
            if (!mounted) return;
            _createAccessoryFromSource(
              source: ImageSource.gallery,
              isDefault: isDefault,
            );
          });
        },
      ),
    );
  }

  void _showBackgroundSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BackgroundPickerSheet(
        initialColor: _canvasColor,
        onColorTap: (color) {
          setState(() => _canvasColor = color);
        },
      ),
    );
  }

  _CanvasItemTransform _defaultItemTransform(int index) {
    final column = index % 2;
    final row = index ~/ 2;
    return _CanvasItemTransform(
      offsetX: (column - 0.5) * _canvasItemWidthFactor * 0.82,
      offsetY: -0.22 + row * _canvasItemHeightFactor * 0.72,
      scale: 1,
      rotation: 0,
    );
  }

  void _rememberItemTransform(
    String productId,
    _CanvasItemTransform transform,
  ) {
    _itemTransforms[productId] = transform;
  }

  void _openNewOutfitPreview() {
    final previewItems = List.generate(_selectedProducts.length, (index) {
      final product = _selectedProducts[index];
      final transform =
          _itemTransforms[product.id] ?? _defaultItemTransform(index);
      return NewOutfitPreviewItem(
        id: product.id,
        name: product.title,
        price: product.price,
        image: product.outfitDisplayImage,
        offsetX: transform.offsetX,
        offsetY: transform.offsetY,
        widthFactor: _canvasItemWidthFactor,
        heightFactor: _canvasItemHeightFactor,
        scale: transform.scale,
        rotation: transform.rotation,
      );
    });

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NewOutfitScreen(
          backgroundColor: _canvasColor,
          items: previewItems,
          authorName: widget.authorName,
          authorHandle: widget.authorHandle,
          authorAvatarUrl: widget.authorAvatarUrl,
          onPublish: (outfit) async {
            final publish = widget.onPublish;
            if (publish != null) {
              await publish(outfit);
              if (context.mounted) Navigator.of(context).maybePop();
              return;
            }
            if (context.mounted) Navigator.of(context).maybePop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const horizontalPadding = 6.0;
                  const topPadding = 8.0;
                  const controlsHeight = 32.0;
                  const gapBelowControls = 26.0;
                  const bottomPadding = 4.0;
                  final maxWidth = math.max(
                    0.0,
                    constraints.maxWidth - horizontalPadding * 2,
                  );
                  final maxHeight = math.max(
                    0.0,
                    constraints.maxHeight -
                        topPadding -
                        controlsHeight -
                        gapBelowControls -
                        bottomPadding,
                  );
                  final naturalHeight = maxWidth / _outfitMediaAspectRatio;
                  final mediaHeight = math.min(naturalHeight, maxHeight);
                  final fittedWidth = mediaHeight * _outfitMediaAspectRatio;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topPadding,
                      horizontalPadding,
                      0,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _close,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5E5E5E),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chevron_left,
                                  size: 23,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _openNewOutfitPreview,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 86),
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Далее',
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1,
                                      letterSpacing: 0,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: gapBelowControls),
                        Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: fittedWidth,
                            height: mediaHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _canvasColor,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _EditorCanvasItems(
                                  products: _selectedProducts,
                                  transforms: _itemTransforms,
                                  defaultTransform: _defaultItemTransform,
                                  onTransformChanged: _rememberItemTransform,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 21),
              child: Row(
                children: [
                  Expanded(
                    child: _EditorActionButton(
                      icon: Icons.checkroom_outlined,
                      label: 'Добавить одежду',
                      onTap: _showClothesSheet,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _EditorActionButton(
                      icon: Icons.diamond_outlined,
                      label: 'Аксессуары',
                      onTap: _showAccessoriesSheet,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _EditorActionButton(
                      icon: Icons.color_lens_outlined,
                      label: 'Сменить фон',
                      onTap: _showBackgroundSheet,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

class _CanvasItemTransform {
  const _CanvasItemTransform({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.rotation,
  });

  final double offsetX;
  final double offsetY;
  final double scale;
  final double rotation;
}

class _EditorCanvasItems extends StatelessWidget {
  const _EditorCanvasItems({
    required this.products,
    required this.transforms,
    required this.defaultTransform,
    required this.onTransformChanged,
  });

  final List<Product> products;
  final Map<String, _CanvasItemTransform> transforms;
  final _CanvasItemTransform Function(int index) defaultTransform;
  final void Function(String productId, _CanvasItemTransform transform)
  onTransformChanged;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.expand();

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final itemWidth =
            constraints.maxWidth *
            _OutfitCreateScreenState._canvasItemWidthFactor;
        final itemHeight =
            constraints.maxHeight *
            _OutfitCreateScreenState._canvasItemHeightFactor;
        return Stack(
          children: List.generate(products.length, (index) {
            final product = products[index];
            final transform = transforms[product.id] ?? defaultTransform(index);
            return Positioned.fill(
              child: _TransformableCanvasItem(
                key: ValueKey(product.id),
                product: product,
                width: itemWidth,
                height: itemHeight,
                canvasSize: canvasSize,
                initialTransform: transform,
                onTransformChanged: (nextTransform) =>
                    onTransformChanged(product.id, nextTransform),
              ),
            );
          }),
        );
      },
    );
  }
}

class _TransformableCanvasItem extends StatefulWidget {
  const _TransformableCanvasItem({
    super.key,
    required this.product,
    required this.width,
    required this.height,
    required this.canvasSize,
    required this.initialTransform,
    required this.onTransformChanged,
  });

  final Product product;
  final double width;
  final double height;
  final Size canvasSize;
  final _CanvasItemTransform initialTransform;
  final ValueChanged<_CanvasItemTransform> onTransformChanged;

  @override
  State<_TransformableCanvasItem> createState() =>
      _TransformableCanvasItemState();
}

class _TransformableCanvasItemState extends State<_TransformableCanvasItem> {
  late Offset _offset;
  double _scale = 1;
  double _rotation = 0;

  late double _startScale;
  late double _startRotation;

  @override
  void initState() {
    super.initState();
    _offset = _offsetFromTransform(widget.initialTransform, widget.canvasSize);
    _scale = widget.initialTransform.scale;
    _rotation = widget.initialTransform.rotation;
  }

  @override
  void didUpdateWidget(covariant _TransformableCanvasItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.canvasSize != widget.canvasSize) {
      _offset = _offsetFromTransform(
        widget.initialTransform,
        widget.canvasSize,
      );
      _scale = widget.initialTransform.scale;
      _rotation = widget.initialTransform.rotation;
    }
  }

  Offset _offsetFromTransform(_CanvasItemTransform transform, Size canvasSize) {
    return Offset(
      transform.offsetX * canvasSize.width,
      transform.offsetY * canvasSize.height,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startRotation = _rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _offset += details.focalPointDelta;
      _scale = (_startScale * details.scale).clamp(0.35, 3.2);
      _rotation = _startRotation + details.rotation;
    });
    widget.onTransformChanged(
      _CanvasItemTransform(
        offsetX: widget.canvasSize.width == 0
            ? 0
            : _offset.dx / widget.canvasSize.width,
        offsetY: widget.canvasSize.height == 0
            ? 0
            : _offset.dy / widget.canvasSize.height,
        scale: _scale,
        rotation: _rotation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: _offset,
        child: Transform.rotate(
          angle: _rotation,
          child: Transform.scale(
            scale: _scale,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: AppImage(
                  imageUrl: widget.product.outfitDisplayImage,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  placeholderColor: Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessoryTitleScreen extends StatefulWidget {
  const _AccessoryTitleScreen({
    required this.imagePath,
    required this.isDefault,
  });

  final String imagePath;
  final bool isDefault;

  @override
  State<_AccessoryTitleScreen> createState() => _AccessoryTitleScreenState();
}

class _AccessoryTitleScreenState extends State<_AccessoryTitleScreen> {
  final TextEditingController _titleController = TextEditingController();

  bool get _canSave => _titleController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(_titleController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.chevron_left),
                    iconSize: 28,
                    color: Colors.black,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.isDefault
                          ? 'аксессуар по умолчанию'
                          : 'мой аксессуар',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            const SizedBox(
              width: double.infinity,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8F9),
                          border: Border.all(color: const Color(0xFFE7E7EA)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: AppImage(
                            imageUrl: widget.imagePath,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            placeholderColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _titleController,
                      onChanged: (_) => setState(() {}),
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: 0,
                        color: Colors.black,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        hintText: 'Например: очки',
                        labelStyle: TextStyle(
                          fontFamily: 'Montserrat',
                          color: Color(0xFF6E6E6E),
                        ),
                        hintStyle: TextStyle(
                          fontFamily: 'Montserrat',
                          color: Color(0xFF8E8E8E),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              height: 82,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
              ),
              padding: const EdgeInsets.fromLTRB(10, 22, 10, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _canSave ? _save : null,
                child: Container(
                  height: 40,
                  color: _canSave ? Colors.black : const Color(0xFFC8C8CE),
                  alignment: Alignment.center,
                  child: Text(
                    'СОХРАНИТЬ АКСЕССУАР',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: _canSave ? Colors.white : const Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClothesPickerSheet extends StatefulWidget {
  const _ClothesPickerSheet({
    required this.myProducts,
    required this.likedProducts,
    required this.onProductTap,
    required this.onCreateTap,
    required this.isProductProcessing,
  });

  final List<Product> myProducts;
  final List<Product> likedProducts;
  final ValueChanged<Product> onProductTap;
  final VoidCallback onCreateTap;
  final bool Function(Product product) isProductProcessing;

  @override
  State<_ClothesPickerSheet> createState() => _ClothesPickerSheetState();
}

class _ClothesPickerSheetState extends State<_ClothesPickerSheet> {
  int _tabIndex = 0;

  List<Product> get _visibleProducts =>
      _tabIndex == 0 ? widget.myProducts : widget.likedProducts;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDADADD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SheetTab(
                label: 'Мои вещи',
                isActive: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              const SizedBox(width: 8),
              _SheetTab(
                label: 'Понравившиеся',
                isActive: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _visibleProducts.isEmpty && _tabIndex != 0
                ? const Center(
                    child: Text(
                      'Вещей пока нет',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF8E8E8E),
                      ),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount:
                        _visibleProducts.length + (_tabIndex == 0 ? 1 : 0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 118,
                        ),
                    itemBuilder: (context, index) {
                      if (_tabIndex == 0 && index == 0) {
                        return _CreateClothingTile(onTap: widget.onCreateTap);
                      }
                      final productIndex = index - (_tabIndex == 0 ? 1 : 0);
                      final product = _visibleProducts[productIndex];
                      final isProcessing = widget.isProductProcessing(product);
                      return _ClothingTile(
                        product: product,
                        isProcessing: isProcessing,
                        onTap: isProcessing
                            ? null
                            : () => widget.onProductTap(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateClothingTile extends StatelessWidget {
  const _CreateClothingTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE1E1E4)),
              ),
              child: const Center(
                child: Icon(Icons.add, size: 30, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Создать',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClothingTile extends StatelessWidget {
  const _ClothingTile({
    required this.product,
    required this.isProcessing,
    required this.onTap,
  });

  final Product product;
  final bool isProcessing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppImage(
                  imageUrl: product.outfitDisplayImage,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  placeholderColor: Colors.transparent,
                ),
                if (isProcessing)
                  Container(
                    color: Colors.white.withValues(alpha: 0.78),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            product.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 9,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessoriesPickerSheet extends StatefulWidget {
  const _AccessoriesPickerSheet({
    required this.defaultAccessories,
    required this.myAccessories,
    required this.onAccessoryTap,
    required this.onCreateTap,
  });

  final List<OutfitAccessory> defaultAccessories;
  final List<OutfitAccessory> myAccessories;
  final ValueChanged<OutfitAccessory> onAccessoryTap;
  final ValueChanged<bool> onCreateTap;

  @override
  State<_AccessoriesPickerSheet> createState() =>
      _AccessoriesPickerSheetState();
}

class _AccessoriesPickerSheetState extends State<_AccessoriesPickerSheet> {
  int _tabIndex = 0;

  List<OutfitAccessory> get _visibleAccessories =>
      _tabIndex == 0 ? widget.defaultAccessories : widget.myAccessories;

  bool get _canCreateAccessory => _tabIndex == 1;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDADADD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SheetTab(
                label: 'По умолчанию',
                isActive: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              const SizedBox(width: 8),
              _SheetTab(
                label: 'Мои',
                isActive: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount:
                  _visibleAccessories.length + (_canCreateAccessory ? 1 : 0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                mainAxisExtent: 118,
              ),
              itemBuilder: (context, index) {
                if (_canCreateAccessory && index == 0) {
                  return _CreateClothingTile(
                    onTap: () => widget.onCreateTap(false),
                  );
                }
                final accessory =
                    _visibleAccessories[index - (_canCreateAccessory ? 1 : 0)];
                return _AccessoryTile(
                  accessory: accessory,
                  onTap: accessory.isProcessing
                      ? null
                      : () => widget.onAccessoryTap(accessory),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessoryTile extends StatelessWidget {
  const _AccessoryTile({required this.accessory, required this.onTap});

  final OutfitAccessory accessory;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppImage(
                  imageUrl: accessory.displayImage,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  placeholderColor: Colors.transparent,
                ),
                if (accessory.isProcessing)
                  Container(
                    color: Colors.white.withValues(alpha: 0.78),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            accessory.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 9,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundPickerSheet extends StatefulWidget {
  const _BackgroundPickerSheet({
    required this.initialColor,
    required this.onColorTap,
  });

  final Color initialColor;
  final ValueChanged<Color> onColorTap;

  static const List<Color> _colors = [
    Color(0xFFFFFFFF),
    Color(0xFFF7F7F4),
    Color(0xFFECE8DF),
    Color(0xFFD9CEC1),
    Color(0xFFC9D6DE),
    Color(0xFFB8C8D8),
    Color(0xFFC9D8CC),
    Color(0xFFD9C5C0),
    Color(0xFFE6D1DA),
    Color(0xFFD9D3EA),
    Color(0xFFCDBAA6),
    Color(0xFFAEB9A4),
    Color(0xFFB8A08E),
    Color(0xFFA93C45),
    Color(0xFF6F5F90),
    Color(0xFF2E4057),
    Color(0xFF22312B),
    Color(0xFF151515),
  ];

  @override
  State<_BackgroundPickerSheet> createState() => _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState extends State<_BackgroundPickerSheet> {
  late Color _selectedColor;
  late HSLColor _selectedHsl;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _selectedHsl = HSLColor.fromColor(_selectedColor);
    _hexController = TextEditingController(text: _colorToHex(_selectedColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _selectColor(Color color, {bool updateHex = true}) {
    setState(() {
      _selectedColor = color;
      _selectedHsl = HSLColor.fromColor(color);
      if (updateHex) {
        _hexController.text = _colorToHex(color);
      }
    });
    widget.onColorTap(color);
  }

  void _updateHsl({double? hue, double? saturation, double? lightness}) {
    final nextHsl = _selectedHsl
        .withHue(hue ?? _selectedHsl.hue)
        .withSaturation(saturation ?? _selectedHsl.saturation)
        .withLightness(lightness ?? _selectedHsl.lightness);
    final nextColor = nextHsl.toColor();
    setState(() {
      _selectedHsl = nextHsl;
      _selectedColor = nextColor;
      _hexController.text = _colorToHex(nextColor);
    });
    widget.onColorTap(nextColor);
  }

  void _applyHex(String value) {
    final parsed = _colorFromHex(value);
    if (parsed == null) return;
    _selectColor(parsed, updateHex: false);
  }

  void _reset() {
    _selectColor(Colors.white);
  }

  void _done() {
    // Every selection is already applied to the parent editor and is copied
    // into CreatedOutfit.previewBackgroundColor during publication.
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final sheetHeight = math.min(
      518.0 + bottomInset,
      MediaQuery.sizeOf(context).height * 0.80,
    );

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF6E6E6E),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD7D7DA)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u0424\u043e\u043d \u043e\u0431\u0440\u0430\u0437\u0430',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: 0,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _colorToHex(_selectedColor),
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          letterSpacing: 0,
                          color: Color(0xFF77777D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _BackgroundSheetDivider(),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              itemCount: _BackgroundPickerSheet._colors.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final color = _BackgroundPickerSheet._colors[index];
                return _BackgroundSwatch(
                  color: color,
                  isSelected: _isSameColor(_selectedColor, color),
                  onTap: () => _selectColor(color),
                );
              },
            ),
          ),
          const _BackgroundSheetDivider(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                children: [
                  _ColorSlider(
                    label: 'H',
                    value: _selectedHsl.hue,
                    min: 0,
                    max: 360,
                    gradient: const [
                      Color(0xFFFF3B30),
                      Color(0xFFFFCC00),
                      Color(0xFF34C759),
                      Color(0xFF00C7BE),
                      Color(0xFF007AFF),
                      Color(0xFFAF52DE),
                      Color(0xFFFF3B30),
                    ],
                    thumbColor: _selectedColor,
                    onChanged: (value) => _updateHsl(hue: value),
                  ),
                  const SizedBox(height: 14),
                  _ColorSlider(
                    label: 'S',
                    value: _selectedHsl.saturation,
                    min: 0,
                    max: 1,
                    gradient: [
                      _selectedHsl.withSaturation(0).toColor(),
                      _selectedHsl.withSaturation(1).toColor(),
                    ],
                    thumbColor: _selectedColor,
                    onChanged: (value) => _updateHsl(saturation: value),
                  ),
                  const SizedBox(height: 14),
                  _ColorSlider(
                    label: 'L',
                    value: _selectedHsl.lightness,
                    min: 0,
                    max: 1,
                    gradient: [
                      Colors.black,
                      _selectedHsl.withLightness(0.5).toColor(),
                      Colors.white,
                    ],
                    thumbColor: _selectedColor,
                    onChanged: (value) => _updateHsl(lightness: value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _hexController,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: _applyHex,
                    onSubmitted: _applyHex,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                    decoration: InputDecoration(
                      labelText: 'HEX',
                      labelStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        color: Color(0xFF77777D),
                      ),
                      prefixText: '#',
                      prefixStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE1E1E4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.black,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _BackgroundSheetDivider(),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottomInset),
            child: Row(
              children: [
                _BackgroundSheetButton(
                  label: '\u0421\u0431\u0440\u043e\u0441\u0438\u0442\u044c',
                  backgroundColor: const Color(0xFFD0D0D0),
                  foregroundColor: Colors.black,
                  horizontalPadding: 22,
                  fontWeight: FontWeight.w600,
                  onTap: _reset,
                ),
                const Spacer(),
                _BackgroundSheetButton(
                  label: '\u0413\u043e\u0442\u043e\u0432\u043e',
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  horizontalPadding: 28,
                  fontWeight: FontWeight.w700,
                  onTap: _done,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _isSameColor(Color a, Color b) {
  return a.toARGB32() == b.toARGB32();
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
}

Color? _colorFromHex(String value) {
  final cleaned = value.replaceAll('#', '').trim();
  if (cleaned.length != 6) return null;
  final rgb = int.tryParse(cleaned, radix: 16);
  if (rgb == null) return null;
  return Color(0xFF000000 | rgb);
}

class _BackgroundSheetDivider extends StatelessWidget {
  const _BackgroundSheetDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 1,
      child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFD8D8D8))),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.gradient,
    required this.thumbColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final List<Color> gradient;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: Colors.black,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE1E1E4)),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 14,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    overlayColor: Colors.black.withValues(alpha: 0.06),
                    thumbColor: thumbColor,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 17,
                    ),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackgroundSheetButton extends StatelessWidget {
  const _BackgroundSheetButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.horizontalPadding,
    required this.fontWeight,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final double horizontalPadding;
  final FontWeight fontWeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 16,
              fontWeight: fontWeight,
              height: 1,
              letterSpacing: 0,
              color: foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 54,
        height: 80,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFFF0A020), width: 2)
              : null,
        ),
      ),
    );
  }
}

class _SheetTab extends StatelessWidget {
  const _SheetTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: isActive ? Colors.black : const Color(0xFFF1F1F1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                letterSpacing: 0,
                color: isActive ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorActionButton extends StatelessWidget {
  const _EditorActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF4A4A4A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: Colors.white),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1,
                letterSpacing: 0,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
