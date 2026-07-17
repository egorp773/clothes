import 'package:clothes/models/app_profile.dart';
import 'package:clothes/data/app_repository.dart';
import 'package:clothes/models/product.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/profile_screen.dart';
import 'package:clothes/screens/reviews_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review eligibility requires the exact completed buyer order', () {
    const buyerId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const sellerId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final pending = _reviewOrder(
      buyerId: buyerId,
      sellerId: sellerId,
      status: AppOrderStatus.deliveredToPickup,
    );
    final completed = _reviewOrder(
      buyerId: buyerId,
      sellerId: sellerId,
      status: AppOrderStatus.completed,
    );

    expect(
      AppRepository.hasCompletedOrderForReview(
        orders: [pending],
        buyerId: buyerId,
        sellerId: sellerId,
        productId: 'product-1',
      ),
      isFalse,
    );
    expect(
      AppRepository.hasCompletedOrderForReview(
        orders: [completed],
        buyerId: buyerId,
        sellerId: sellerId,
        productId: 'product-1',
      ),
      isTrue,
    );
    expect(
      AppRepository.hasCompletedOrderForReview(
        orders: [completed],
        buyerId: buyerId,
        sellerId: buyerId,
        productId: 'product-1',
      ),
      isFalse,
    );
  });

  testWidgets('shows the authoritative review eligibility error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewsScreen(
          seller: const SellerProfile(
            id: 'seller-1',
            name: 'Продавец',
            handle: '@seller',
          ),
          sourceProduct: _reviewProduct(),
          loadReviews: (_) async => const [],
          onCreateReview:
              ({
                required sellerId,
                required productId,
                required productTitle,
                required productImage,
                required rating,
                required text,
                hasPhoto = false,
              }) async => throw const SellerReviewSubmissionException(
                'Отзыв можно оставить только после завершённой сделки',
              ),
          canCreateReview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ОСТАВИТЬ ОТЗЫВ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('СОХРАНИТЬ'));
    await tester.pumpAndSettle();

    expect(
      find.text('Отзыв можно оставить только после завершённой сделки'),
      findsOneWidget,
    );
  });

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
          onClearRecentlyViewed: () async {},
          onDeleteProduct: (id) async {},
          onProductTap: (_) {},
          onShareProduct: (_) {},
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

Product _reviewProduct() {
  return Product(
    id: 'product-1',
    title: 'Куртка',
    detailTitle: 'Куртка',
    price: '10 000 ₽',
    detailPrice: '10 000 ₽',
    priceValue: 10000,
    image: 'image.jpg',
    category: 'Одежда',
    brand: 'Test',
    size: 'M',
    color: 'Чёрный',
    condition: 'Новое',
    ownerId: 'seller-1',
    dotsOnDark: false,
  );
}

AppOrder _reviewOrder({
  required String buyerId,
  required String sellerId,
  required AppOrderStatus status,
}) {
  final timestamp = DateTime.utc(2026, 7, 17);
  return AppOrder(
    id: 'order-1',
    productId: 'product-1',
    productTitle: 'Куртка',
    productImage: '',
    productPrice: '10 000 ₽',
    productPriceValue: 10000,
    sellerId: sellerId,
    buyerId: buyerId,
    trackingNumber: '',
    deliveryService: 'СДЭК',
    deliveryAddress: 'Москва',
    recipientName: 'Покупатель',
    recipientPhone: '',
    recipientEmail: '',
    deliveryPrice: 0,
    status: status,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
