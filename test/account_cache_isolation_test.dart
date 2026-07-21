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
    final resetStart = repository.indexOf(
      'if (previousUserId != currentUserId) {',
    );
    final resetEnd = repository.indexOf(
      '_activateBlockedUserIdentity(user?.id ?? \'\');',
      resetStart,
    );
    expect(resetStart, greaterThanOrEqualTo(0));
    expect(resetEnd, greaterThan(resetStart));
    final identityReset = repository.substring(resetStart, resetEnd);
    expect(identityReset, contains('_chatMediaUrlCache.clear();'));
    expect(identityReset, contains('_knownRemoteThreadIds.clear();'));
    expect(identityReset, contains('_loadLocalUserState();'));
    expect(
      identityReset.indexOf('_loadLocalUserState();'),
      greaterThan(identityReset.indexOf('_knownRemoteThreadIds.clear();')),
    );
    expect(
      repository,
      contains('final generation = ++_authTransitionGeneration;'),
    );
    expect(repository, contains('await previous;'));
    expect(
      repository,
      contains('if (generation != _authTransitionGeneration) return;'),
    );
    expect(repository, contains('await _handleAuthState(null);'));
  });
}
