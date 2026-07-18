/// The remote chat write stages are deliberately separated because a
/// conversation row is immutable after creation while messages are append-only.
enum ChatRemoteWriteStage { ensureThread, persistMessages }

class ChatRemoteWriteFailure {
  const ChatRemoteWriteFailure({
    required this.stage,
    required this.error,
    required this.stackTrace,
  });

  final ChatRemoteWriteStage stage;
  final Object error;
  final StackTrace stackTrace;
}

class ChatRemoteWriteResult {
  const ChatRemoteWriteResult._({
    required this.succeeded,
    required this.threadConfirmed,
    this.failure,
  });

  const ChatRemoteWriteResult.success({required bool threadConfirmed})
    : this._(succeeded: true, threadConfirmed: threadConfirmed);

  const ChatRemoteWriteResult.failure({
    required bool threadConfirmed,
    required ChatRemoteWriteFailure failure,
  }) : this._(
         succeeded: false,
         threadConfirmed: threadConfirmed,
         failure: failure,
       );

  final bool succeeded;
  final bool threadConfirmed;
  final ChatRemoteWriteFailure? failure;
}

/// Coordinates append-only message writes without mutating an existing thread.
///
/// A cached thread is not automatically known to exist remotely. For that
/// case the coordinator first attempts the cheap message insert. It creates
/// the thread only when that insert fails, then retries the exact same message
/// id. The insert callback must therefore be idempotent.
class ChatRemoteWriteCoordinator {
  const ChatRemoteWriteCoordinator();

  Future<ChatRemoteWriteResult> persist({
    required bool hasMessages,
    required bool threadKnownRemote,
    required bool ensureThreadFirst,
    required Future<void> Function() ensureThread,
    required Future<void> Function() persistMessages,
  }) async {
    var threadConfirmed = threadKnownRemote;

    if (!hasMessages || ensureThreadFirst) {
      if (!threadConfirmed) {
        try {
          await ensureThread();
          threadConfirmed = true;
        } catch (error, stackTrace) {
          return ChatRemoteWriteResult.failure(
            threadConfirmed: false,
            failure: ChatRemoteWriteFailure(
              stage: ChatRemoteWriteStage.ensureThread,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        }
      }
      if (!hasMessages) {
        return ChatRemoteWriteResult.success(threadConfirmed: threadConfirmed);
      }
    }

    try {
      await persistMessages();
      return const ChatRemoteWriteResult.success(threadConfirmed: true);
    } catch (messageError, messageStackTrace) {
      if (threadConfirmed) {
        return ChatRemoteWriteResult.failure(
          threadConfirmed: true,
          failure: ChatRemoteWriteFailure(
            stage: ChatRemoteWriteStage.persistMessages,
            error: messageError,
            stackTrace: messageStackTrace,
          ),
        );
      }

      // The only legitimate reason to create a thread while sending is a
      // cache-only conversation (or a first message racing thread creation).
      // Do not do this for threads already confirmed by a server response.
      try {
        await ensureThread();
        threadConfirmed = true;
      } catch (threadError, threadStackTrace) {
        return ChatRemoteWriteResult.failure(
          threadConfirmed: false,
          failure: ChatRemoteWriteFailure(
            stage: ChatRemoteWriteStage.ensureThread,
            error: threadError,
            stackTrace: threadStackTrace,
          ),
        );
      }

      try {
        await persistMessages();
        return const ChatRemoteWriteResult.success(threadConfirmed: true);
      } catch (retryError, retryStackTrace) {
        return ChatRemoteWriteResult.failure(
          threadConfirmed: true,
          failure: ChatRemoteWriteFailure(
            stage: ChatRemoteWriteStage.persistMessages,
            error: retryError,
            stackTrace: retryStackTrace,
          ),
        );
      }
    }
  }
}
