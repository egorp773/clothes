import 'package:clothes/models/profile_feature.dart';
import 'package:clothes/screens/profile_feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = DeliveryProfile(
    fullName: 'Иван Иванов',
    phone: '+7 999 123-45-67',
    email: 'ivan@example.test',
    city: 'Москва',
    address: 'ул. Домашняя, 1',
    pickupProvider: 'cdek',
    pickupPointId: 'cdek-42',
    pickupPointName: 'СДЭК на Тверской',
    pickupPointAddress: 'ул. Тверская, 10',
  );

  test('delivery profile keeps street address and pickup point separate', () {
    final local = DeliveryProfile.fromJson(profile.toJson());
    final remote = DeliveryProfile.fromJson(profile.toSupabaseJson('user-id'));

    for (final restored in [local, remote]) {
      expect(restored.address, 'ул. Домашняя, 1');
      expect(restored.pickupProvider, 'cdek');
      expect(restored.pickupPointId, 'cdek-42');
      expect(restored.pickupPointAddress, 'ул. Тверская, 10');
    }
  });

  testWidgets('address screen saves address without overwriting pickup data', (
    tester,
  ) async {
    DeliveryProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAddressesScreen(
          profile: profile,
          onSave: (next) async {
            saved = next;
          },
          onOpenCatalog: () {},
        ),
      ),
    );

    final saveButton = find.byKey(const Key('save-profile-address'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.address, 'ул. Домашняя, 1');
    expect(saved?.pickupPointId, 'cdek-42');
    expect(saved?.pickupPointAddress, 'ул. Тверская, 10');

    final clearButton = find.byKey(const Key('clear-saved-pickup-point'));
    await tester.ensureVisible(clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(saved?.address, 'ул. Домашняя, 1');
    expect(saved?.pickupProvider, isEmpty);
    expect(saved?.pickupPointId, isEmpty);
    expect(saved?.pickupPointAddress, isEmpty);
  });

  testWidgets('address screen explains a save failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAddressesScreen(
          profile: profile,
          onSave: (_) async => throw StateError('offline'),
          onOpenCatalog: () {},
        ),
      ),
    );

    final saveButton = find.byKey(const Key('save-profile-address'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Не удалось сохранить адрес. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  });
}
