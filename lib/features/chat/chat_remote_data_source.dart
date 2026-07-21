import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/message_thread.dart';
import 'chat_errors.dart';

class RemoteThreadCreation {
  const RemoteThreadCreation({required this.row, required this.created});

  final Map<String, dynamic> row;
  final bool created;
}

class RemoteProductMessageResult {
  const RemoteProductMessageResult({
    required this.threadRow,
    required this.messageRow,
    required this.createdThread,
    required this.createdMessage,
  });

  final Map<String, dynamic> threadRow;
  final Map<String, dynamic>? messageRow;
  final bool createdThread;
  final bool createdMessage;
}

class ChatMessagePage {
  const ChatMessagePage({required this.rows, required this.hasMore});

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
}

class ChatCursor {
  const ChatCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

class ChatRemoteDataSource {
  ChatRemoteDataSource(
    this._client, {
    this.requestTimeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;
  final Duration requestTimeout;

  Future<ChatResult<RemoteThreadCreation>> createDirectThread(
    String otherUserId,
  ) => _rpcThread(
    operation: 'create_direct_thread',
    function: 'create_or_get_direct_thread',
    params: {'p_other_user_id': otherUserId},
  );

  Future<ChatResult<RemoteThreadCreation>> createProductThread(
    String productId,
  ) => _rpcThread(
    operation: 'create_product_thread',
    function: 'create_or_get_product_thread',
    params: {'p_product_id': productId},
  );

  Future<ChatResult<RemoteThreadCreation>> createGroupThread({
    required List<String> memberIds,
    required String title,
    required String requestId,
  }) => _rpcThread(
    operation: 'create_group_thread',
    function: 'create_group_thread',
    params: {
      'p_member_ids': memberIds,
      'p_title': title,
      // Legacy production parameter name; Flutter treats this strictly as an
      // idempotency request token and trusts only the id in the returned row.
      'p_client_thread_id': requestId,
    },
  );

  Future<ChatResult<Map<String, dynamic>>> sendMessage({
    required String threadId,
    required ChatMessage message,
  }) {
    return _rpcRow(
      operation: 'send_message',
      function: 'send_chat_message',
      threadId: threadId,
      clientMessageId: message.clientMessageId,
      params: {
        'p_thread_id': threadId,
        'p_client_message_id': message.clientMessageId,
        'p_type': message.type,
        'p_text': message.text,
        'p_product': message.sharedProduct?.toJson(),
        'p_attachment': message.attachment?.toSupabaseJson(),
        'p_reply_to_id': message.replyToId.isEmpty ? null : message.replyToId,
      },
    );
  }

  Future<ChatResult<RemoteProductMessageResult>> sendProductChatMessage({
    required String productId,
    required String clientMessageId,
    required String text,
  }) async {
    try {
      final response = await _client
          .rpc(
            'send_product_chat_message',
            params: {
              'p_product_id': productId,
              'p_client_message_id': clientMessageId,
              'p_text': text,
            },
          )
          .timeout(requestTimeout);
      final envelope = _requiredRow(response);
      final rawThread = envelope['thread'];
      final rawMessage = envelope['message'];
      if (rawThread is! Map) {
        throw const FormatException('chat_product_rpc_missing_thread');
      }
      return ChatSuccess(
        RemoteProductMessageResult(
          threadRow: Map<String, dynamic>.from(rawThread),
          messageRow: rawMessage is Map
              ? Map<String, dynamic>.from(rawMessage)
              : null,
          createdThread: envelope['created_thread'] == true,
          createdMessage: envelope['created_message'] == true,
        ),
      );
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(
          error,
          stackTrace,
          operation: 'send_product_chat_message',
          clientMessageId: clientMessageId,
        ),
      );
    }
  }

  Future<ChatResult<Map<String, dynamic>?>> getMessageByClientId({
    required String threadId,
    required String clientMessageId,
  }) async {
    try {
      final response = await _client
          .rpc(
            'get_chat_message_by_client_id',
            params: {
              'p_thread_id': threadId,
              'p_client_message_id': clientMessageId,
            },
          )
          .timeout(requestTimeout);
      return ChatSuccess(_optionalRow(response));
    } catch (error, stackTrace) {
      final failure = ChatFailure.from(
        error,
        stackTrace,
        operation: 'get_message_by_client_id',
        threadId: threadId,
        clientMessageId: clientMessageId,
      );
      return ChatFailureResult(failure);
    }
  }

  Future<ChatResult<void>> acknowledgeDelivered({
    required String threadId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return const ChatSuccess(null);
    try {
      await _client
          .rpc(
            'acknowledge_chat_messages_delivered',
            params: {'p_thread_id': threadId, 'p_message_ids': messageIds},
          )
          .timeout(requestTimeout);
      return const ChatSuccess(null);
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(
          error,
          stackTrace,
          operation: 'acknowledge_delivered',
          threadId: threadId,
        ),
      );
    }
  }

  Future<ChatResult<ChatMessagePage>> fetchLatestMessages(
    String threadId, {
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('chat_messages')
          .select()
          .eq('thread_id', threadId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit + 1)
          .timeout(requestTimeout);
      final rows = _rows(response);
      final hasMore = rows.length > limit;
      final page = rows.take(limit).toList(growable: false).reversed.toList();
      return ChatSuccess(ChatMessagePage(rows: page, hasMore: hasMore));
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(
          error,
          stackTrace,
          operation: 'load_latest_messages',
          threadId: threadId,
        ),
      );
    }
  }

  Future<ChatResult<ChatMessagePage>> fetchOlderMessages(
    String threadId, {
    required ChatCursor before,
    int limit = 50,
  }) async {
    try {
      final instant = before.createdAt.toUtc().toIso8601String();
      final response = await _client
          .from('chat_messages')
          .select()
          .eq('thread_id', threadId)
          .or(
            'created_at.lt.$instant,and(created_at.eq.$instant,id.lt.${before.id})',
          )
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit + 1)
          .timeout(requestTimeout);
      final rows = _rows(response);
      final hasMore = rows.length > limit;
      final page = rows.take(limit).toList(growable: false).reversed.toList();
      return ChatSuccess(ChatMessagePage(rows: page, hasMore: hasMore));
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(
          error,
          stackTrace,
          operation: 'load_older_messages',
          threadId: threadId,
        ),
      );
    }
  }

  Future<ChatResult<List<Map<String, dynamic>>>> fetchMessagesAfter(
    String threadId, {
    required ChatCursor after,
    int limit = 200,
  }) async {
    try {
      final instant = after.createdAt.toUtc().toIso8601String();
      final response = await _client
          .from('chat_messages')
          .select()
          .eq('thread_id', threadId)
          .or(
            'created_at.gt.$instant,and(created_at.eq.$instant,id.gt.${after.id})',
          )
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .limit(limit)
          .timeout(requestTimeout);
      return ChatSuccess(_rows(response));
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(
          error,
          stackTrace,
          operation: 'gap_sync_messages',
          threadId: threadId,
        ),
      );
    }
  }

  Future<ChatResult<RemoteThreadCreation>> _rpcThread({
    required String operation,
    required String function,
    required Map<String, dynamic> params,
  }) async {
    try {
      final response = await _client
          .rpc(function, params: params)
          .timeout(requestTimeout);
      final row = _requiredRow(response);
      final created =
          row.remove('_created') == true ||
          row.remove('created') == true ||
          row.remove('was_created') == true;
      final nested = row['thread'];
      return ChatSuccess(
        RemoteThreadCreation(
          row: nested is Map ? Map<String, dynamic>.from(nested) : row,
          created: created,
        ),
      );
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(error, stackTrace, operation: operation),
      );
    }
  }

  Future<ChatResult<Map<String, dynamic>>> _rpcRow({
    required String operation,
    required String function,
    required Map<String, dynamic> params,
    String threadId = '',
    String clientMessageId = '',
  }) async {
    try {
      final response = await _client
          .rpc(function, params: params)
          .timeout(requestTimeout);
      final row = _requiredRow(response);
      final nested = row['message'];
      return ChatSuccess(
        nested is Map ? Map<String, dynamic>.from(nested) : row,
      );
    } catch (error, stackTrace) {
      return ChatFailureResult(
        ChatFailure.from(
          error,
          stackTrace,
          operation: operation,
          threadId: threadId,
          clientMessageId: clientMessageId,
        ),
      );
    }
  }

  Map<String, dynamic> _requiredRow(dynamic response) {
    final row = _optionalRow(response);
    if (row == null) throw const FormatException('chat_rpc_empty_response');
    return row;
  }

  Map<String, dynamic>? _optionalRow(dynamic response) {
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic response) => response is List
      ? response
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
      : const [];
}
