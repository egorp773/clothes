import 'dart:io';

import 'package:clothes/data/app_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account-scoped cache keys never overlap guest or another account', () {
    const baseKey = 'profile_v1';
    final guest = AppRepository.userScopedStorageKey(baseKey, '');
    final firstAccount = AppRepository.userScopedStorageKey(
      baseKey,
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    );
    final secondAccount = AppRepository.userScopedStorageKey(
      baseKey,
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    );

    expect(guest, 'profile_v1:guest');
    expect({guest, firstAccount, secondAccount}, hasLength(3));
    expect(
      AppRepository.userScopedStorageKey(
        baseKey,
        '  aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa  ',
      ),
      firstAccount,
    );
  });

  test('sign-out is local-first and reloads the guest-scoped state', () {
    final repository = File('lib/data/app_repository.dart').readAsStringSync();

    expect(repository, contains('auth.signOut(scope: SignOutScope.local)'));
    expect(
      repository,
      matches(
        RegExp(
          r'if \(previousUserId != currentUserId\) \{\s*'
          r'_chatMediaUrlCache\.clear\(\);\s*'
          r'_loadLocalUserState\(\);',
        ),
      ),
    );
    expect(repository, contains('await _handleAuthState(null);'));
  });
}
