import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_appearance.dart';
import '../../../models/product.dart';
import '../data/listing_publish_repository.dart';
import '../listing_publish_controller.dart';
import '../models/listing_draft.dart';
import '../services/remote_product_image_analyzer.dart';
import '../widgets/listing_publish_widgets.dart';
import 'listing_attributes_step.dart';
import 'listing_basics_step.dart';
import 'listing_delivery_step.dart';
import 'listing_photos_step.dart';
import 'listing_preview_step.dart';

class ListingPublishFlowScreen extends StatefulWidget {
  const ListingPublishFlowScreen({
    super.key,
    required this.sidePadding,
    required this.sellerName,
    required this.sellerHandle,
    required this.initialCity,
    required this.onClose,
    required this.onPublished,
    this.scale = 1,
    this.onTabChange,
    this.onPublish,
    this.onUploadImage,
    this.publishButtonText = '',
    this.successMessage = '',
    this.failureMessage = '',
    this.controller,
  });

  final double sidePadding;
  final String sellerName;
  final String sellerHandle;
  final String initialCity;
  final VoidCallback onClose;
  final Future<void> Function(Product product) onPublished;
  final double scale;
  final Function(int)? onTabChange;
  final Future<bool> Function(Product product)? onPublish;
  final Object? onUploadImage;
  final String publishButtonText;
  final String successMessage;
  final String failureMessage;
  final ListingPublishController? controller;

  @override
  State<ListingPublishFlowScreen> createState() =>
      _ListingPublishFlowScreenState();
}

class _ListingPublishFlowScreenState extends State<ListingPublishFlowScreen>
    with WidgetsBindingObserver {
  late final ListingPublishController _controller;
  late final bool _ownsController;
  String? _shownError;
  bool _completionSent = false;
  Product? _publishedProduct;
  bool _isCompletingPublication = false;
  String? _completionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        ListingPublishController(
          repository: ListingPublishRepository(
            sellerName: widget.sellerName,
            sellerHandle: widget.sellerHandle,
            fallbackCity: widget.initialCity,
          ),
          analyzer: RemoteProductImageAnalyzer(),
          sellerName: widget.sellerName,
          sellerHandle: widget.sellerHandle,
        );
    _controller.addListener(_handleControllerChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    if (!mounted) return;
    if (_controller.hasRecoverableDraft) {
      await _showRecoveryDialog();
    }
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final error = _controller.transientError;
    if (error != null && error.isNotEmpty && error != _shownError) {
      _shownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
        );
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.retryPendingSync());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleControllerChanged);
    unawaited(_controller.flush());
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    if (!_controller.isInitialized) {
      return ColoredBox(
        color: context.appBackdrop.scaffoldColor,
        child: Center(child: CircularProgressIndicator(color: palette.ink)),
      );
    }
    final step = _controller.draft.currentStep;
    if (step == ListingPublishStep.success) return _buildSuccess();

    return ColoredBox(
      color: context.appBackdrop.scaffoldColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ListingStepHeader(
              title: _titleFor(step),
              currentStep: _controller.visibleStepNumber,
              totalSteps: 5,
              onBack: step == ListingPublishStep.photos ? null : _goBack,
              onClose: _close,
              padding: EdgeInsets.fromLTRB(
                widget.sidePadding,
                4,
                widget.sidePadding,
                step == ListingPublishStep.photos ? 0 : 12,
              ),
            ),
            Expanded(
              child: KeyedSubtree(key: ValueKey(step), child: _bodyFor(step)),
            ),
            ListingPrimaryBottomButton(
              label: step == ListingPublishStep.preview
                  ? 'Опубликовать'
                  : 'Продолжить',
              isLoading:
                  _controller.isPublishing || _controller.isWaitingForAnalysis,
              onPressed: _isPrimaryEnabled(step) ? _continue : null,
              padding: EdgeInsets.fromLTRB(
                widget.sidePadding,
                12,
                widget.sidePadding,
                14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyFor(ListingPublishStep step) => switch (step) {
    ListingPublishStep.photos => Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: ListingPhotosStep(controller: _controller),
      ),
    ),
    ListingPublishStep.basics => Align(
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: const Offset(0, -9),
        child: ListingBasicsStep(controller: _controller),
      ),
    ),
    ListingPublishStep.attributes => Transform.translate(
      offset: const Offset(0, -5),
      child: ListingAttributesStep(controller: _controller),
    ),
    ListingPublishStep.delivery => Transform.translate(
      offset: const Offset(0, -5),
      child: ListingDeliveryStep(controller: _controller),
    ),
    ListingPublishStep.preview => ListingPreviewStep(controller: _controller),
    ListingPublishStep.success => const SizedBox.shrink(),
  };

  bool _isPrimaryEnabled(ListingPublishStep step) => switch (step) {
    ListingPublishStep.photos => _controller.canContinueFromPhotos,
    ListingPublishStep.preview => !_controller.isPublishing,
    ListingPublishStep.success => false,
    _ => true,
  };

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    final draft = _controller.draft;
    switch (draft.currentStep) {
      case ListingPublishStep.photos:
        if (draft.photos.isEmpty) return;
        _controller.goToStep(ListingPublishStep.basics);
      case ListingPublishStep.basics:
        final error = draft.validateBasics();
        if (error != null) return _showValidation(error);
        _controller.confirmBasicDetails();
        _controller.goToStep(ListingPublishStep.attributes);
      case ListingPublishStep.attributes:
        final error = draft.validateAttributes();
        if (error != null) return _showValidation(error);
        _controller.confirmRequiredDetails();
        _controller.goToStep(ListingPublishStep.delivery);
      case ListingPublishStep.delivery:
        final error = draft.validateDelivery();
        if (error != null) return _showValidation(error);
        _controller.goToStep(ListingPublishStep.preview);
      case ListingPublishStep.preview:
        final error = draft.validateForPublish();
        if (error != null) return _showValidation(error);
        try {
          final product = await _controller.publish();
          if (!mounted) return;
          _publishedProduct = product;
          setState(() {});
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (mounted) await _completePublication();
        } on ListingPublishException catch (error) {
          if (mounted) _showValidation(error.userMessage);
        }
      case ListingPublishStep.success:
        return;
    }
  }

  Future<void> _completePublication() async {
    final product = _publishedProduct;
    if (product == null ||
        _completionSent ||
        _isCompletingPublication ||
        !mounted) {
      return;
    }
    setState(() {
      _isCompletingPublication = true;
      _completionError = null;
    });
    try {
      await widget.onPublished(product);
      if (!mounted) return;
      setState(() {
        _completionSent = true;
        _isCompletingPublication = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Published listing handoff error: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isCompletingPublication = false;
        _completionError =
            'Объявление уже опубликовано, но карточку не удалось открыть.';
      });
    }
  }

  void _goBack() {
    final previous = switch (_controller.draft.currentStep) {
      ListingPublishStep.basics => ListingPublishStep.photos,
      ListingPublishStep.attributes => ListingPublishStep.basics,
      ListingPublishStep.delivery => ListingPublishStep.attributes,
      ListingPublishStep.preview => ListingPublishStep.delivery,
      _ => ListingPublishStep.photos,
    };
    _controller.goToStep(previous);
  }

  void _close() {
    unawaited(_controller.flush());
    widget.onClose();
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showRecoveryDialog() async {
    final action = await showDialog<_RecoveryAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'У вас есть незавершённое объявление',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Продолжить с сохранённого места или начать новое?',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _RecoveryAction.delete),
            child: const Text('Удалить'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _RecoveryAction.createNew),
            child: const Text('Создать новое'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.appPalette.ink,
              foregroundColor: dialogContext.appPalette.surface,
              overlayColor: Colors.transparent,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, _RecoveryAction.resume),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _RecoveryAction.resume:
        await _controller.resumeDraft();
      case _RecoveryAction.createNew:
        await _controller.createNewDraft();
      case _RecoveryAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Удалить черновик?'),
            content: const Text(
              'Фотографии и заполненные данные будут удалены.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: dialogContext.appPalette.ink,
                  foregroundColor: dialogContext.appPalette.surface,
                  overlayColor: Colors.transparent,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _controller.deleteRecoverableDraft();
        } else {
          await _controller.resumeDraft();
        }
      case null:
        await _controller.resumeDraft();
    }
  }

  Widget _buildSuccess() => ColoredBox(
    color: context.appBackdrop.scaffoldColor,
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: context.appPalette.ink,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 40,
                  color: context.appPalette.surface,
                ),
              ),
              const SizedBox(height: 22),
              const SizedBox(
                width: double.infinity,
                child: Text(
                  'Объявление опубликовано',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Text(
                  _completionError ??
                      (_completionSent ? 'Готово' : 'Открываем карточку вещи'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appPalette.muted,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_completionError != null)
                FilledButton(
                  key: const Key('listing-completion-retry'),
                  onPressed: _isCompletingPublication
                      ? null
                      : _completePublication,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.appPalette.ink,
                    foregroundColor: context.appPalette.surface,
                    overlayColor: Colors.transparent,
                  ),
                  child: const Text('ОТКРЫТЬ КАРТОЧКУ'),
                )
              else if (!_completionSent)
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.appPalette.ink,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  String _titleFor(ListingPublishStep step) => switch (step) {
    ListingPublishStep.photos => 'Фотографии',
    ListingPublishStep.basics => 'Основная информация',
    ListingPublishStep.attributes => 'Всё о вещи',
    ListingPublishStep.delivery => 'Адрес и доставка',
    ListingPublishStep.preview => 'Предпросмотр',
    ListingPublishStep.success => 'Готово',
  };
}

enum _RecoveryAction { resume, createNew, delete }
