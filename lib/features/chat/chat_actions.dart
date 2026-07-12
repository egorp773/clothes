import 'package:image_picker/image_picker.dart';

import '../../models/message_thread.dart';

typedef SendReplyCallback =
    Future<bool> Function(String threadId, String text, ChatMessage replyTo);

typedef SendChatImageCallback =
    Future<bool> Function(
      String threadId,
      XFile image, {
      String caption,
      ChatMessage? replyTo,
    });

typedef EditMessageCallback =
    Future<bool> Function(String threadId, String messageId, String text);

typedef DeleteMessageCallback =
    Future<bool> Function(String threadId, String messageId);

typedef UpdateThreadCallback =
    Future<bool> Function(
      String threadId, {
      bool? isPinned,
      bool? isMuted,
      bool? isArchived,
      String? title,
    });

typedef SaveDraftCallback =
    Future<void> Function(String threadId, String draft);

typedef MarkThreadReadCallback = Future<void> Function(String threadId);

/// Optional enhanced chat operations.
///
/// Keeping these operations in one object lets simple previews and widget tests
/// continue to provide only [ChatScreen.onSendMessage], while the real app can
/// opt into the full conversation experience.
class ChatActions {
  const ChatActions({
    this.sendReply,
    this.sendImage,
    this.editMessage,
    this.deleteMessage,
    this.updateThread,
    this.saveDraft,
    this.markRead,
  });

  final SendReplyCallback? sendReply;
  final SendChatImageCallback? sendImage;
  final EditMessageCallback? editMessage;
  final DeleteMessageCallback? deleteMessage;
  final UpdateThreadCallback? updateThread;
  final SaveDraftCallback? saveDraft;
  final MarkThreadReadCallback? markRead;
}
