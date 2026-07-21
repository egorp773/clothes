import '../../models/message_thread.dart';
import 'chat_local_cache.dart';

class ChatMessageOutbox {
  ChatMessageOutbox(this._cache);

  final ChatLocalCache _cache;
  String _userId = '';
  final Map<String, ChatOutboxRecord> _records = {};

  int get pendingCount => _records.length;
  List<ChatOutboxRecord> get records => List.unmodifiable(_records.values);

  Future<void> activate(String userId) async {
    _userId = userId.trim();
    _records
      ..clear()
      ..addEntries(
        _cache
            .readOutbox(_userId)
            .map((record) => MapEntry(record.message.clientMessageId, record)),
      );
  }

  void deactivate() {
    _userId = '';
    _records.clear();
  }

  Iterable<ChatOutboxRecord> forThread(String threadId) =>
      _records.values.where((record) => record.threadId == threadId);

  Future<void> put(String threadId, ChatMessage message) async {
    final clientId = message.clientMessageId.trim();
    if (_userId.isEmpty || threadId.isEmpty || clientId.isEmpty) return;
    _records[clientId] = ChatOutboxRecord(
      threadId: threadId,
      message: message,
      savedAt: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> markFailed(String clientMessageId) async {
    final record = _records[clientMessageId];
    if (record == null) return;
    _records[clientMessageId] = ChatOutboxRecord(
      threadId: record.threadId,
      message: record.message.copyWith(
        isPending: false,
        hasError: true,
        status: ChatMessageDeliveryStatus.failed,
      ),
      savedAt: record.savedAt,
    );
    await _persist();
  }

  Future<void> remove(String clientMessageId) async {
    if (_records.remove(clientMessageId) == null) return;
    await _persist();
  }

  Future<void> _persist() => _cache.writeOutbox(_userId, _records.values);
}
