import 'package:clothes/models/app_profile.dart';
import 'package:clothes/screens/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('prefills identity and saves profile without a birth date', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? savedName;
    String? savedHandle;
    AppProfile? savedProfile;

    await tester.pumpWidget(
      MaterialApp(
        home: EditProfileScreen(
          profile: const AppProfile(
            name: 'Ева Смирнова',
            handle: '@eva_style',
            city: 'Москва',
            rating: 4.8,
            salesCount: 3,
            followersCount: 24,
          ),
          accountEmail: '',
          isSignedIn: false,
          onUpdateIdentity:
              ({required String name, required String handle}) async {
                savedName = name;
                savedHandle = handle;
                return null;
              },
          onSave: (profile, avatar) async {
            savedProfile = profile;
            return null;
          },
          onConfirmEmail: (email) async => null,
          onDeleteAccount: () async => null,
        ),
      ),
    );

    expect(find.text('Редактировать профиль'), findsOneWidget);
    expect(find.text('Изменить фото'), findsOneWidget);
    expect(find.text('Ева'), findsOneWidget);
    expect(find.text('Смирнова'), findsOneWidget);
    expect(find.text('eva_style'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(savedName, 'Ева Смирнова');
    expect(savedHandle, '@eva_style');
    expect(savedProfile?.birthDate, isEmpty);
    expect(savedProfile?.city, 'Москва');
  });
}
