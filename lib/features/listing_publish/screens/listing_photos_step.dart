import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_appearance.dart';
import '../../../core/app_typography.dart';
import '../../../widgets/app_image.dart';
import '../listing_publish_controller.dart';
import '../models/listing_draft.dart';
import '../widgets/listing_publish_widgets.dart';

class ListingPhotosStep extends StatelessWidget {
  const ListingPhotosStep({super.key, required this.controller});

  final ListingPublishController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final palette = context.appPalette;
        if (!controller.isInitialized) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.ink,
              ),
            ),
          );
        }

        final photos = controller.draft.photos;
        final isAtLimit = photos.length >= 8;

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Добавьте фотографии вещи',
                  children: [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(
                        color: Color(0xFFE11D2E),
                        fontWeight: AppTypography.bold,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: AppTypography.semiBold,
                  color: palette.ink,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Первое фото станет главным. Лучше всего работают снимки при хорошем освещении.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: AppTypography.medium,
                  color: palette.muted,
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _PhotoSourceButton(
                      icon: Icons.photo_library_outlined,
                      title: 'Из галереи',
                      subtitle: 'Можно несколько',
                      isBusy: controller.isPickingPhotos,
                      onTap: isAtLimit || controller.isPickingPhotos
                          ? null
                          : () => unawaited(controller.pickFromGallery()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PhotoSourceButton(
                      icon: Icons.photo_camera_outlined,
                      title: 'Сделать фото',
                      subtitle: 'Открыть камеру',
                      isBusy: controller.isPickingPhotos,
                      onTap: isAtLimit || controller.isPickingPhotos
                          ? null
                          : () => unawaited(controller.takePhoto()),
                    ),
                  ),
                ],
              ),
              if (controller.transientError case final error?) ...[
                const SizedBox(height: 12),
                _InlineError(
                  message: error,
                  onDismiss: controller.clearTransientError,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      'Фотографии',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        fontWeight: AppTypography.semiBold,
                        color: palette.ink,
                        height: 1,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Text(
                    '${photos.length}/8',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11.5,
                      fontWeight: AppTypography.medium,
                      color: palette.muted,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (photos.isEmpty)
                const _EmptyPhotosHint()
              else ...[
                _PhotoReorderList(
                  photos: photos,
                  mainPhotoId: controller.draft.mainPhotoId,
                  onReorder: controller.reorderPhotos,
                  onSetMain: controller.setMainPhoto,
                  onPreview: (index) => _showPhotoPreview(
                    context,
                    photos: List<ListingPhoto>.of(photos),
                    initialIndex: index,
                  ),
                  onDelete: (photo) => unawaited(
                    _confirmPhotoDeletion(context, controller, photo),
                  ),
                  onRetry: (photo) =>
                      unawaited(controller.retryPhotoUpload(photo)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Зажмите фото и перетащите, чтобы изменить порядок. Нажмите звезду, чтобы выбрать главное.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10.5,
                    fontWeight: AppTypography.medium,
                    color: palette.muted,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 16),
                _AnalysisStatus(status: controller.draft.analysisStatus),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmPhotoDeletion(
    BuildContext context,
    ListingPublishController controller,
    ListingPhoto photo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (dialogContext) => Dialog(
        backgroundColor: dialogContext.appPalette.surfaceRaised,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Удалить фотографию?',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: AppTypography.semiBold,
                  color: dialogContext.appPalette.ink,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Она будет удалена из черновика объявления.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  fontWeight: AppTypography.medium,
                  color: dialogContext.appPalette.muted,
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: TextButton.styleFrom(
                        foregroundColor: dialogContext.appPalette.ink,
                        overlayColor: Colors.transparent,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text(
                        'Отмена',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: AppTypography.semiBold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: dialogContext.appPalette.ink,
                        foregroundColor: dialogContext.appPalette.surface,
                        overlayColor: Colors.transparent,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: const Text(
                        'Удалить',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: AppTypography.semiBold,
                        ),
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
    if (confirmed == true) await controller.removePhoto(photo);
  }

  void _showPhotoPreview(
    BuildContext context, {
    required List<ListingPhoto> photos,
    required int initialIndex,
  }) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullscreenPhotoPreview(
          photos: photos,
          initialIndex: initialIndex,
        );
      },
    );
  }
}

class _PhotoSourceButton extends StatelessWidget {
  const _PhotoSourceButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isBusy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final palette = context.appPalette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isBusy)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.ink,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 24,
                    color: enabled ? palette.ink : palette.muted,
                  ),
                const SizedBox(height: 9),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: AppTypography.semiBold,
                    color: enabled ? palette.ink : palette.muted,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10.5,
                    fontWeight: AppTypography.medium,
                    color: palette.muted,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: context.appPalette.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11.5,
                fontWeight: AppTypography.medium,
                color: context.appPalette.ink,
                height: 1.3,
                letterSpacing: 0,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Скрыть',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: context.appPalette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPhotosHint extends StatelessWidget {
  const _EmptyPhotosHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.appPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appPalette.border),
      ),
      child: Text(
        'Добавьте от 1 до 8 фотографий',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: AppTypography.medium,
          color: context.appPalette.muted,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _PhotoReorderList extends StatelessWidget {
  const _PhotoReorderList({
    required this.photos,
    required this.mainPhotoId,
    required this.onReorder,
    required this.onSetMain,
    required this.onPreview,
    required this.onDelete,
    required this.onRetry,
  });

  final List<ListingPhoto> photos;
  final String mainPhotoId;
  final ReorderCallback onReorder;
  final ValueChanged<String> onSetMain;
  final ValueChanged<int> onPreview;
  final ValueChanged<ListingPhoto> onDelete;
  final ValueChanged<ListingPhoto> onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 136,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.scale(
            scale: 1 + (0.04 * animation.value),
            child: Material(
              color: Colors.transparent,
              elevation: 5 * animation.value,
              borderRadius: BorderRadius.circular(10),
              child: child,
            ),
          ),
          child: child,
        ),
        itemCount: photos.length,
        onReorderItem: (oldIndex, newIndex) {
          // The controller keeps the legacy ReorderCallback contract and
          // performs the downward-index adjustment itself.
          onReorder(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex);
        },
        itemBuilder: (context, index) {
          final photo = photos[index];
          return Padding(
            key: ValueKey(photo.id),
            padding: EdgeInsets.only(
              right: index == photos.length - 1 ? 0 : 10,
            ),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: _PhotoCard(
                photo: photo,
                index: index,
                isMain: photo.id == mainPhotoId,
                onPreview: () => onPreview(index),
                onSetMain: () => onSetMain(photo.id),
                onDelete: () => onDelete(photo),
                onRetry: () => onRetry(photo),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.photo,
    required this.index,
    required this.isMain,
    required this.onPreview,
    required this.onSetMain,
    required this.onDelete,
    required this.onRetry,
  });

  final ListingPhoto photo;
  final int index;
  final bool isMain;
  final VoidCallback onPreview;
  final VoidCallback onSetMain;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPreview,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: context.appPalette.surfaceMuted,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isMain
                        ? context.appPalette.ink
                        : context.appPalette.border,
                    width: isMain ? 1.5 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppImage(imageUrl: photo.displaySource, fit: BoxFit.cover),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: _PhotoOverlayButton(
                        tooltip: isMain ? 'Главное фото' : 'Сделать главным',
                        onTap: onSetMain,
                        icon: isMain
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: _PhotoOverlayButton(
                        tooltip: 'Удалить фото',
                        onTap: onDelete,
                        icon: Icons.close_rounded,
                      ),
                    ),
                    Positioned(
                      left: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isMain ? 'Главное' : '${index + 1}',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 9.5,
                            fontWeight: AppTypography.semiBold,
                            color: Colors.white,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    if (photo.uploadStatus ==
                        ListingPhotoUploadStatus.uploading)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          color: Colors.black,
                          backgroundColor: Colors.white54,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _PhotoUploadStatus(status: photo.uploadStatus, onRetry: onRetry),
        ],
      ),
    );
  }
}

class _PhotoOverlayButton extends StatelessWidget {
  const _PhotoOverlayButton({
    required this.tooltip,
    required this.onTap,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      ),
    );
  }
}

class _PhotoUploadStatus extends StatelessWidget {
  const _PhotoUploadStatus({required this.status, required this.onRetry});

  final ListingPhotoUploadStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ListingPhotoUploadStatus.pending => const _StatusLabel(
        icon: Icons.schedule_rounded,
        label: 'В очереди',
      ),
      ListingPhotoUploadStatus.uploading => const _StatusLabel(
        icon: Icons.cloud_upload_outlined,
        label: 'Загрузка',
      ),
      ListingPhotoUploadStatus.uploaded => const _StatusLabel(
        icon: Icons.check_circle_outline_rounded,
        label: 'Загружено',
      ),
      ListingPhotoUploadStatus.failed => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: _StatusLabel(
          icon: Icons.refresh_rounded,
          label: 'Повторить',
          color: context.appPalette.ink,
        ),
      ),
    };
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.appPalette.muted;
    return Row(
      children: [
        Icon(icon, size: 12, color: effectiveColor),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 9.5,
              fontWeight: AppTypography.medium,
              color: effectiveColor,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisStatus extends StatelessWidget {
  const _AnalysisStatus({required this.status});

  final ListingAnalysisStatus status;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: switch (status) {
        ListingAnalysisStatus.pending => const ListingAnalysisStatusBadge(
          label: 'Готовим фотографии к анализу',
        ),
        ListingAnalysisStatus.processing =>
          const ListingAnalysisStatusBadge.processing(),
        ListingAnalysisStatus.completed =>
          const ListingAnalysisStatusBadge.completed(),
        ListingAnalysisStatus.failed => const ListingAnalysisStatusBadge(
          label: 'Характеристики можно заполнить вручную',
        ),
      },
    );
  }
}

class _FullscreenPhotoPreview extends StatefulWidget {
  const _FullscreenPhotoPreview({
    required this.photos,
    required this.initialIndex,
  });

  final List<ListingPhoto> photos;
  final int initialIndex;

  @override
  State<_FullscreenPhotoPreview> createState() =>
      _FullscreenPhotoPreviewState();
}

class _FullscreenPhotoPreviewState extends State<_FullscreenPhotoPreview> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (value) => setState(() => _currentIndex = value),
              itemBuilder: (context, index) => LayoutBuilder(
                builder: (context, constraints) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: AppImage(
                      imageUrl: widget.photos[index].displaySource,
                      fit: BoxFit.contain,
                      placeholderColor: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 8,
              child: IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                  overlayColor: Colors.transparent,
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              top: 18,
              left: 72,
              right: 72,
              child: Text(
                '${_currentIndex + 1} / ${widget.photos.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: AppTypography.semiBold,
                  color: Colors.white,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
