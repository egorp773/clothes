import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/message_thread.dart';

class ChatOutboxRecord {
  const ChatOutboxRecord({
    required this.threadId,
    required this.message,
    required this.savedAt,
  });

  final String threadId;
  final ChatMessage message;
  final DateTime savedAt;

  Map<String, dynamic> toJson() {
    final messageJson = message.toJson();
    final attachment = messageJson['attachment'];
    if (attachment is Map<String, dynamic>) {
      final url = attachment['url']?.toString() ?? '';
      if (url.startsWith('http://') || url.startsWith('https://')) {
        attachment['url'] = '';
      }
    }
    return {
      'thread_id': threadId,
      'message': messageJson,
      'saved_at': savedAt.toUtc().toIso8601String(),
    };
  }

  factory ChatOutboxRecord.fromJson(Map<String, dynamic> json) {
    return ChatOutboxRecord(
      threadId: json['thread_id'] as String? ?? '',
      message: ChatMessage.fromJson(
        Map<String, dynamic>.from(json['message'] as Map),
      ),
      savedAt:
          DateTime.tryParse(json['saved_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class ChatLocalCache {
  ChatLocalCache(this._preferences);

  static const _outboxPrefix = 'chat_outbox_v1';
  static const _maxRecords = 100;
  static const _retention = Duration(days: 14);

  final SharedPreferences _preferences;

  String _key(String userId) => '$_outboxPrefix:${userId.trim()}';

  List<ChatOutboxRecord> readOutbox(String userId) {
    final identity = userId.trim();
    if (identity.isEmpty) return const [];
    final raw = _preferences.getString(_key(identity));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final cutoff = DateTime.now().toUtc().subtract(_retention);
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ChatOutboxRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .where(
            (item) =>
                item.threadId.isNotEmpty &&
                item.message.clientMessageId.isNotEmpty &&
                item.savedAt.toUtc().isAfter(cutoff),
          )
          .take(_maxRecords)
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      // Corruption must not crash startup, but it must remain observable in
      // debug builds. Never log the serialized outbox or message text.
      debugPrint('Chat outbox decode failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const [];
    }
  }

  Future<void> writeOutbox(
    String userId,
    Iterable<ChatOutboxRecord> records,
  ) async {
    final identity = userId.trim();
    if (identity.isEmpty) return;
    final retained = records
        .where(
          (record) =>
              record.threadId.isNotEmpty &&
              record.message.clientMessageId.isNotEmpty &&
              (record.message.isPending || record.message.hasError),
        )
        .take(_maxRecords)
        .map((record) => record.toJson())
        .toList(growable: false);
    if (retained.isEmpty) {
      await _preferences.remove(_key(identity));
      return;
    }
    await _preferences.setString(_key(identity), jsonEncode(retained));
  }

  Future<void> clearOutbox(String userId) {
    final identity = userId.trim();
    if (identity.isEmpty) return Future<void>.value();
    return _preferences.remove(_key(identity));
  }
}
