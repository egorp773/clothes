import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/product.dart';
import 'visual_search_object_selection_screen.dart';
import 'visual_search_screen.dart';
import 'visual_search_service.dart';

class VisualSearchCameraScreen extends StatefulWidget {
  const VisualSearchCameraScreen({
    super.key,
    required this.onProductTap,
    required this.onToggleLike,
    this.catalogProducts = const [],
    this.onProductMenu,
    this.onShareProduct,
    this.service,
    this.initializeHardware = true,
    this.cameraPreviewOverride,
  });

  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId) onToggleLike;
  final List<Product> catalogProducts;
  final ValueChanged<Product>? onProductMenu;
  final ValueChanged<Product>? onShareProduct;
  final VisualSearchService? service;
  final bool initializeHardware;
  final Widget? cameraPreviewOverride;

  @override
  State<VisualSearchCameraScreen> createState() =>
      _VisualSearchCameraScreenState();
}

class _VisualSearchCameraScreenState extends State<VisualSearchCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _collapsedPanelHeight = 202.0;
  static const _photoRequest = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  late final VisualSearchService _service;
  late final AnimationController _focusAnimation;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  List<AssetEntity> _assets = const [];
  PermissionState? _photoPermission;
  FlashMode _flashMode = FlashMode.off;
  bool _cameraInitializing = true;
  bool _cameraPermissionDenied = false;
  bool _galleryLoading = true;
  bool _panelExpanded = false;
  bool _capturing = false;
  bool _detectingObjects = false;
  bool _searching = false;
  int _cameraGeneration = 0;
  int _searchGeneration = 0;
  String? _cameraError;
  Uint8List? _searchPreview;

  bool get _busy => _capturing || _detectingObjects || _searching;

  List<AssetEntity> get _visibleAssets {
    final threshold = DateTime.now().subtract(const Duration(days: 30));
    final recent = _assets
        .where((asset) => asset.createDateTime.isAfter(threshold))
        .toList(growable: false);
    return recent.isEmpty ? _assets : recent;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.service ?? VisualSearchService();
    _focusAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    if (widget.initializeHardware) {
      _initializeHardware();
    } else {
      _cameraInitializing = false;
      _galleryLoading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
      return;
    }
    if (state == AppLifecycleState.resumed &&
        widget.initializeHardware &&
        !_busy) {
      _resumeHardware();
    }
  }

  Future<void> _initializeHardware() async {
    await _initializeCamera();
    if (mounted) await _loadGallery();
  }

  Future<void> _resumeHardware() async {
    await _initializeCamera(preferred: _selectedCamera);
    if (mounted && _photoPermission?.hasAccess != true) await _loadGallery();
  }

  Future<void> _initializeCamera({CameraDescription? preferred}) async {
    final generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _cameraInitializing = true;
        _cameraError = null;
      });
    }
    try {
      final cameras = _cameras.isEmpty ? await availableCameras() : _cameras;
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'Камера не найдена');
      }
      _cameras = cameras;
      final selected =
          preferred ??
          cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
      await _startCamera(selected, generation: generation);
    } on CameraException catch (error) {
      if (!mounted || generation != _cameraGeneration) return;
      final denied = const {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      }.contains(error.code);
      setState(() {
        _cameraInitializing = false;
        _cameraPermissionDenied = denied;
        _cameraError = denied
            ? 'Нет доступа к камере'
            : 'Не удалось запустить камеру';
      });
    } catch (_) {
      if (!mounted || generation != _cameraGeneration) return;
      setState(() {
        _cameraInitializing = false;
        _cameraError = 'Не удалось запустить камеру';
      });
    }
  }

  Future<void> _startCamera(
    CameraDescription description, {
    int? generation,
  }) async {
    final currentGeneration = generation ?? ++_cameraGeneration;
    final oldController = _cameraController;
    _cameraController = null;
    await oldController?.dispose();
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    if (!mounted || currentGeneration != _cameraGeneration) {
      await controller.dispose();
      return;
    }
    setState(() {
      _cameraController = controller;
      _selectedCamera = description;
      _flashMode = FlashMode.off;
      _cameraInitializing = false;
      _cameraPermissionDenied = false;
      _cameraError = null;
    });
  }

  Future<void> _loadGallery() async {
    if (mounted) setState(() => _galleryLoading = true);
    try {
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: _photoRequest,
      );
      if (!permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          _photoPermission = permission;
          _galleryLoading = false;
          _assets = const [];
        });
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
      );
      final assets = paths.isEmpty
          ? const <AssetEntity>[]
          : await paths.first.getAssetListPaged(page: 0, size: 240);
      if (!mounted) return;
      setState(() {
        _photoPermission = permission;
        _assets = assets;
        _galleryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _galleryLoading = false;
        _assets = const [];
      });
    }
  }

  Future<void> _disposeCamera() async {
    ++_cameraGeneration;
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusAnimation.dispose();
    ++_cameraGeneration;
    _cameraController?.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _switchCamera() async {
    if (_busy || _cameras.length < 2) return;
    final current = _selectedCamera;
    final next = _cameras.firstWhere(
      (camera) => camera.lensDirection != current?.lensDirection,
      orElse: () {
        final index = _cameras.indexOf(current!);
        return _cameras[(index + 1) % _cameras.length];
      },
    );
    setState(() => _cameraInitializing = true);
    try {
      await _startCamera(next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        _cameraError = 'Не удалось переключить камеру';
      });
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (_busy || controller == null || !controller.value.isInitialized) return;
    final next = _flashMode == FlashMode.torch
        ? FlashMode.off
        : FlashMode.torch;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вспышка недоступна на этой камере')),
      );
    }
  }

  Future<void> _capture() async {
    final controller = _cameraController;
    if (_busy || controller == null || !controller.value.isInitialized) return;
    setState(() => _capturing = true);
    try {
      final captured = await controller.takePicture();
      final image = await normalizeVisualSearchImage(captured);
      await _prepareSearch(image);
    } on CameraException {
      if (!mounted) return;
      _showError('Не удалось сделать фото');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _selectAsset(AssetEntity asset) async {
    if (_busy) return;
    setState(() => _capturing = true);
    try {
      final bytes = await asset.thumbnailDataWithSize(
        _searchThumbnailSize(asset),
        format: ThumbnailFormat.jpeg,
        quality: 88,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Photo data is unavailable');
      }
      final image = XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: 'gallery-${asset.id}.jpg',
      );
      await _prepareSearch(image, preview: bytes);
    } catch (_) {
      if (!mounted) return;
      _showError('Не удалось открыть фотографию');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _prepareSearch(XFile image, {Uint8List? preview}) async {
    if (_detectingObjects || _searching) return;
    final operationGeneration = ++_searchGeneration;
    final previewBytes = preview ?? await image.readAsBytes();
    if (!mounted || operationGeneration != _searchGeneration) return;
    _focusAnimation
      ..duration = const Duration(milliseconds: 6000)
      ..repeat();
    setState(() {
      _detectingObjects = true;
      _searchPreview = previewBytes;
    });
    try {
      await _cameraController?.pausePreview();
    } catch (_) {}

    Size imageSize;
    try {
      imageSize = await visualSearchImageSize(previewBytes);
    } catch (_) {
      imageSize = const Size(1, 1);
    }
    if (!mounted || operationGeneration != _searchGeneration) return;

    final choice = await Navigator.of(context, rootNavigator: true)
        .push<VisualSearchObjectSelectionResult>(
          MaterialPageRoute<VisualSearchObjectSelectionResult>(
            builder: (context) => VisualSearchObjectSelectionScreen(
              previewBytes: previewBytes,
              imageSize: imageSize,
            ),
          ),
        );
    if (!mounted || operationGeneration != _searchGeneration) return;
    if (choice == null) {
      await _finishDetection(operationGeneration);
      return;
    }

    var searchImage = image;
    var searchPreviewBytes = previewBytes;
    try {
      searchImage = await cropVisualSearchImage(
        image,
        choice.cropBounds,
        imageBytes: previewBytes,
      );
      searchPreviewBytes = await searchImage.readAsBytes();
    } catch (_) {
      if (!mounted || operationGeneration != _searchGeneration) return;
      _showError('Не удалось выделить выбранную вещь');
      await _finishDetection(operationGeneration);
      return;
    }
    if (!mounted || operationGeneration != _searchGeneration) return;
    setState(() => _detectingObjects = false);
    await _runSearch(searchImage, preview: searchPreviewBytes);
  }

  Future<void> _finishDetection(int generation) async {
    if (!mounted || generation != _searchGeneration) return;
    _focusAnimation
      ..duration = const Duration(milliseconds: 3600)
      ..repeat();
    setState(() {
      _detectingObjects = false;
      _searchPreview = null;
      _panelExpanded = false;
    });
    await _resumeCameraPreview();
  }

  Future<void> _runSearch(XFile image, {Uint8List? preview}) async {
    if (_searching) return;
    final searchGeneration = ++_searchGeneration;
    final previewBytes = preview ?? await image.readAsBytes();
    if (!mounted) return;
    _focusAnimation
      ..duration = const Duration(milliseconds: 6000)
      ..repeat();
    setState(() {
      _searching = true;
      _searchPreview = previewBytes;
    });
    try {
      await _cameraController?.pausePreview();
    } catch (_) {}
    try {
      final result = await _service.search(image, imageBytes: previewBytes);
      if (!mounted || searchGeneration != _searchGeneration) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VisualSearchScreen(
            initialImage: image,
            initialResult: result,
            initialPreviewBytes: previewBytes,
            service: _service,
            catalogProducts: widget.catalogProducts,
            onProductTap: widget.onProductTap,
            onToggleLike: widget.onToggleLike,
            onProductMenu: widget.onProductMenu,
            onShareProduct: widget.onShareProduct,
          ),
        ),
      );
    } on VisualSearchException catch (error) {
      if (mounted && searchGeneration == _searchGeneration) {
        _showError(error.message);
      }
    } catch (_) {
      if (mounted && searchGeneration == _searchGeneration) {
        _showError('Поиск по фото временно недоступен');
      }
    } finally {
      if (mounted && searchGeneration == _searchGeneration) {
        _focusAnimation.duration = const Duration(milliseconds: 3600);
        if (_panelExpanded) {
          _focusAnimation.stop();
        } else {
          _focusAnimation.repeat();
        }
        setState(() {
          _searching = false;
          _searchPreview = null;
        });
        await _resumeCameraPreview();
      }
    }
  }

  void _cancelSearch() {
    if (!_searching && !_detectingObjects) return;
    ++_searchGeneration;
    _service.cancelActiveSearch();
    _focusAnimation
      ..duration = const Duration(milliseconds: 3600)
      ..repeat();
    setState(() {
      _searching = false;
      _detectingObjects = false;
      _searchPreview = null;
      _capturing = false;
      _panelExpanded = false;
    });
    _resumeCameraPreview();
  }

  Future<void> _resumeCameraPreview() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      if (widget.initializeHardware && mounted) {
        await _initializeCamera(preferred: _selectedCamera);
      }
      return;
    }
    try {
      await controller.resumePreview();
    } catch (_) {}
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xE61B1B1D),
        ),
      );
  }

  void _setPanelExpanded(bool expanded) {
    if (_busy) return;
    if (expanded) {
      _focusAnimation.stop();
    } else if (!_focusAnimation.isAnimating) {
      _focusAnimation.repeat();
    }
    setState(() => _panelExpanded = expanded);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final expandedHeight = media.size.height - media.padding.top - 72;
    final collapsedHeight = _collapsedPanelHeight + media.padding.bottom;
    final panelHeight = _panelExpanded ? expandedHeight : collapsedHeight;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraLayer(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Colors.transparent,
                  Color(0x4D000000),
                ],
                stops: [0, 0.42, 1],
              ),
            ),
          ),
          if (!_panelExpanded) _buildFocusWave(),
          _buildTopControls(),
          _buildSearchIntro(),
          _buildSideControls(),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: panelHeight + 18,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _panelExpanded ? 0 : 1,
              child: IgnorePointer(
                ignoring: _panelExpanded,
                child: _buildCaptureArea(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildGalleryPanel(panelHeight),
          ),
          if ((_detectingObjects || _searching) && _searchPreview != null)
            _buildSearchingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCameraLayer() {
    if (widget.cameraPreviewOverride case final Widget preview) return preview;
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      final screen = MediaQuery.sizeOf(context);
      var scale = 1 / (controller.value.aspectRatio * screen.aspectRatio);
      if (scale < 1) scale = 1 / scale;
      return ClipRect(
        child: Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(controller)),
        ),
      );
    }
    if (_cameraError != null) {
      return ColoredBox(
        color: const Color(0xFF111113),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  size: 42,
                  color: Colors.white70,
                ),
                const SizedBox(height: 14),
                Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cameraPermissionDenied
                      ? PhotoManager.openSetting
                      : _initializeCamera,
                  child: Text(
                    _cameraPermissionDenied ? 'Открыть настройки' : 'Повторить',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const ColoredBox(
      color: Color(0xFF111113),
      child: Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
    );
  }

  Widget _buildTopControls() => Positioned(
    left: 14,
    top: 10,
    child: SafeArea(
      child: _RoundControl(
        tooltip: 'Назад',
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: _busy ? null : () => Navigator.maybePop(context),
      ),
    ),
  );

  Widget _buildSearchIntro() => Positioned(
    top: MediaQuery.paddingOf(context).top + 14,
    left: 76,
    right: 76,
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Найдём похожие товары',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
          ),
        ),
        SizedBox(height: 3),
        Text(
          'Сфотографируйте вещь, которую хотите найти',
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.25,
            shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
          ),
        ),
      ],
    ),
  );

  Widget _buildSideControls() => Positioned(
    right: 14,
    top: MediaQuery.paddingOf(context).top + 12,
    child: Column(
      children: [
        _RoundControl(
          tooltip: 'Переключить камеру',
          icon: Icons.cameraswitch_rounded,
          onTap: _busy || _cameraInitializing || _cameras.length < 2
              ? null
              : _switchCamera,
        ),
        const SizedBox(height: 12),
        _RoundControl(
          tooltip: 'Вспышка',
          icon: _flashMode == FlashMode.torch
              ? Icons.flash_on_rounded
              : Icons.flash_off_rounded,
          active: _flashMode == FlashMode.torch,
          onTap: _busy || _cameraInitializing ? null : _toggleFlash,
        ),
      ],
    ),
  );

  Widget _buildFocusWave() => Center(
    child: Padding(
      padding: const EdgeInsets.only(bottom: 86),
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: AspectRatio(
          aspectRatio: 0.82,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CenterWavePainter(animation: _focusAnimation),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildCaptureArea() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: 'Сделать фото',
        child: GestureDetector(
          onTap: _busy || _cameraController?.value.isInitialized != true
              ? null
              : _capture,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              color: Colors.black12,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _busy ? Colors.white54 : Colors.white,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildGalleryPanel(double height) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity < -180) _setPanelExpanded(true);
      if (velocity > 180) _setPanelExpanded(false);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6171719),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
                child: Row(
                  children: [
                    const Text(
                      'Недавние',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _setPanelExpanded(!_panelExpanded),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: AnimatedRotation(
                        duration: const Duration(milliseconds: 250),
                        turns: _panelExpanded ? 0.5 : 0,
                        child: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      label: Text(_panelExpanded ? 'Свернуть' : 'Развернуть'),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildGalleryContent()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildGalleryContent() {
    if (_galleryLoading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      );
    }
    if (_photoPermission?.hasAccess != true) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Нет доступа к фото',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text(
                'Настройки',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
    final assets = _visibleAssets;
    if (assets.isEmpty) {
      return const Center(
        child: Text('Нет фотографий', style: TextStyle(color: Colors.white54)),
      );
    }
    if (!_panelExpanded) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        scrollDirection: Axis.horizontal,
        itemCount: assets.length.clamp(0, 20),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) => SizedBox(
          width: 78,
          child: _AssetThumbnail(
            asset: assets[index],
            onTap: _busy ? null : () => _selectAsset(assets[index]),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        4,
        0,
        4,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) => _AssetThumbnail(
        asset: assets[index],
        onTap: _busy ? null : () => _selectAsset(assets[index]),
      ),
    );
  }

  Widget _buildSearchingOverlay() => Positioned.fill(
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_searchPreview!, fit: BoxFit.cover),
          const ColoredBox(color: Color(0x42000000)),
          CustomPaint(
            painter: _CenterWavePainter(
              animation: _focusAnimation,
              dense: true,
            ),
          ),
          Center(
            child: Text(
              _detectingObjects
                  ? 'Определяем вещи на фото…'
                  : 'Ищем похожие вещи…',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 26,
            child: Center(
              child: Semantics(
                button: true,
                label: 'Остановить поиск',
                child: _RoundControl(
                  tooltip: 'Остановить поиск',
                  icon: Icons.close_rounded,
                  onTap: _cancelSearch,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

ThumbnailSize _searchThumbnailSize(AssetEntity asset) {
  const maxSide = 1024;
  final width = asset.width;
  final height = asset.height;
  if (width <= 0 || height <= 0) return const ThumbnailSize.square(maxSide);
  final longestSide = math.max(width, height);
  return ThumbnailSize(
    math.max(1, (width * maxSide / longestSide).round()).toInt(),
    math.max(1, (height * maxSide / longestSide).round()).toInt(),
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: active
          ? Colors.white
          : Colors.black.withValues(alpha: onTap == null ? 0.24 : 0.42),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            size: 22,
            color: active ? Colors.black : Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _AssetThumbnail extends StatefulWidget {
  const _AssetThumbnail({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback? onTap;

  @override
  State<_AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<_AssetThumbnail> {
  late Future<Uint8List?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = _load();
  }

  @override
  void didUpdateWidget(covariant _AssetThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _thumbnail = _load();
  }

  Future<Uint8List?> _load() => widget.asset.thumbnailDataWithSize(
    const ThumbnailSize.square(320),
    format: ThumbnailFormat.jpeg,
    quality: 82,
  );

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: ColoredBox(
        color: const Color(0xFF2D2D30),
        child: FutureBuilder<Uint8List?>(
          future: _thumbnail,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) return const SizedBox.expand();
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            );
          },
        ),
      ),
    ),
  );
}

class _CenterWavePainter extends CustomPainter {
  _CenterWavePainter({required this.animation, this.dense = false})
    : super(repaint: animation);

  final Animation<double> animation;
  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    if (dense) {
      const cycleSeconds = 6.0;
      const waveDurationSeconds = 2.3;
      final elapsedSeconds = animation.value * cycleSeconds;
      for (final startSeconds in const [0.0, 2.0, 4.0]) {
        final ageSeconds =
            (elapsedSeconds - startSeconds + cycleSeconds) % cycleSeconds;
        if (ageSeconds < waveDurationSeconds) {
          _drawAnalysisWave(canvas, size, ageSeconds / waveDurationSeconds);
        }
      }
      return;
    }
    _drawWave(canvas, size, animation.value);
  }

  void _drawWave(Canvas canvas, Size size, double cycle) {
    const activePart = 0.68;
    if (cycle >= activePart) return;

    final linearProgress = cycle / activePart;
    final progress = Curves.easeOutCubic.transform(linearProgress);
    final opacity = math.sin(linearProgress * math.pi).clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height * 0.48);
    final maxRadius = math.sqrt(
      math.pow(size.width / 2, 2) + math.pow(size.height / 2, 2),
    );
    final radius = 12 + (maxRadius - 12) * progress;

    final wideGlow = Paint()
      ..color = const Color(0xFFBDEEFF).withValues(alpha: 0.12 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20 - 8 * progress
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final softGlow = Paint()
      ..color = Colors.white.withValues(alpha: 0.24 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final waveLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.58 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas
      ..drawCircle(center, radius, wideGlow)
      ..drawCircle(center, radius, softGlow)
      ..drawCircle(center, radius, waveLine);

    final centerGlow = Paint()
      ..color = const Color(
        0xFFDDF7FF,
      ).withValues(alpha: 0.1 * opacity * (1 - linearProgress))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, 18 + 12 * progress, centerGlow);
  }

  void _drawAnalysisWave(Canvas canvas, Size size, double linearProgress) {
    final progress = Curves.easeOutCubic.transform(linearProgress);
    final opacity = math.pow(1 - linearProgress, 1.35).toDouble();
    final center = Offset(size.width / 2, size.height * 0.48);
    final maxRadius = math.sqrt(
      math.pow(size.width / 2, 2) + math.pow(size.height / 2, 2),
    );
    final radius = 10 + (maxRadius - 10) * progress;
    final circleRect = Rect.fromCircle(center: center, radius: radius);
    final waveFill = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF9AE9FF).withValues(alpha: 0.13 * opacity),
          const Color(0xFFBDEEFF).withValues(alpha: 0.15 * opacity),
          Colors.white.withValues(alpha: 0.2 * opacity),
          Colors.transparent,
        ],
        stops: const [0, 0.58, 0.9, 1],
      ).createShader(circleRect);
    canvas.drawCircle(center, radius, waveFill);
  }

  @override
  bool shouldRepaint(covariant _CenterWavePainter oldDelegate) => false;
}
