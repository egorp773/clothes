import 'package:clothes/models/user_entitlements.dart';
import 'package:clothes/screens/legal_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const version = 'test-2026-07-26';
  const documents = <LegalDocumentRequirement>[
    LegalDocumentRequirement(
      type: LegalDocumentType.terms,
      version: version,
      title: 'Пользовательское соглашение',
      url: 'https://example.com/terms',
      isAccepted: false,
    ),
    LegalDocumentRequirement(
      type: LegalDocumentType.privacy,
      version: version,
      title: 'Политика обработки персональных данных',
      url: 'https://example.com/privacy',
      isAccepted: false,
    ),
    LegalDocumentRequirement(
      type: LegalDocumentType.personalData,
      version: version,
      title: 'Согласие на обработку персональных данных',
      url: 'https://example.com/personal-data',
      isAccepted: false,
    ),
    LegalDocumentRequirement(
      type: LegalDocumentType.marketing,
      version: version,
      title: 'Маркетинговые сообщения',
      url: 'https://example.com/marketing',
      isAccepted: false,
    ),
  ];

  testWidgets('shows profile fields and the three-wheel birth date picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: LegalOnboardingScreen(
          documents: documents,
          initialName: 'Анна',
          initialHandle: '@anna',
          initialCity: 'Москва',
          onSaveProfile: (name, handle, city) async => null,
          onSubmit: (intent) async => null,
        ),
      ),
    );

    expect(find.byKey(const Key('onboarding-profile-name')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-profile-handle')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-profile-city')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('legal-birth-date')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('legal-birth-date')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('birth-date-day-wheel')), findsOneWidget);
    expect(find.byKey(const Key('birth-date-month-wheel')), findsOneWidget);
    expect(find.byKey(const Key('birth-date-year-wheel')), findsOneWidget);
  });

  testWidgets('saves the profile before completing registration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];

    final acceptedVersions = <LegalDocumentType, String>{
      LegalDocumentType.terms: version,
      LegalDocumentType.privacy: version,
      LegalDocumentType.personalData: version,
      LegalDocumentType.marketing: version,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: LegalOnboardingScreen(
          documents: documents,
          initialName: 'Анна',
          initialHandle: '@anna',
          initialCity: 'Москва',
          initialIntent: RegistrationIntent(
            birthDate: DateTime(1995, 5, 17),
            acceptedVersions: acceptedVersions,
            marketingAccepted: false,
          ),
          onSaveProfile: (name, handle, city) async {
            calls.add('profile:$name:$handle:$city');
            return null;
          },
          onSubmit: (intent) async {
            calls.add('registration:${intent.birthDate.toIso8601String()}');
            return null;
          },
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('legal-onboarding-submit')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('legal-onboarding-submit')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(2));
    expect(calls.first, 'profile:Анна:@anna:Москва');
    expect(calls.last, startsWith('registration:1995-05-17'));
  });
}
