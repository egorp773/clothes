import 'package:clothes/data/app_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'profile save diagnostics identify the failing stage and server code',
    () {
      final message = AppRepository.profileSaveFailureMessage(
        operation: 'birth_date',
        error: const PostgrestException(
          message: 'permission denied for table profiles',
          code: '42501',
        ),
      );

      expect(message, contains('Не удалось сохранить дату рождения.'));
      expect(message, contains('PROFILE_BIRTH_DATE'));
      expect(message, contains('сервер: 42501'));
      expect(message, contains('permission denied'));
    },
  );

  test('profile save diagnostics redact private backend values', () {
    final message = AppRepository.profileSaveFailureMessage(
      operation: 'private_profile',
      error: const PostgrestException(
        message:
            'failed for user@example.com at '
            'https://internal.example/profile '
            '123e4567-e89b-12d3-a456-426614174000',
        code: 'PGRST204',
      ),
    );

    expect(message, contains('PROFILE_PRIVATE_PROFILE'));
    expect(message, isNot(contains('user@example.com')));
    expect(message, isNot(contains('https://internal.example')));
    expect(message, isNot(contains('123e4567-e89b-12d3-a456-426614174000')));
  });

  test('update-then-insert skips insert when the row already exists', () async {
    var updates = 0;
    var inserts = 0;

    await AppRepository.updateThenInsert(
      update: () async {
        updates++;
        return true;
      },
      insert: () async {
        inserts++;
      },
    );

    expect(updates, 1);
    expect(inserts, 0);
  });

  test('update-then-insert creates a missing row', () async {
    var inserts = 0;

    await AppRepository.updateThenInsert(
      update: () async => false,
      insert: () async {
        inserts++;
      },
    );

    expect(inserts, 1);
  });

  test('duplicate insert race retries the owner-scoped update', () async {
    var updates = 0;

    await AppRepository.updateThenInsert(
      update: () async => ++updates == 2,
      insert: () async => throw const PostgrestException(
        message: 'duplicate key',
        code: '23505',
      ),
    );

    expect(updates, 2);
  });

  test('non-duplicate insert error is preserved', () async {
    expect(
      () => AppRepository.updateThenInsert(
        update: () async => false,
        insert: () async => throw const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
      ),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.code,
          'code',
          '42501',
        ),
      ),
    );
  });
}
