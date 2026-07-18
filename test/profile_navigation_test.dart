import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/edit_profile_screen.dart';
import 'package:clothes/screens/messages_screen.dart';
import 'package:clothes/screens/outfits_screen.dart';
import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:clothes/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'settings opens its own screen and recent history can be cleared',
    (tester) async {
      var clearCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _profileScreen(
            recentProducts: [_product()],
            onClear: () async => clearCalls++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('profile-settings-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile-settings-edit-profile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile-settings-notifications')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile-settings-addresses')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.chevron_left).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('недавно смотрели'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear-recent-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-clear-recent-history')));
      await tester.pumpAndSettle();

      expect(clearCalls, 1);
      expect(find.byKey(const Key('clear-recent-history')), findsNothing);
    },
  );

  testWidgets('profile, messages and outfits headers share a vertical origin', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _profileScreen()));
    final profileTop = tester
        .getTopLeft(find.byKey(const Key('profile-header-row')))
        .dy;

    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: MessagesScreen(
            threads: const [],
            onSendMessage: (_, _) async {},
            onSearchUsers: (_) async => const [],
            onStartDirectChat: (_) async => null,
            onCreateConversation: (_, {title = ''}) async => null,
            currentUserId: 'current-user',
            threadsListenable: notifier,
            resolveThread: (_) => null,
            lastSeenForUser: (_) => null,
          ),
        ),
      ),
    );
    final messagesTop = tester
        .getTopLeft(find.byKey(const Key('messages-header-row')))
        .dy;

    await tester.pumpWidget(
      MaterialApp(
        home: OutfitsScreen(
          scale: 1,
          sidePadding: 18,
          onCreateTap: () {},
          onToggleProductLike: (_) async {},
          onToggleOutfitLike: (_) async {},
          onProductViewed: (_) async => 0,
          onOutfitViewed: (_) async => 0,
          onContactSeller:
              (_, {imageOnly = false, Route<dynamic>? sourceRoute}) async {},
          onOpenSellerProfile: (_) {},
          deliveryProfile: const DeliveryProfile(),
          onSaveDeliveryProfile: (_) async {},
          onCreateDeliveryOrder:
              (_, {required deliveryService, required deliveryPrice}) async =>
                  null,
        ),
      ),
    );
    final outfitsTop = tester
        .getTopLeft(find.byKey(const Key('outfits-header-row')))
        .dy;

    expect(messagesTop, closeTo(profileTop, 0.01));
    expect(outfitsTop, closeTo(profileTop, 0.01));
  });

  testWidgets('every settings row opens its intended destination', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: _profileScreen()),
    );
    await tester.tap(find.byKey(const Key('profile-settings-button')));
    await tester.pumpAndSettle();

    Future<void> verifyRoute(Key key, Finder destination) async {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(destination, findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    }

    await verifyRoute(
      const Key('profile-settings-edit-profile'),
      find.byType(EditProfileScreen),
    );
    await verifyRoute(
      const Key('profile-settings-notifications'),
      find.byType(NotificationSettingsScreen),
    );
    await verifyRoute(
      const Key('profile-settings-addresses'),
      find.byType(ProfileAddressesScreen),
    );
    await verifyRoute(
      const Key('profile-settings-support'),
      find.text('поддержка'),
    );
    await verifyRoute(
      const Key('profile-settings-faq'),
      find.text('частые вопросы'),
    );
    await verifyRoute(
      const Key('profile-settings-documents'),
      find.text('документы'),
    );
  });

  testWidgets('profile menu does not expose unfinished gift cards', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _profileScreen()));
    await tester.scrollUntilVisible(find.text('мои заказы'), 400);

    expect(find.textContaining('подарочная карта'), findsNothing);
  });
}

ProfileScreen _profileScreen({
  List<Product> recentProducts = const [],
  Future<void> Function()? onClear,
}) {
  return ProfileScreen(
    profile: const AppProfile(
      name: 'Test User',
      handle: '@test',
      city: 'Moscow',
      rating: 4.9,
      salesCount: 3,
      followersCount: 12,
    ),
    products: const [],
    likedProducts: const [],
    likedOutfits: const [],
    recentlyViewedProducts: recentProducts,
    recentlyViewedOutfits: const [],
    outfits: const [],
    allProducts: recentProducts,
    isSignedIn: true,
    isSigningIn: false,
    accountLabel: 'test@example.com',
    authError: null,
    currentUserId: 'current-user',
    notifications: const [],
    notificationPreferences: const NotificationPreferences(),
    orders: const [],
    sellerDashboardStats: const SellerDashboardStats(
      rating: 4.9,
      commissionPercent: 10,
      revenue: 0,
      ordersCount: 0,
      averageOrder: 0,
      returnsPercent: 0,
    ),
    onSignInWithYandex: () async {},
    onSignInWithTelegram: () {},
    onSignOut: () async {},
    onUpdateProfile: ({required name, required handle}) async => null,
    onSavePersonalProfile: (_, _) async => null,
    onConfirmEmail: (_) async => null,
    onDeleteAccount: () async => null,
    onToggleProductLike: (_) async {},
    onToggleOutfitLike: (_) async {},
    onClearRecentlyViewed: onClear ?? () async {},
    onDeleteProduct: (_) async {},
    onProductTap: (_) {},
    onShareProduct: (_) {},
    onOutfitAuthorTap: (_) {},
    onMarkNotificationRead: (_) async {},
    onMarkAllNotificationsRead: () async {},
    onNotificationTap: (_) async {},
    onUpdateNotificationPreferences: (_) async {},
    onLoadReviews: (_) async => const [],
    onOpenCatalog: () {},
  );
}

Product _product() => Product(
  id: 'recent-product',
  title: 'Sweater',
  detailTitle: 'Sweater',
  description: '',
  price: '3 000 ₽',
  detailPrice: '3 000 ₽',
  priceValue: 3000,
  image: '',
  category: 'Clothes',
  brand: 'Brand',
  size: 'M',
  color: 'White',
  condition: 'Good',
  ownerId: 'seller',
  sellerName: 'Seller',
  sellerHandle: '@seller',
  dotsOnDark: false,
);
