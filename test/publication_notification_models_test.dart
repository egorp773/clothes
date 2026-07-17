import 'package:clothes/models/created_outfit.dart';
import 'package:clothes/models/profile_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'outfit publication time and counters round-trip without timezone loss',
    () {
      final publishedAt = DateTime(2026, 7, 16, 12, 45);
      final outfit = CreatedOutfit(
        id: 'outfit-1',
        authorName: 'Автор',
        authorHandle: '@author',
        authorAvatarUrl: 'https://cdn.example/avatar.jpg',
        ownerId: 'owner-1',
        photos: const [],
        items: const [],
        viewsCount: 17,
        likesCount: 4,
        publishedAt: publishedAt,
      );

      final json = outfit.toJson();
      expect(json['publishedAt'], publishedAt.toUtc().toIso8601String());
      expect(json['publishedAt'] as String, endsWith('Z'));

      final restored = CreatedOutfit.fromJson(json);
      expect(restored.publishedAt, publishedAt.toUtc());
      expect(restored.viewsCount, 17);
      expect(restored.likesCount, 4);
      expect(restored.authorAvatarUrl, 'https://cdn.example/avatar.jpg');

      final restoredFromSupabase = CreatedOutfit.fromSupabase({
        'id': 'outfit-1',
        'photos': const <String>[],
        'items': const <Map<String, dynamic>>[],
        'author_avatar_url': 'https://cdn.example/avatar.jpg',
      });
      expect(
        restoredFromSupabase.authorAvatarUrl,
        'https://cdn.example/avatar.jpg',
      );
    },
  );

  test('notification categories persist in cache and Supabase formats', () {
    const preferences = NotificationPreferences(
      pushEnabled: true,
      messagesEnabled: true,
      ordersEnabled: false,
      favoritesEnabled: true,
      promotionsEnabled: false,
      soundEnabled: false,
    );

    final cached = NotificationPreferences.fromJson(preferences.toJson());
    expect(cached.messagesEnabled, isTrue);
    expect(cached.ordersEnabled, isFalse);
    expect(cached.soundEnabled, isFalse);

    final remote = preferences.toSupabaseJson(
      '00000000-0000-0000-0000-000000000001',
    );
    expect(remote['favorites_enabled'], isTrue);
    expect(remote['promotions_enabled'], isFalse);
    expect(remote['updated_at'] as String, endsWith('Z'));
  });

  test('notification timestamps parse to a single UTC instant', () {
    final notification = ProfileNotification.fromJson({
      'id': '00000000-0000-0000-0000-000000000002',
      'title': 'Сообщение',
      'body': 'Привет',
      'created_at': '2026-07-16T17:00:00+05:00',
    });

    expect(notification.createdAt, DateTime.utc(2026, 7, 16, 12));
    expect(notification.toJson()['createdAt'] as String, endsWith('Z'));
  });
}
