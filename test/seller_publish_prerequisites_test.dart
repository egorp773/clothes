import 'package:clothes/models/app_profile.dart';
import 'package:clothes/models/user_entitlements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active account can use marketplace without legal or age gates', () {
    final entitlements = UserEntitlements.fromJson({
      'account_active': true,
      'legal_onboarding_complete': false,
      'age_verified': false,
      'birth_date': '2000-02-02',
      'seller_type': 'legal_entity',
      'seller_status': 'verified',
      'seller_moderation_status': 'clear',
      'can_publish': true,
    });

    expect(entitlements.canUseMarketplace, isTrue);
    expect(entitlements.canBuy, isTrue);
    expect(entitlements.canSell, isTrue);
    expect(entitlements.seller.type, SellerType.legalEntity);
    expect(entitlements.publishBlockReason, isNull);
  });

  test('publish reason falls back to date and seller prerequisites', () {
    final withoutDate = UserEntitlements.fromJson({
      'account_active': true,
      'can_publish': false,
    });
    expect(withoutDate.publishBlockReason, PublishBlockReason.missingBirthDate);

    final today = DateTime.now();
    final underageDate = DateTime(today.year - 17, today.month, today.day);
    final underage = UserEntitlements.fromJson({
      'account_active': true,
      'birth_date': underageDate.toIso8601String(),
      'can_publish': false,
    });
    expect(underage.publishBlockReason, PublishBlockReason.underage);

    final adult = DateTime(today.year - 20, today.month, today.day);
    final withoutType = UserEntitlements.fromJson({
      'account_active': true,
      'birth_date': adult.toIso8601String(),
      'can_publish': false,
    });
    expect(
      withoutType.publishBlockReason,
      PublishBlockReason.sellerTypeRequired,
    );
  });

  test('all four seller types round-trip through profile json', () {
    for (final type in SellerType.values) {
      final profile = AppProfile.fromJson(
        AppProfile(
          name: 'Анна',
          handle: '@anna',
          city: 'Москва',
          rating: 0,
          salesCount: 0,
          followersCount: 0,
          sellerType: type,
        ).toJson(),
      );
      expect(profile.sellerType, type);
      expect(type.displayName, isNotEmpty);
    }
  });
}
