import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_profile.dart';
import '../models/created_outfit.dart';
import '../models/product.dart';
import '../models/profile_feature.dart';
import '../widgets/app_image.dart';
import 'edit_profile_screen.dart';
import 'profile_feature_screens.dart';
import 'reviews_screen.dart';

const _outfitMediaBackground = Color(0xFFF4F4F4);
const _profileInk = Color(0xFF111113);
const _outfitItemBackground = Color(0xFFFFFFFF);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.products,
    required this.likedProducts,
    required this.likedOutfits,
    required this.recentlyViewedProducts,
    required this.recentlyViewedOutfits,
    required this.outfits,
    required this.allProducts,
    required this.isSignedIn,
    required this.isSigningIn,
    required this.accountLabel,
    required this.authError,
    required this.currentUserId,
    required this.notifications,
    required this.notificationPreferences,
    required this.orders,
    required this.sellerDashboardStats,
    required this.onSignInWithYandex,
    required this.onSignInWithTelegram,
    required this.onSignOut,
    required this.onUpdateProfile,
    required this.onSavePersonalProfile,
    required this.onConfirmEmail,
    required this.onDeleteAccount,
    required this.onToggleProductLike,
    required this.onToggleOutfitLike,
    required this.onDeleteProduct,
    required this.onProductTap,
    required this.onOutfitAuthorTap,
    required this.onMarkNotificationRead,
    required this.onUpdateNotificationPreferences,
    required this.onLoadReviews,
    required this.onOpenCatalog,
  });

  final AppProfile profile;
  final List<Product> products;
  final List<Product> likedProducts;
  final List<CreatedOutfit> likedOutfits;
  final List<Product> recentlyViewedProducts;
  final List<CreatedOutfit> recentlyViewedOutfits;
  final List<CreatedOutfit> outfits;
  final List<Product> allProducts;
  final bool isSignedIn;
  final bool isSigningIn;
  final String? accountLabel;
  final String? authError;
  final String currentUserId;
  final List<ProfileNotification> notifications;
  final NotificationPreferences notificationPreferences;
  final List<AppOrder> orders;
  final SellerDashboardStats sellerDashboardStats;
  final Future<void> Function() onSignInWithYandex;
  final VoidCallback onSignInWithTelegram;
  final Future<void> Function() onSignOut;
  final Future<String?> Function({required String name, required String handle})
  onUpdateProfile;
  final Future<String?> Function(AppProfile profile, XFile? avatarFile)
  onSavePersonalProfile;
  final Future<String?> Function(String email) onConfirmEmail;
  final Future<String?> Function() onDeleteAccount;
  final Future<void> Function(String productId) onToggleProductLike;
  final Future<void> Function(String outfitId) onToggleOutfitLike;
  final Future<void> Function(String productId) onDeleteProduct;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<CreatedOutfit> onOutfitAuthorTap;
  final Future<void> Function(String notificationId) onMarkNotificationRead;
  final Future<void> Function(NotificationPreferences preferences)
  onUpdateNotificationPreferences;
  final Future<List<SellerReview>> Function(String sellerId) onLoadReviews;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final outfitCards = outfits.map(_ProfileOutfit.fromOutfit).toList();
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, topInset + 12, 18, 136),
          children: [
            _ProfileTopBar(
              hasUnreadNotifications: notifications.any(
                (notification) => !notification.isRead,
              ),
              onNotificationsTap: () => _openNotifications(context),
              onSettingsTap: () => _openEditProfile(context),
            ),
            const SizedBox(height: 16),
            _ProfileOverviewCard(
              profile: profile,
              onEditTap: () => _openEditProfile(context),
              onReviewsTap: () => _openReviews(context),
            ),
            _ProfileShortcutSection(
              favoritesCount: likedProducts.length + likedOutfits.length,
              recentCount:
                  recentlyViewedProducts.length + recentlyViewedOutfits.length,
              favoritesBackgroundImage: likedProducts.isNotEmpty
                  ? likedProducts.first.image
                  : likedOutfits.isNotEmpty &&
                        likedOutfits.first.photos.isNotEmpty
                  ? likedOutfits.first.photos.first
                  : null,
              recentBackgroundImage: recentlyViewedProducts.isNotEmpty
                  ? recentlyViewedProducts.first.image
                  : recentlyViewedOutfits.isNotEmpty &&
                        recentlyViewedOutfits.first.photos.isNotEmpty
                  ? recentlyViewedOutfits.first.photos.first
                  : null,
              onFavoritesTap: () => _openLikedProducts(context),
              onRecentTap: () => _openRecentlyViewedProducts(context),
            ),
            _PhotoPreviewSection(
              title: 'мои объявления',
              count: products.length,
              images: products.map((product) => product.image).take(3).toList(),
              emptyText: 'Пока нет объявлений',
              emptyIcon: Icons.sell_outlined,
              topPadding: 22,
              onOpen: () => _openProducts(context),
            ),
            _PhotoPreviewSection(
              title: 'мои образы',
              count: outfitCards.length,
              images: outfitCards
                  .map((outfit) => outfit.image)
                  .take(3)
                  .toList(),
              emptyText: 'Пока нет образов',
              emptyIcon: Icons.checkroom_outlined,
              topPadding: 22,
              onOpen: () => _openOutfits(context),
            ),
            const SizedBox(height: 24),
            _ProfileMenuSection(
              rows: [
                _MenuRowData('мои заказы', _ProfileMenuAction.orders),
                _MenuRowData('уведомления', _ProfileMenuAction.notifications),
                _MenuRowData(
                  'настройки уведомлений',
                  _ProfileMenuAction.notificationSettings,
                ),
                _MenuRowData('мои адреса', _ProfileMenuAction.addresses),
                _MenuRowData('подарочная карта', _ProfileMenuAction.giftCard),
                _MenuRowData(
                  'дашборд продавца',
                  _ProfileMenuAction.sellerDashboard,
                ),
              ],
              onSelected: (action) => _openProfileMenu(context, action),
            ),
            const _CountrySection(),
            const _SupportSection(),
            const _InfoSection(),
            const SizedBox(height: 10),
            _LogoutBlock(onSignOut: onSignOut),
          ],
        ),
      ),
    );
  }

  void _openProducts(BuildContext context) {
    _openProductList(
      context,
      title: 'мои объявления',
      emptyText: 'активных объявлений пока нет',
      products: products,
    );
  }

  void _openEditProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditProfileScreen(
          profile: profile,
          accountEmail: accountLabel ?? '',
          isSignedIn: isSignedIn,
          onSave: onSavePersonalProfile,
          onConfirmEmail: onConfirmEmail,
          onDeleteAccount: onDeleteAccount,
        ),
      ),
    );
  }

  void _openReviews(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewsScreen(
          seller: SellerProfile(
            id: currentUserId,
            name: profile.name,
            handle: profile.handle,
            avatarUrl: profile.avatarUrl,
            city: profile.city,
            rating: profile.rating,
            salesCount: profile.salesCount,
            followersCount: profile.followersCount,
          ),
          sourceProduct: null,
          loadReviews: onLoadReviews,
          onCreateReview: null,
          canCreateReview: false,
        ),
      ),
    );
  }

  void _openLikedProducts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileCollectionScreen(
          title: 'избранное',
          productEmptyText: 'в избранном пока нет вещей',
          outfitEmptyText: 'в избранном пока нет образов',
          products: likedProducts,
          outfits: likedOutfits,
          allProducts: allProducts,
          onToggleProductLike: onToggleProductLike,
          onToggleOutfitLike: onToggleOutfitLike,
          onProductTap: onProductTap,
          onOutfitAuthorTap: onOutfitAuthorTap,
        ),
      ),
    );
  }

  void _openRecentlyViewedProducts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileCollectionScreen(
          title: 'недавно просмотренное',
          productEmptyText: 'просмотренных вещей пока нет',
          outfitEmptyText: 'просмотренных образов пока нет',
          products: recentlyViewedProducts,
          outfits: recentlyViewedOutfits,
          allProducts: allProducts,
          onToggleProductLike: onToggleProductLike,
          onToggleOutfitLike: onToggleOutfitLike,
          onProductTap: onProductTap,
          onOutfitAuthorTap: onOutfitAuthorTap,
        ),
      ),
    );
  }

  void _openProductList(
    BuildContext context, {
    required String title,
    required String emptyText,
    required List<Product> products,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AllProductsScreen(
          title: title,
          emptyText: emptyText,
          products: products,
          onDeleteProduct: onDeleteProduct,
          onToggleLike: onToggleProductLike,
          onProductTap: onProductTap,
        ),
      ),
    );
  }

  void _openOutfits(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AllOutfitsScreen(
          outfits: outfits,
          products: allProducts,
          onToggleLike: onToggleOutfitLike,
          onAuthorTap: onOutfitAuthorTap,
        ),
      ),
    );
  }

  void _openProfileMenu(BuildContext context, _ProfileMenuAction action) {
    switch (action) {
      case _ProfileMenuAction.orders:
        _openOrders(context);
        break;
      case _ProfileMenuAction.notifications:
        _openNotifications(context);
        break;
      case _ProfileMenuAction.notificationSettings:
        _openNotificationSettings(context);
        break;
      case _ProfileMenuAction.sellerDashboard:
        _openSellerDashboard(context);
        break;
      case _ProfileMenuAction.addresses:
        _openAddresses(context);
        break;
      case _ProfileMenuAction.giftCard:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Раздел сохраняется в профиле и будет доступен после добавления данных.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
    }
  }

  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ProfileNotificationsScreen(
          notifications: notifications,
          onMarkRead: onMarkNotificationRead,
        ),
      ),
    );
  }

  void _openNotificationSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => NotificationSettingsScreen(
          preferences: notificationPreferences,
          onSave: onUpdateNotificationPreferences,
        ),
      ),
    );
  }

  void _openCatalogFromFeature(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    onOpenCatalog();
  }

  void _openOrders(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ProfileOrdersScreen(
          orders: orders,
          recommendedProducts: allProducts,
          currentUserId: currentUserId,
          onProductTap: onProductTap,
          onToggleProductLike: onToggleProductLike,
          onOpenCatalog: () => _openCatalogFromFeature(context),
        ),
      ),
    );
  }

  void _openAddresses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ProfileAddressesScreen(
          onOpenCatalog: () => _openCatalogFromFeature(context),
        ),
      ),
    );
  }

  void _openSellerDashboard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            SellerDashboardScreen(stats: sellerDashboardStats),
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({
    required this.hasUnreadNotifications,
    required this.onNotificationsTap,
    required this.onSettingsTap,
  });

  final bool hasUnreadNotifications;
  final VoidCallback onNotificationsTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'профиль',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -0.4,
                color: Color(0xFF070707),
              ),
            ),
          ),
          _ProfileActionButton(
            icon: Icons.notifications_none_rounded,
            hasIndicator: hasUnreadNotifications,
            onTap: onNotificationsTap,
          ),
          const SizedBox(width: 8),
          _ProfileActionButton(
            icon: Icons.settings_outlined,
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.onTap,
    this.hasIndicator = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool hasIndicator;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F5F7),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF111114)),
              if (hasIndicator)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D46),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({
    required this.profile,
    required this.onEditTap,
    required this.onReviewsTap,
  });

  final AppProfile profile;
  final VoidCallback onEditTap;
  final VoidCallback onReviewsTap;

  @override
  Widget build(BuildContext context) {
    final displayName = profile.name.trim().isEmpty
        ? 'Имя Фамилия'
        : profile.name.trim();
    final handle = _normalizedHandle(profile.handle);
    final city = profile.city.trim();
    final rating = profile.rating.toStringAsFixed(1).replaceAll('.', ',');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D0D0F), Color(0xFF26262A)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProfileAvatar(
                avatarUrl: profile.avatarUrl,
                displayName: displayName,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x17FFFFFF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              handle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1,
                                letterSpacing: 0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (city.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: Color(0xFF9C9CA4),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                height: 1,
                                letterSpacing: 0,
                                color: Color(0xFF9C9CA4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProfileEditButton(onTap: onEditTap),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ProfileStatTile(value: rating, label: 'рейтинг'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileStatTile(
                  value: '${profile.salesCount}',
                  label: 'продажи',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileStatTile(
                  value: '${profile.followersCount}',
                  label: 'подписчики',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onReviewsTap,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 19,
                        color: _profileInk,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$rating  ·  Отзывы',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: 0,
                          color: _profileInk,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _profileReviewCountLabel(profile.salesCount),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            letterSpacing: 0,
                            color: Color(0x99111113),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: _profileInk,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _normalizedHandle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '@user';
    return trimmed.startsWith('@') ? trimmed : '@$trimmed';
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl, required this.displayName});

  final String avatarUrl;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFF55555C)],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0D0D0F),
        ),
        child: ClipOval(
          child: ColoredBox(
            color: const Color(0xFFEEEEF0),
            child: avatarUrl.trim().isEmpty
                ? Center(
                    child: Text(
                      displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _profileInk,
                      ),
                    ),
                  )
                : AppImage(
                    imageUrl: avatarUrl,
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  const _ProfileStatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: 0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0.2,
              color: Color(0xFF9C9CA4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileEditButton extends StatelessWidget {
  const _ProfileEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Редактировать профиль',
      child: Material(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.edit_outlined, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

String _profileReviewCountLabel(int count) {
  final mod100 = count % 100;
  if (mod100 >= 11 && mod100 <= 14) return '$count отзывов покупателей';
  return switch (count % 10) {
    1 => '$count отзыв покупателя',
    2 || 3 || 4 => '$count отзыва покупателей',
    _ => '$count отзывов покупателей',
  };
}

class _ProfileShortcutSection extends StatelessWidget {
  const _ProfileShortcutSection({
    required this.favoritesCount,
    required this.recentCount,
    required this.favoritesBackgroundImage,
    required this.recentBackgroundImage,
    required this.onFavoritesTap,
    required this.onRecentTap,
  });

  final int favoritesCount;
  final int recentCount;
  final String? favoritesBackgroundImage;
  final String? recentBackgroundImage;
  final VoidCallback onFavoritesTap;
  final VoidCallback onRecentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: _ProfileShortcutTile(
              icon: Icons.favorite_border_rounded,
              title: 'избранное',
              count: favoritesCount,
              backgroundImage: favoritesBackgroundImage,
              onTap: onFavoritesTap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProfileShortcutTile(
              icon: Icons.history_rounded,
              title: 'недавно смотрели',
              count: recentCount,
              backgroundImage: recentBackgroundImage,
              onTap: onRecentTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileShortcutTile extends StatelessWidget {
  const _ProfileShortcutTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.backgroundImage,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int count;
  final String? backgroundImage;
  final VoidCallback onTap;

  bool get _hasBackgroundImage =>
      backgroundImage != null && backgroundImage!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    const radius = 21.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          height: 86,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F6)],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFECECEF), width: 1),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasBackgroundImage)
                Positioned(
                  left: 34,
                  right: -14,
                  top: -18,
                  bottom: -24,
                  child: Opacity(
                    opacity: 0.11,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: AppImage(
                        imageUrl: backgroundImage!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        placeholderColor: Colors.transparent,
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  right: -14,
                  bottom: -23,
                  child: Opacity(
                    opacity: 0.045,
                    child: Icon(icon, size: 104, color: _profileInk),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.96),
                        Colors.white.withValues(alpha: 0.78),
                        Colors.white.withValues(alpha: 0.22),
                      ],
                      stops: const [0, 0.52, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 11,
                top: 11,
                child: Container(
                  width: 31,
                  height: 31,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE8E8EB)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.045),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 18, color: _profileInk),
                ),
              ),
              Positioned(
                right: 11,
                top: 11,
                child: Container(
                  height: 25,
                  constraints: const BoxConstraints(minWidth: 27),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _profileInk,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 10,
                bottom: 11,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: -0.1,
                          color: _profileInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: _profileInk,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPreviewSection extends StatelessWidget {
  const _PhotoPreviewSection({
    required this.title,
    required this.count,
    required this.images,
    required this.emptyText,
    required this.emptyIcon,
    required this.onOpen,
    this.topPadding = 18,
  });

  final String title;
  final int count;
  final List<String> images;
  final String emptyText;
  final IconData emptyIcon;
  final VoidCallback onOpen;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final visibleImages = images.take(3).toList();

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      letterSpacing: 0,
                      color: _profileInk,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    height: 22,
                    constraints: const BoxConstraints(minWidth: 26),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: _profileInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Color(0xFF85858C),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          if (visibleImages.isEmpty)
            _EmptyPhotoPreview(icon: emptyIcon, text: emptyText, onTap: onOpen)
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: SizedBox(
                height: 104,
                child: Row(
                  children: List.generate(3, (index) {
                    final image = index < visibleImages.length
                        ? visibleImages[index]
                        : '';
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                        child: _PreviewPhoto(image: image),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPhotoPreview extends StatelessWidget {
  const _EmptyPhotoPreview({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7F8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 82,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: const Color(0xFF77777F)),
              ),
              const SizedBox(width: 10),
              Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0,
                  color: Color(0xFF77777F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPhoto extends StatelessWidget {
  const _PreviewPhoto({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: _outfitMediaBackground,
        child: image.trim().isEmpty
            ? const Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 24,
                  color: Color(0xFFC7C7CC),
                ),
              )
            : AppImage(
                imageUrl: image,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                placeholderColor: _outfitMediaBackground,
              ),
      ),
    );
  }
}

class _ProfileCollectionScreen extends StatefulWidget {
  const _ProfileCollectionScreen({
    required this.title,
    required this.productEmptyText,
    required this.outfitEmptyText,
    required this.products,
    required this.outfits,
    required this.allProducts,
    required this.onToggleProductLike,
    required this.onToggleOutfitLike,
    required this.onProductTap,
    required this.onOutfitAuthorTap,
  });

  final String title;
  final String productEmptyText;
  final String outfitEmptyText;
  final List<Product> products;
  final List<CreatedOutfit> outfits;
  final List<Product> allProducts;
  final Future<void> Function(String productId) onToggleProductLike;
  final Future<void> Function(String outfitId) onToggleOutfitLike;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<CreatedOutfit> onOutfitAuthorTap;

  @override
  State<_ProfileCollectionScreen> createState() =>
      _ProfileCollectionScreenState();
}

class _ProfileCollectionScreenState extends State<_ProfileCollectionScreen> {
  int _selectedTab = 0;

  bool get _showsProducts => _selectedTab == 0;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: widget.title,
      isEmpty: _showsProducts
          ? widget.products.isEmpty
          : widget.outfits.isEmpty,
      emptyText: _showsProducts
          ? widget.productEmptyText
          : widget.outfitEmptyText,
      backgroundColor: _showsProducts ? Colors.white : _outfitMediaBackground,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: _ProfileCollectionTabs(
          selectedIndex: _selectedTab,
          onChanged: (index) => setState(() => _selectedTab = index),
        ),
      ),
      child: _showsProducts
          ? _ProductsGrid(
              products: widget.products,
              onToggleLike: widget.onToggleProductLike,
              onProductTap: widget.onProductTap,
            )
          : _OutfitsList(
              outfits: widget.outfits,
              products: widget.allProducts,
              onToggleLike: widget.onToggleOutfitLike,
              onAuthorTap: widget.onOutfitAuthorTap,
            ),
    );
  }
}

class _ProfileCollectionTabs extends StatelessWidget {
  const _ProfileCollectionTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _ProfileCollectionTab(
            label: 'вещи',
            isActive: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _ProfileCollectionTab(
            label: 'образы',
            isActive: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _ProfileCollectionTab extends StatelessWidget {
  const _ProfileCollectionTab({
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: isActive ? Colors.white : const Color(0xFF070707),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({
    required this.products,
    required this.onToggleLike,
    required this.onProductTap,
    this.onDeleteProduct,
  });

  final List<Product> products;
  final Future<void> Function(String productId) onToggleLike;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId)? onDeleteProduct;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 120),
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 7,
        mainAxisSpacing: 4,
        mainAxisExtent: 320,
      ),
      itemBuilder: (context, index) {
        return _CatalogProductCard(
          product: products[index],
          onTap: () => onProductTap(products[index]),
          onMenu: onDeleteProduct == null
              ? null
              : () => onDeleteProduct!(products[index].id),
          onLike: () {
            onToggleLike(products[index].id);
          },
          onShare: () {
            // TODO: Share product.
          },
        );
      },
    );
  }
}

class _OutfitsList extends StatelessWidget {
  const _OutfitsList({
    required this.outfits,
    required this.products,
    required this.onToggleLike,
    required this.onAuthorTap,
  });

  final List<CreatedOutfit> outfits;
  final List<Product> products;
  final Future<void> Function(String outfitId) onToggleLike;
  final ValueChanged<CreatedOutfit> onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      physics: const BouncingScrollPhysics(),
      itemCount: outfits.length,
      separatorBuilder: (context, index) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        return _ProfileOutfitCard(
          outfit: outfits[index],
          products: products,
          onToggleLike: () => onToggleLike(outfits[index].id),
          onAuthorTap: onAuthorTap,
        );
      },
    );
  }
}

class _AllProductsScreen extends StatefulWidget {
  const _AllProductsScreen({
    required this.title,
    required this.emptyText,
    required this.products,
    required this.onToggleLike,
    required this.onDeleteProduct,
    required this.onProductTap,
  });

  final String title;
  final String emptyText;
  final List<Product> products;
  final Future<void> Function(String productId) onToggleLike;
  final Future<void> Function(String productId) onDeleteProduct;
  final ValueChanged<Product> onProductTap;

  @override
  State<_AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<_AllProductsScreen> {
  late List<Product> _products;

  @override
  void initState() {
    super.initState();
    _products = List<Product>.from(widget.products);
  }

  Future<void> _deleteProduct(String productId) async {
    await widget.onDeleteProduct(productId);
    if (!mounted) return;
    setState(() {
      _products.removeWhere((product) => product.id == productId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: widget.title,
      isEmpty: _products.isEmpty,
      emptyText: widget.emptyText,
      child: _ProductsGrid(
        products: _products,
        onToggleLike: widget.onToggleLike,
        onDeleteProduct: _deleteProduct,
        onProductTap: widget.onProductTap,
      ),
    );
  }
}

class _AllOutfitsScreen extends StatelessWidget {
  const _AllOutfitsScreen({
    required this.outfits,
    required this.products,
    required this.onToggleLike,
    required this.onAuthorTap,
  });

  final List<CreatedOutfit> outfits;
  final List<Product> products;
  final Future<void> Function(String outfitId) onToggleLike;
  final ValueChanged<CreatedOutfit> onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return _ProfileGridScaffold(
      title: 'мои образы',
      isEmpty: outfits.isEmpty,
      emptyText: 'активных образов пока нет',
      backgroundColor: _outfitMediaBackground,
      topPadding: 4,
      child: _OutfitsList(
        outfits: outfits,
        products: products,
        onToggleLike: onToggleLike,
        onAuthorTap: onAuthorTap,
      ),
    );
  }
}

class _ProfileOutfitCard extends StatefulWidget {
  const _ProfileOutfitCard({
    required this.outfit,
    required this.products,
    required this.onToggleLike,
    required this.onAuthorTap,
  });

  final CreatedOutfit outfit;
  final List<Product> products;
  final VoidCallback onToggleLike;
  final ValueChanged<CreatedOutfit> onAuthorTap;

  @override
  State<_ProfileOutfitCard> createState() => _ProfileOutfitCardState();
}

class _ProfileOutfitCardState extends State<_ProfileOutfitCard> {
  late final PageController _pageController;

  Map<String, Product> get _productsById {
    return {for (final product in widget.products) product.id: product};
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const scale = 1.0;
    final outfitProducts = widget.outfit.items.map((item) {
      final product = _productsById[item.id];
      return _OutfitProductPreview(
        name: item.name,
        price: item.price,
        image: product?.outfitDisplayImage ?? item.image,
      );
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFF0F0F2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
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
              _OutfitHeroMedia(
                scale: scale,
                photos: widget.outfit.photos,
                previewBackgroundColor: widget.outfit.previewBackgroundColor,
                layoutItems: widget.outfit.layoutItems,
                pageController: _pageController,
              ),
              _OutfitProductsStrip(scale: scale, products: outfitProducts),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 398,
            child: _OutfitAuthorCard(
              authorName: widget.outfit.authorName.trim().isEmpty
                  ? 'Автор'
                  : widget.outfit.authorName,
              authorHandle: widget.outfit.authorHandle.trim().isEmpty
                  ? '@user'
                  : widget.outfit.authorHandle,
              isLiked: widget.outfit.isLiked,
              likesCount: 0,
              onLikeTap: widget.onToggleLike,
              onAuthorTap: () => widget.onAuthorTap(widget.outfit),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitHeroMedia extends StatelessWidget {
  const _OutfitHeroMedia({
    required this.scale,
    required this.photos,
    required this.previewBackgroundColor,
    required this.layoutItems,
    required this.pageController,
  });

  final double scale;
  final List<String> photos;
  final int? previewBackgroundColor;
  final List<OutfitLayoutItem> layoutItems;
  final PageController pageController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 430 * scale,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30 * scale)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (layoutItems.isNotEmpty)
              _OutfitLayoutCanvas(
                backgroundColor: Color(
                  previewBackgroundColor ?? _outfitMediaBackground.toARGB32(),
                ),
                items: layoutItems,
              )
            else
              PageView.builder(
                controller: pageController,
                itemCount: photos.isEmpty ? 1 : photos.length,
                itemBuilder: (context, index) {
                  if (photos.isEmpty) {
                    return const DecoratedBox(
                      decoration: BoxDecoration(color: _outfitMediaBackground),
                    );
                  }
                  return AppImage(
                    imageUrl: photos[index],
                    fit: BoxFit.fill,
                    alignment: Alignment.topCenter,
                    placeholderColor: _outfitMediaBackground,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OutfitLayoutCanvas extends StatelessWidget {
  const _OutfitLayoutCanvas({
    required this.backgroundColor,
    required this.items,
  });

  final Color backgroundColor;
  final List<OutfitLayoutItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor),
      child: LayoutBuilder(
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
      ),
    );
  }
}

class _OutfitAuthorCard extends StatelessWidget {
  const _OutfitAuthorCard({
    required this.authorName,
    required this.authorHandle,
    required this.isLiked,
    required this.likesCount,
    required this.onLikeTap,
    required this.onAuthorTap,
  });

  final String authorName;
  final String authorHandle;
  final bool isLiked;
  final int likesCount;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAuthorTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE9E9EC),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 20,
                color: Color(0xFF8F8F94),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      letterSpacing: 0,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$authorHandle • $likesCount лайков',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1,
                      letterSpacing: 0,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLikeTap,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_outline,
                size: 22,
                color: isLiked
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFF8F8F94),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitProductsStrip extends StatelessWidget {
  const _OutfitProductsStrip({required this.scale, required this.products});

  final double scale;
  final List<_OutfitProductPreview> products;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16 * scale, 42 * scale, 0, 12 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30 * scale),
        ),
      ),
      child: SizedBox(
        height: 84 * scale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(right: 16 * scale),
          itemCount: products.length,
          separatorBuilder: (context, index) => SizedBox(width: 10 * scale),
          itemBuilder: (context, index) {
            return _OutfitProductCard(scale: scale, product: products[index]);
          },
        ),
      ),
    );
  }
}

class _OutfitProductCard extends StatelessWidget {
  const _OutfitProductCard({required this.scale, required this.product});

  final double scale;
  final _OutfitProductPreview product;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74 * scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48 * scale,
            height: 48 * scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _outfitItemBackground,
                borderRadius: BorderRadius.circular(5 * scale),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5 * scale),
                child: product.image.trim().isEmpty
                    ? Container(
                        color: _outfitItemBackground,
                        child: Icon(
                          Icons.checkroom_outlined,
                          size: 24 * scale,
                          color: const Color(0xFFB8B8BD),
                        ),
                      )
                    : AppImage(
                        imageUrl: product.image,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        placeholderColor: _outfitItemBackground,
                      ),
              ),
            ),
          ),
          SizedBox(height: 3 * scale),
          Text(
            product.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 9.5 * scale,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
              color: const Color(0xFF111111),
            ),
          ),
          SizedBox(height: 1.5 * scale),
          Text(
            product.price,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10 * scale,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: 0,
              color: const Color(0xFF8F8F94),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitProductPreview {
  const _OutfitProductPreview({
    required this.name,
    required this.price,
    required this.image,
  });

  final String name;
  final String price;
  final String image;
}

class _ProfileGridScaffold extends StatelessWidget {
  const _ProfileGridScaffold({
    required this.title,
    required this.isEmpty,
    required this.emptyText,
    required this.child,
    this.backgroundColor = Colors.white,
    this.topPadding = 12,
    this.header,
  });

  final String title;
  final bool isEmpty;
  final String emptyText;
  final Widget child;
  final Color backgroundColor;
  final double topPadding;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, topInset + topPadding, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    splashRadius: 18,
                    icon: const Icon(
                      Icons.chevron_left,
                      size: 28,
                      color: Colors.black,
                    ),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ?header,
            Expanded(
              child: isEmpty
                  ? Center(
                      child: Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                          letterSpacing: 0,
                          color: Color(0xFF8E8E8E),
                        ),
                      ),
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogProductCard extends StatelessWidget {
  const _CatalogProductCard({
    required this.product,
    required this.onTap,
    required this.onLike,
    required this.onShare,
    this.onMenu,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CatalogImageCard(
              image: product.image,
              dotsOnDark: product.dotsOnDark,
              onMenu: onMenu,
              actionIcon: Icons.delete_outline,
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: SizedBox(
                height: 50,
                child: _CatalogInfo(
                  title: product.title,
                  price: product.price,
                  isLiked: product.isLiked,
                  onLike: onLike,
                  onShare: onShare,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogImageCard extends StatelessWidget {
  const _CatalogImageCard({
    required this.image,
    this.dotsOnDark = false,
    this.onMenu,
    this.actionIcon = Icons.more_horiz,
  });

  final String image;
  final bool dotsOnDark;
  final VoidCallback? onMenu;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final dotColor = dotsOnDark ? Colors.white : const Color(0xFF070707);

    return SizedBox(
      width: double.infinity,
      height: 266,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F9),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AppImage(
                  imageUrl: image,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                ),
              ),
            ),
            if (onMenu != null)
              Positioned(
                right: 12,
                top: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(actionIcon, size: 22, color: dotColor),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogInfo extends StatelessWidget {
  const _CatalogInfo({
    required this.title,
    required this.price,
    required this.isLiked,
    required this.onLike,
    required this.onShare,
  });

  final String title;
  final String price;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.08,
            letterSpacing: 0,
            color: Color(0xFF070707),
          ),
        ),
        const SizedBox(height: 1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                price,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: 0,
                  color: Color(0xFF070707),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _IconTapTarget(
              onTap: onLike,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: 23,
                color: const Color(0xFF070707),
              ),
            ),
            const SizedBox(width: 4),
            _IconTapTarget(
              onTap: onShare,
              child: const Icon(
                Icons.near_me_outlined,
                size: 23,
                color: Color(0xFF070707),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconTapTarget extends StatelessWidget {
  const _IconTapTarget({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 28, height: 28, child: Center(child: child)),
    );
  }
}

class _ProfileOutfit {
  const _ProfileOutfit({
    required this.title,
    required this.price,
    required this.image,
  });

  final String title;
  final String price;
  final String image;

  factory _ProfileOutfit.fromOutfit(CreatedOutfit outfit) {
    return _ProfileOutfit(
      title: 'образ',
      price: _formatOutfitPrice(outfit.items),
      image: outfit.photos.isNotEmpty
          ? outfit.photos.first
          : outfit.items.isNotEmpty
          ? outfit.items.first.image
          : '',
    );
  }

  static String _formatOutfitPrice(List<OutfitItem> items) {
    final total = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          (int.tryParse(item.price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0),
    );
    if (total <= 0) return 'цена не указана';

    final raw = total.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return '$buffer ₽';
  }
}

class _ProfileMenuSection extends StatelessWidget {
  const _ProfileMenuSection({required this.rows, required this.onSelected});

  final List<_MenuRowData> rows;
  final ValueChanged<_ProfileMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        ...rows.map(
          (row) =>
              _MenuRow(title: row.title, onTap: () => onSelected(row.action)),
        ),
      ],
    );
  }
}

class _MenuRowData {
  const _MenuRowData(this.title, this.action);

  final String title;
  final _ProfileMenuAction action;
}

enum _ProfileMenuAction {
  orders,
  notifications,
  notificationSettings,
  addresses,
  giftCard,
  sellerDashboard,
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    this.leading,
    this.showChevron = true,
    this.height = 52,
    this.textWeight = FontWeight.w600,
    this.onTap,
  });

  final String title;
  final Widget? leading;
  final bool showChevron;
  final double height;
  final FontWeight textWeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13.5,
                  fontWeight: textWeight,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, size: 19, color: Colors.black),
          ],
        ),
      ),
    );
  }
}

class _CountrySection extends StatelessWidget {
  const _CountrySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        _MenuRow(
          title: 'Россия',
          height: 54,
          leading: const _RussiaFlag(),
          onTap: () {
            // TODO: Open country selector.
          },
        ),
      ],
    );
  }
}

class _RussiaFlag extends StatelessWidget {
  const _RussiaFlag();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 21,
      height: 21,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: const Column(
        children: [
          Expanded(child: ColoredBox(color: Colors.white)),
          Expanded(child: ColoredBox(color: Color(0xFF1C57A7))),
          Expanded(child: ColoredBox(color: Color(0xFFE53935))),
        ],
      ),
    );
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        _SupportRow(
          icon: Icons.chat_bubble_outline,
          title: 'написать в поддержку',
          meta: 'онлайн',
          onTap: () {
            // TODO: Open support chat.
          },
        ),
        _SupportRow(
          icon: Icons.phone_outlined,
          title: 'позвонить',
          meta: 'в сети 24/7',
          onTap: () {
            // TODO: Start support call.
          },
        ),
        _SupportRow(
          icon: Icons.help_outline,
          title: 'FAQ',
          meta: 'частые вопросы',
          onTap: () {
            // TODO: Open FAQ.
          },
        ),
      ],
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
              ),
            ),
            Text(
              meta,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1,
                letterSpacing: 0,
                color: Color(0xFF8E8E8E),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 19, color: Colors.black),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SectionDivider(),
        _MenuRow(
          title: 'доставка и оплата',
          height: 48,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
        _MenuRow(
          title: 'документы',
          height: 48,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
        _MenuRow(
          title: 'вакансии',
          height: 48,
          textWeight: FontWeight.w500,
          showChevron: true,
        ),
      ],
    );
  }
}

class _LogoutBlock extends StatelessWidget {
  const _LogoutBlock({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionDivider(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSignOut,
          child: const SizedBox(
            height: 54,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'выйти из профиля',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                ),
                Icon(Icons.logout, size: 21, color: Color(0xFFFF3B30)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'версия приложения 1.0',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
              color: Color(0xFF8E8E8E),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 1,
      margin: const EdgeInsets.only(top: 4),
      color: const Color(0xFFE6E6E6),
    );
  }
}
