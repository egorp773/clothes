import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/app_appearance.dart';
import '../models/created_outfit.dart';
import '../widgets/app_image.dart';

class NewOutfitPreviewItem {
  const NewOutfitPreviewItem({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
    required this.offsetX,
    required this.offsetY,
    required this.widthFactor,
    required this.heightFactor,
    required this.scale,
    required this.rotation,
  });

  final String id;
  final String name;
  final String price;
  final String image;
  final double offsetX;
  final double offsetY;
  final double widthFactor;
  final double heightFactor;
  final double scale;
  final double rotation;
}

class NewOutfitScreen extends StatefulWidget {
  const NewOutfitScreen({
    super.key,
    required this.backgroundColor,
    required this.items,
    required this.authorName,
    required this.authorHandle,
    this.authorAvatarUrl = '',
    required this.onPublish,
  });

  final Color backgroundColor;
  final List<NewOutfitPreviewItem> items;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;
  final Future<void> Function(CreatedOutfit outfit) onPublish;

  @override
  State<NewOutfitScreen> createState() => _NewOutfitScreenState();
}

class _NewOutfitScreenState extends State<NewOutfitScreen> {
  static const Uuid _uuid = Uuid();

  bool _isPublishing = false;

  Future<void> _publish() async {
    if (_isPublishing) return;
    setState(() => _isPublishing = true);

    final outfit = CreatedOutfit(
      id: _uuid.v4(),
      photos: const [],
      items: widget.items
          .map(
            (item) => OutfitItem(
              id: item.id,
              name: item.name,
              price: item.price,
              image: item.image,
            ),
          )
          .toList(),
      authorName: widget.authorName,
      authorHandle: widget.authorHandle,
      authorAvatarUrl: widget.authorAvatarUrl,
      previewBackgroundColor: widget.backgroundColor.toARGB32(),
      layoutItems: widget.items
          .map(
            (item) => OutfitLayoutItem(
              image: item.image,
              offsetX: item.offsetX,
              offsetY: item.offsetY,
              widthFactor: item.widthFactor,
              heightFactor: item.heightFactor,
              scale: item.scale,
              rotation: item.rotation,
            ),
          )
          .toList(),
    );

    await widget.onPublish(outfit);
    if (mounted) setState(() => _isPublishing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const _NewOutfitHeader(),
            const _HeaderDivider(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 24),
                child: _ResponsiveOutfitCard(
                  backgroundColor: widget.backgroundColor,
                  items: widget.items,
                  authorName: widget.authorName,
                  authorHandle: widget.authorHandle,
                  authorAvatarUrl: widget.authorAvatarUrl,
                ),
              ),
            ),
            _PublishBottomBar(isPublishing: _isPublishing, onPublish: _publish),
          ],
        ),
      ),
    );
  }
}

class _NewOutfitHeader extends StatelessWidget {
  const _NewOutfitHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
      child: SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.chevron_left),
              iconSize: 28,
              color: context.appPalette.ink,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'новый образ',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: 0,
                  color: context.appPalette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.appPalette.ink),
      ),
    );
  }
}

class _ResponsiveOutfitCard extends StatelessWidget {
  const _ResponsiveOutfitCard({
    required this.backgroundColor,
    required this.items,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
  });

  final Color backgroundColor;
  final List<NewOutfitPreviewItem> items;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 354).clamp(0.86, 1.0);
        return Center(
          child: SizedBox(
            width: 354 * scale,
            child: _PreviewOutfitCard(
              scale: scale,
              backgroundColor: backgroundColor,
              items: items,
              authorName: authorName,
              authorHandle: authorHandle,
              authorAvatarUrl: authorAvatarUrl,
            ),
          ),
        );
      },
    );
  }
}

class _PreviewOutfitCard extends StatelessWidget {
  const _PreviewOutfitCard({
    required this.scale,
    required this.backgroundColor,
    required this.items,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
  });

  final double scale;
  final Color backgroundColor;
  final List<NewOutfitPreviewItem> items;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(30 * scale),
        border: Border.all(color: context.appPalette.border),
        boxShadow: [
          BoxShadow(
            color: context.appPalette.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              _HeroMedia(
                scale: scale,
                backgroundColor: backgroundColor,
                items: items,
              ),
              _ProductsSection(scale: scale, items: items),
            ],
          ),
          Positioned(
            left: 16 * scale,
            right: 16 * scale,
            top: 488 * scale,
            child: _AuthorCard(
              scale: scale,
              authorName: authorName,
              authorHandle: authorHandle,
              authorAvatarUrl: authorAvatarUrl,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMedia extends StatelessWidget {
  const _HeroMedia({
    required this.scale,
    required this.backgroundColor,
    required this.items,
  });

  final double scale;
  final Color backgroundColor;
  final List<NewOutfitPreviewItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520 * scale,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30 * scale)),
        child: DecoratedBox(
          decoration: BoxDecoration(color: backgroundColor),
          child: _PreviewCanvasItems(items: items),
        ),
      ),
    );
  }
}

class _PreviewCanvasItems extends StatelessWidget {
  const _PreviewCanvasItems({required this.items});

  final List<NewOutfitPreviewItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: context.appPalette.surfaceMuted),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final item in items)
              Positioned.fill(
                child: Center(
                  child: Transform.translate(
                    offset: Offset(
                      item.offsetX * constraints.maxWidth,
                      item.offsetY * constraints.maxHeight,
                    ),
                    child: Transform.rotate(
                      angle: item.rotation,
                      child: Transform.scale(
                        scale: item.scale,
                        child: SizedBox(
                          width: constraints.maxWidth * item.widthFactor,
                          height: constraints.maxHeight * item.heightFactor,
                          child: AppImage(
                            imageUrl: item.image,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            placeholderColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AuthorCard extends StatelessWidget {
  const _AuthorCard({
    required this.scale,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
  });

  final double scale;
  final String authorName;
  final String authorHandle;
  final String authorAvatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64 * scale,
      padding: EdgeInsets.symmetric(horizontal: 12 * scale),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(18 * scale),
        boxShadow: [
          BoxShadow(
            color: context.appPalette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: 38 * scale,
              height: 38 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appPalette.surfaceMuted,
              ),
              child: authorAvatarUrl.trim().isEmpty
                  ? Icon(
                      Icons.person_outline,
                      size: 20 * scale,
                      color: context.appPalette.muted,
                    )
                  : AppImage(
                      imageUrl: authorAvatarUrl,
                      width: 38 * scale,
                      height: 38 * scale,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w600,
                    height: 1.05,
                    letterSpacing: 0,
                    color: context.appPalette.ink,
                  ),
                ),
                SizedBox(height: 3 * scale),
                Text(
                  '$authorHandle · 0 лайков',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11.5 * scale,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    letterSpacing: 0,
                    color: context.appPalette.muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8 * scale),
          Icon(
            Icons.favorite_outline,
            size: 22 * scale,
            color: context.appPalette.muted,
          ),
        ],
      ),
    );
  }
}

class _ProductsSection extends StatefulWidget {
  const _ProductsSection({required this.scale, required this.items});

  final double scale;
  final List<NewOutfitPreviewItem> items;

  @override
  State<_ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends State<_ProductsSection> {
  late final ScrollController _controller;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final nextLeft = _controller.offset > 2;
    final nextRight =
        _controller.position.maxScrollExtent - _controller.offset > 2;
    if (nextLeft == _canScrollLeft && nextRight == _canScrollRight) return;
    setState(() {
      _canScrollLeft = nextLeft;
      _canScrollRight = nextRight;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16 * widget.scale,
        58 * widget.scale,
        0,
        22 * widget.scale,
      ),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30 * widget.scale),
        ),
      ),
      child: SizedBox(
        height: 86 * widget.scale,
        child: Stack(
          children: [
            if (widget.items.isEmpty)
              const SizedBox.expand()
            else
              ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(right: 16 * widget.scale),
                itemCount: widget.items.length,
                separatorBuilder: (context, index) =>
                    SizedBox(width: 12 * widget.scale),
                itemBuilder: (context, index) {
                  return _ProductCard(
                    scale: widget.scale,
                    item: widget.items[index],
                  );
                },
              ),
            if (_canScrollLeft)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _ScrollArrow(
                  scale: widget.scale,
                  icon: Icons.chevron_left,
                ),
              ),
            if (_canScrollRight)
              Positioned(
                right: 12 * widget.scale,
                top: 0,
                bottom: 0,
                child: _ScrollArrow(
                  scale: widget.scale,
                  icon: Icons.chevron_right,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.scale, required this.item});

  final double scale;
  final NewOutfitPreviewItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80 * scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appPalette.surface,
          borderRadius: BorderRadius.circular(5 * scale),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5 * scale),
          child: AppImage(
            imageUrl: item.image,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            placeholderColor: context.appPalette.surface,
          ),
        ),
      ),
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({required this.scale, required this.icon});

  final double scale;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34 * scale,
      child: Center(
        child: Container(
          width: 28 * scale,
          height: 28 * scale,
          decoration: BoxDecoration(
            color: context.appPalette.surfaceRaised.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: context.appPalette.shadow,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 18 * scale, color: context.appPalette.ink),
        ),
      ),
    );
  }
}

class _PublishBottomBar extends StatelessWidget {
  const _PublishBottomBar({
    required this.isPublishing,
    required this.onPublish,
  });

  final bool isPublishing;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      height: 82,
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised,
        border: Border(top: BorderSide(color: context.appPalette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 22, 10, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isPublishing ? null : onPublish,
          child: Container(
            width: double.infinity,
            height: 40,
            color: scheme.primary,
            alignment: Alignment.center,
            child: isPublishing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : Text(
                    'ОПУБЛИКОВАТЬ ОБРАЗ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: scheme.onPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
