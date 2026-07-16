import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens own reviews from the profile card in read-only mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? loadedSellerId;
    final review = SellerReview(
      id: 'review-1',
      sellerId: 'seller-user',
      buyerId: 'buyer-user',
      buyerName: 'Анна',
      productId: 'product-1',
      productTitle: 'Куртка',
      rating: 5,
      text: 'Всё отлично, вещь как новая.',
      createdAt: DateTime(2026, 7, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: const AppProfile(
            name: 'Ева Смирнова',
            handle: '@eva',
            city: 'Москва',
            rating: 4.8,
            salesCount: 1,
            followersCount: 24,
          ),
          products: const [],
          likedProducts: const [],
          likedOutfits: const [],
          recentlyViewedProducts: const [],
          recentlyViewedOutfits: const [],
          outfits: const [],
          allProducts: const [],
          isSignedIn: true,
          isSigningIn: false,
          accountLabel: 'eva@example.com',
          authError: null,
          currentUserId: 'seller-user',
          notifications: const [],
          notificationPreferences: const NotificationPreferences(),
          orders: const [],
          sellerDashboardStats: const SellerDashboardStats(
            rating: 4.8,
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
          onSavePersonalProfile: (profile, avatar) async => null,
          onConfirmEmail: (email) async => null,
          onDeleteAccount: () async => null,
          onToggleProductLike: (id) async {},
          onToggleOutfitLike: (id) async {},
          onDeleteProduct: (id) async {},
          onProductTap: (_) {},
          onOutfitAuthorTap: (_) {},
          onMarkNotificationRead: (id) async {},
          onMarkAllNotificationsRead: () async {},
          onNotificationTap: (notification) async {},
          onUpdateNotificationPreferences: (preferences) async {},
          onLoadReviews: (sellerId) async {
            loadedSellerId = sellerId;
            return [review];
          },
          onOpenCatalog: () {},
        ),
      ),
    );

    expect(find.text('Ева Смирнова'), findsOneWidget);
    expect(find.text('@eva'), findsOneWidget);
    expect(find.text('Москва'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('4,8  ·  Отзывы'), findsOneWidget);
    await tester.tap(find.text('4,8  ·  Отзывы'));
    await tester.pumpAndSettle();

    expect(loadedSellerId, 'seller-user');
    expect(find.text('Отзывы'), findsOneWidget);
    expect(find.text('Анна'), findsOneWidget);
    expect(find.text('Всё отлично, вещь как новая.'), findsOneWidget);
    expect(find.text('ОСТАВИТЬ ОТЗЫВ'), findsNothing);
  });
}
