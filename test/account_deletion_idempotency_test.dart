import 'package:clothes/data/app_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'account deletion retries reuse the persisted idempotency key',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var generatedKeys = 0;

      String generateKey() => 'attempt-${++generatedKeys}-abcdefghijklmnop';

      final first = await AppRepository.reuseOrCreateAccountDeletionAttemptKey(
        preferences: preferences,
        userId: 'user-1',
        createKey: generateKey,
      );
      final retry = await AppRepository.reuseOrCreateAccountDeletionAttemptKey(
        preferences: preferences,
        userId: 'user-1',
        createKey: generateKey,
      );

      expect(retry, first);
      expect(generatedKeys, 1);

      await AppRepository.clearAccountDeletionAttemptKey(
        preferences: preferences,
        userId: 'user-1',
      );
      final nextAttempt =
          await AppRepository.reuseOrCreateAccountDeletionAttemptKey(
            preferences: preferences,
            userId: 'user-1',
            createKey: generateKey,
          );

      expect(nextAttempt, isNot(first));
      expect(generatedKeys, 2);
    },
  );
}
