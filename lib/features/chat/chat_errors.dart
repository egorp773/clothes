import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ChatFailureCode {
  unauthenticated,
  forbidden,
  threadNotFound,
  recipientNotFound,
  blocked,
  validationError,
  networkError,
  timeout,
  schemaMismatch,
  rlsDenied,
  realtimeDisconnected,
  storageError,
  unknown,
}

class ChatFailure implements Exception {
  const ChatFailure({
    required this.code,
    required this.operation,
    this.message = '',
    this.threadId = '',
    this.clientMessageId = '',
    this.postgrestCode = '',
    this.details = '',
    this.hint = '',
    this.cause,
    this.stackTrace,
  });

  final ChatFailureCode code;
  final String operation;
  final String message;
  final String threadId;
  final String clientMessageId;
  final String postgrestCode;
  final String details;
  final String hint;
  final Object? cause;
  final StackTrace? stackTrace;

  bool get isAmbiguous =>
      code == ChatFailureCode.networkError ||
      code == ChatFailureCode.timeout ||
      code == ChatFailureCode.unknown;

  String get userMessage => switch (code) {
    ChatFailureCode.unauthenticated => 'Войдите в профиль и повторите попытку.',
    ChatFailureCode.forbidden ||
    ChatFailureCode.rlsDenied => 'Нет доступа к этому диалогу.',
    ChatFailureCode.threadNotFound => 'Диалог не найден.',
    ChatFailureCode.recipientNotFound => 'Получатель больше недоступен.',
    ChatFailureCode.blocked =>
      'Отправка сообщений недоступна из-за блокировки.',
    ChatFailureCode.validationError =>
      message.trim().isEmpty ? 'Проверьте сообщение.' : message.trim(),
    ChatFailureCode.networkError || ChatFailureCode.timeout =>
      'Не удалось связаться с сервером. Проверьте подключение.',
    ChatFailureCode.schemaMismatch =>
      'Чат временно недоступен из-за несовпадения версии сервера.',
    ChatFailureCode.realtimeDisconnected =>
      'Соединение с чатом восстанавливается.',
    ChatFailureCode.storageError => 'Не удалось обработать вложение.',
    ChatFailureCode.unknown =>
      'Не удалось выполнить действие. Повторите попытку.',
  };

  @override
  String toString() => 'ChatFailure($code, operation=$operation)';

  static ChatFailure from(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    String threadId = '',
    String clientMessageId = '',
  }) {
    if (error is ChatFailure) return error;
    if (error is TimeoutException) {
      return ChatFailure(
        code: ChatFailureCode.timeout,
        operation: operation,
        threadId: threadId,
        clientMessageId: clientMessageId,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is SocketException || error is AuthRetryableFetchException) {
      return ChatFailure(
        code: ChatFailureCode.networkError,
        operation: operation,
        threadId: threadId,
        clientMessageId: clientMessageId,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is AuthException) {
      return ChatFailure(
        code: ChatFailureCode.unauthenticated,
        operation: operation,
        message: error.message,
        threadId: threadId,
        clientMessageId: clientMessageId,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is StorageException) {
      return ChatFailure(
        code: ChatFailureCode.storageError,
        operation: operation,
        message: error.message,
        threadId: threadId,
        clientMessageId: clientMessageId,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is PostgrestException) {
      final raw = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
          .toLowerCase();
      final code = switch (error.code) {
        '42501' =>
          raw.contains('rls')
              ? ChatFailureCode.rlsDenied
              : raw.contains('authentication')
              ? ChatFailureCode.unauthenticated
              : raw.contains('blocked')
              ? ChatFailureCode.blocked
              : ChatFailureCode.forbidden,
        '23503' =>
          raw.contains('recipient') || raw.contains('user')
              ? ChatFailureCode.recipientNotFound
              : ChatFailureCode.threadNotFound,
        '22023' || '23514' => ChatFailureCode.validationError,
        'P0002' =>
          raw.contains('thread')
              ? ChatFailureCode.threadNotFound
              : raw.contains('recipient') ||
                    raw.contains('seller') ||
                    raw.contains('product')
              ? ChatFailureCode.recipientNotFound
              : ChatFailureCode.unknown,
        'PGRST301' => ChatFailureCode.unauthenticated,
        '42P01' ||
        '42703' ||
        '42883' ||
        'PGRST202' ||
        'PGRST204' ||
        'PGRST205' => ChatFailureCode.schemaMismatch,
        _ =>
          raw.contains('blocked')
              ? ChatFailureCode.blocked
              : raw.contains('thread_not_found')
              ? ChatFailureCode.threadNotFound
              : raw.contains('recipient_not_found')
              ? ChatFailureCode.recipientNotFound
              : ChatFailureCode.unknown,
      };
      return ChatFailure(
        code: code,
        operation: operation,
        message: error.message,
        threadId: threadId,
        clientMessageId: clientMessageId,
        postgrestCode: error.code ?? '',
        details: error.details?.toString() ?? '',
        hint: error.hint?.toString() ?? '',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return ChatFailure(
      code: ChatFailureCode.unknown,
      operation: operation,
      threadId: threadId,
      clientMessageId: clientMessageId,
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

sealed class ChatResult<T> {
  const ChatResult();

  bool get isSuccess => this is ChatSuccess<T>;
  T? get valueOrNull => switch (this) {
    ChatSuccess<T>(:final value) => value,
    ChatFailureResult<T>() => null,
  };
  ChatFailure? get failureOrNull => switch (this) {
    ChatSuccess<T>() => null,
    ChatFailureResult<T>(:final failure) => failure,
  };
}

class ChatSuccess<T> extends ChatResult<T> {
  const ChatSuccess(this.value);
  final T value;
}

class ChatFailureResult<T> extends ChatResult<T> {
  const ChatFailureResult(this.failure);
  final ChatFailure failure;
}

void logChatFailure(ChatFailure failure, {String userId = ''}) {
  if (!kDebugMode) return;
  final fields = <String>[
    'operation=${failure.operation}',
    if (failure.threadId.isNotEmpty) 'thread_id=${failure.threadId}',
    if (failure.clientMessageId.isNotEmpty)
      'client_message_id=${failure.clientMessageId}',
    if (userId.isNotEmpty) 'user_id=$userId',
    if (failure.postgrestCode.isNotEmpty)
      'postgrest_code=${failure.postgrestCode}',
    if (failure.message.isNotEmpty) 'message=${failure.message}',
    if (failure.details.isNotEmpty) 'details=${failure.details}',
    if (failure.hint.isNotEmpty) 'hint=${failure.hint}',
  ];
  debugPrint('Chat failure: ${fields.join(', ')}');
  if (failure.stackTrace != null) {
    debugPrintStack(stackTrace: failure.stackTrace);
  }
}
