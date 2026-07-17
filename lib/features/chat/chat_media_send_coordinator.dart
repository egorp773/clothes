import '../../models/message_thread.dart';

typedef ChatMediaThreadPreflight = Future<bool> Function();
typedef ChatMediaUpload = Future<ChatAttachment?> Function();
typedef ChatMediaPersist = Future<bool> Function(ChatAttachment attachment);
typedef ChatMediaFailureAction =
    Future<void> Function(ChatAttachment attachment);

/// Keeps remote chat media operations in the only safe order:
/// create/verify the thread, upload, then persist the referencing message.
///
/// Once an object has been uploaded, every unsuccessful persistence path marks
/// the local attempt as failed and removes the now-unreferenced object. Both
/// failure actions are best-effort and cannot mask the original send result.
class ChatMediaSendCoordinator {
  const ChatMediaSendCoordinator();

  ChatAttachment localFailureAttachment(
    ChatAttachment uploaded, {
    required String localUrl,
  }) {
    return uploaded.copyWith(url: localUrl.trim(), bucket: '', storagePath: '');
  }

  Future<bool> send({
    required ChatMediaThreadPreflight ensureRemoteThread,
    required ChatMediaUpload upload,
    required ChatMediaPersist persist,
    required ChatMediaFailureAction markFailed,
    required ChatMediaFailureAction cleanup,
  }) async {
    try {
      if (!await ensureRemoteThread()) return false;
    } catch (_) {
      return false;
    }

    ChatAttachment? attachment;
    try {
      attachment = await upload();
    } catch (_) {
      return false;
    }
    if (attachment == null) return false;
    if (attachment.url.trim().isEmpty) {
      await _bestEffort(() => cleanup(attachment!));
      return false;
    }

    var persisted = false;
    try {
      persisted = await persist(attachment);
    } catch (_) {
      persisted = false;
    }
    if (persisted) return true;

    await _bestEffort(() => markFailed(attachment!));
    await _bestEffort(() => cleanup(attachment!));
    return false;
  }

  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // A secondary recovery failure must never turn a failed send into an
      // exception or prevent the remaining recovery action from running.
    }
  }
}
