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

  /// A support-friendly message that is safe to show in the UI.
  ///
  /// [userMessage] explains what the person can do, while the compact code and
  /// sanitized server text preserve enough context to diagnose a failed send
  /// from a screenshot. Credentials, URLs and common personal identifiers are
  /// redacted before any backend text is exposed.
  String get diagnosticMessage {
    final operationCode = _chatDiagnosticIdentifier(
      operation,
      fallback: 'chat',
    );
    final failureCode = _chatDiagnosticIdentifier(
      code.name,
      fallback: 'unknown',
    );
    final diagnostic = <String>[
      'CHAT_${failureCode.toUpperCase()}',
      'операция: $operationCode',
      if (postgrestCode.trim().isNotEmpty)
        'сервер: ${_chatDiagnosticIdentifier(postgrestCode, fallback: 'unknown')}',
    ];
    final backendMessage = _sanitizedBackendMessage;
    if (backendMessage.isNotEmpty) diagnostic.add('детали: $backendMessage');
    return '$userMessage\nКод: ${diagnostic.join(' · ')}';
  }

  String get _sanitizedBackendMessage {
    final candidates = <String>[
      message,
      details,
      hint,
      if (cause != null) cause.toString(),
    ];
    for (final candidate in candidates) {
      final sanitized = sanitizeChatDiagnosticText(candidate);
      if (sanitized.isNotEmpty && sanitized != 'null') return sanitized;
    }
    return '';
  }

  String get userMessage => switch (code) {
    ChatFailureCode.unauthenticated => 'Войдите в профиль и повторите попытку.',
    ChatFailureCode.forbidden ||
    ChatFailureCode.rlsDenied => 'Нет доступа к этому диалогу.',
    ChatFailureCode.threadNotFound => 'Диалог не найден.',
    ChatFailureCode.recipientNotFound => 'Получатель больше недоступен.',
    ChatFailureCode.blocked =>
      'Отправка сообщений недоступна из-за блокировки.',
    ChatFailureCode.validationError =>
      _knownChatBackendMessage(message) ??
          'Проверьте данные сообщения и повторите попытку.',
    ChatFailureCode.networkError || ChatFailureCode.timeout =>
      'Не удалось связаться с сервером. Проверьте подключение.',
    ChatFailureCode.schemaMismatch =>
      'Чат временно недоступен из-за несовпадения версии сервера.',
    ChatFailureCode.realtimeDisconnected =>
      'Соединение с чатом восстанавливается.',
    ChatFailureCode.storageError => 'Не удалось обработать вложение.',
    ChatFailureCode.unknown =>
      _knownChatBackendMessage(message) ??
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
        '55000' =>
          raw.contains('product_not_available')
              ? ChatFailureCode.validationError
              : ChatFailureCode.unknown,
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

/// Builds a concrete fallback for chat callbacks that returned `false`
/// without throwing. The repository can replace it with [ChatFailure]'s richer
/// [ChatFailure.diagnosticMessage] through `ChatActions.errorMessage`.
String chatOperationFailureMessage({
  required String fallback,
  required String operation,
  String? repositoryMessage,
  Object? error,
  StackTrace? stackTrace,
}) {
  if (error != null) {
    return ChatFailure.from(
      error,
      stackTrace ?? StackTrace.current,
      operation: operation,
    ).diagnosticMessage;
  }
  final repositoryText = repositoryMessage?.trim() ?? '';
  if (repositoryText.isNotEmpty) return repositoryText;
  final operationCode = _chatDiagnosticIdentifier(
    operation,
    fallback: 'chat_ui',
  ).toUpperCase();
  return '${fallback.trim()}\nКод: CHAT_UI_$operationCode';
}

String? _knownChatBackendMessage(String rawMessage) {
  final normalized = rawMessage.trim().toLowerCase();
  if (normalized.contains('cannot_message_own_product')) {
    return 'Это ваше объявление — чат с самим собой открыть нельзя.';
  }
  if (normalized.contains('product_not_available')) {
    return 'Объявление больше недоступно.';
  }
  if (normalized.contains('message_text_required')) {
    return 'Введите текст сообщения.';
  }
  if (normalized.contains('message_text_too_long')) {
    return 'Сообщение слишком длинное.';
  }
  if (normalized.contains('unsupported_message_type')) {
    return 'Этот тип сообщения не поддерживается.';
  }
  if (normalized.contains('chat_attachment') ||
      normalized.contains('attachment_')) {
    return 'Вложение не прошло проверку сервера.';
  }
  return null;
}

String _chatDiagnosticIdentifier(String value, {required String fallback}) {
  final normalized = value
      .trim()
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[_\.-]+|[_\.-]+$'), '');
  if (normalized.isEmpty) return fallback;
  return normalized.length <= 64 ? normalized : normalized.substring(0, 64);
}

/// Removes credentials and common personal identifiers from diagnostics that
/// are shown in the UI or copied into a support report.
String sanitizeChatDiagnosticText(String value) {
  var result = value
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
      .replaceAll(
        RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer [скрыто]',
      )
      .replaceAll(
        RegExp(
          r'\b[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b',
        ),
        '[токен скрыт]',
      )
      .replaceAll(
        RegExp(r'\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b'),
        '[email скрыт]',
      )
      .replaceAll(RegExp(r'\+?\d[\d\s().-]{8,}\d'), '[телефон скрыт]')
      .replaceAll(
        RegExp(
          r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
          caseSensitive: false,
        ),
        '[id скрыт]',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const maxLength = 180;
  if (result.length > maxLength) {
    result = '${result.substring(0, maxLength - 1).trimRight()}…';
  }
  return result;
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
