import 'package:flutter/material.dart';

import '../core/app_typography.dart';
import 'app_image.dart';

class PromoBanner {
  const PromoBanner({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    this.onTap,
  });

  final String image;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback? onTap;
}

class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key, required this.banners, this.height});

  final List<PromoBanner> banners;
  final double? height;

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  final PageController _pageController = PageController();
  int _activeIndex = 0;

  @override
  void didUpdateWidget(covariant PromoBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_activeIndex >= widget.banners.length) {
      _activeIndex = widget.banners.isEmpty ? 0 : widget.banners.length - 1;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final bannerHeight =
        widget.height ?? (screenWidth * 1.32).clamp(500.0, 540.0).toDouble();

    return SizedBox(
      width: double.infinity,
      height: bannerHeight,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.banners.length,
        onPageChanged: (index) => setState(() => _activeIndex = index),
        itemBuilder: (context, index) {
          return PromoBannerCard(
            banner: widget.banners[index],
            activeIndex: _activeIndex,
            totalCount: widget.banners.length,
          );
        },
      ),
    );
  }
}

class PromoBannerCard extends StatelessWidget {
  const PromoBannerCard({
    super.key,
    required this.banner,
    required this.activeIndex,
    required this.totalCount,
  });

  final PromoBanner banner;
  final int activeIndex;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: banner.onTap,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppImage(
              imageUrl: banner.image,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xA6000000)],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PromoDots(activeIndex: activeIndex, totalCount: totalCount),
                  if (banner.title.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      banner.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 36,
                        fontWeight: AppTypography.bold,
                        color: Colors.white,
                        height: 1.0,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                  if (banner.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      banner.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: AppTypography.medium,
                        color: Colors.white,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: banner.onTap,
                    child: Container(
                      width: 245,
                      height: 48,
                      alignment: Alignment.center,
                      color: Colors.white,
                      child: Text(
                        banner.buttonText,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 14,
                          fontWeight: AppTypography.bold,
                          color: Colors.black,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PromoDots extends StatelessWidget {
  const PromoDots({
    super.key,
    required this.activeIndex,
    required this.totalCount,
  });

  final int activeIndex;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalCount, (index) {
        final isActive = index == activeIndex;
        return Container(
          width: 7,
          height: 7,
          margin: EdgeInsets.only(right: index == totalCount - 1 ? 0 : 7),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.42),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
