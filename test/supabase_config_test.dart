import 'package:clothes/core/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupabaseConfig', () {
    test('accepts an HTTPS backend with a client key', () {
      expect(
        SupabaseConfig.isValidConfiguration(
          url: 'https://project.supabase.co',
          anonKey: 'public-client-key',
        ),
        isTrue,
      );
    });

    test('rejects missing or non-HTTPS backend configuration', () {
      expect(
        SupabaseConfig.isValidConfiguration(url: '', anonKey: 'key'),
        isFalse,
      );
      expect(
        SupabaseConfig.isValidConfiguration(
          url: 'http://project.supabase.co',
          anonKey: 'key',
        ),
        isFalse,
      );
      expect(
        SupabaseConfig.isValidConfiguration(
          url: 'https://project.supabase.co',
          anonKey: '   ',
        ),
        isFalse,
      );
    });
  });
}
