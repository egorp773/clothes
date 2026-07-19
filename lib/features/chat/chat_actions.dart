import 'package:image_picker/image_picker.dart';

import '../../models/message_thread.dart';

typedef SendChatTextCallback =
    Future<bool> Function(String threadId, String text);

typedef SendPendingChatTextCallback =
    Future<bool> Function(String threadId, ChatMessage pendingMessage);

typedef RetryChatTextCallback =
    Future<bool> Function(String threadId, ChatMessage failedMessage);

typedef RetryChatMediaCallback =
    Future<bool> Function(String threadId, ChatMessage failedMessage);

typedef SendReplyCallback =
    Future<bool> Function(String threadId, String text, ChatMessage replyTo);

typedef SendChatImageCallback =
    Future<bool> Function(
      String threadId,
      XFile image, {
      String caption,
      ChatMessage? replyTo,
    });

typedef SendChatMediaCallback =
    Future<bool> Function(
      String threadId,
      XFile media, {
      required ChatMediaKind kind,
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
typedef SetChatVisibilityCallback =
    void Function(String threadId, bool isVisible);

/// Optional enhanced chat operations.
///
/// Keeping these operations in one object lets simple previews and widget tests
/// continue to provide only [ChatScreen.onSendMessage], while the real app can
/// opt into the full conversation experience.
class ChatActions {
  const ChatActions({
    this.sendText,
    this.sendPendingText,
    this.retryText,
    this.retryMedia,
    this.sendReply,
    this.sendImage,
    this.sendMedia,
    this.editMessage,
    this.deleteMessage,
    this.updateThread,
    this.saveDraft,
    this.markRead,
    this.setVisibility,
  });

  final SendChatTextCallback? sendText;
  final SendPendingChatTextCallback? sendPendingText;
  final RetryChatTextCallback? retryText;
  final RetryChatMediaCallback? retryMedia;
  final SendReplyCallback? sendReply;
  final SendChatImageCallback? sendImage;
  final SendChatMediaCallback? sendMedia;
  final EditMessageCallback? editMessage;
  final DeleteMessageCallback? deleteMessage;
  final UpdateThreadCallback? updateThread;
  final SaveDraftCallback? saveDraft;
  final MarkThreadReadCallback? markRead;
  final SetChatVisibilityCallback? setVisibility;
}
