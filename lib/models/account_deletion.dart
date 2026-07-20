enum AccountDeletionStatus { requested, deferred, anonymized }

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.status,
    required this.requestId,
    required this.retainedCategories,
    this.deferredReasons = const [],
    this.removedCategories = const [],
    this.errorMessage,
  });

  const AccountDeletionResult.failed(String message)
    : status = AccountDeletionStatus.deferred,
      requestId = '',
      retainedCategories = const [],
      deferredReasons = const [],
      removedCategories = const [],
      errorMessage = message;

  final AccountDeletionStatus status;
  final String requestId;
  final List<String> retainedCategories;
  final List<String> deferredReasons;
  final List<String> removedCategories;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
  bool get isFinalized => status == AccountDeletionStatus.anonymized;
  bool get isDeferred => status == AccountDeletionStatus.deferred;

  factory AccountDeletionResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? '').toString().trim().toLowerCase();
    final status = switch (rawStatus) {
      'requested' || 'pending' => AccountDeletionStatus.requested,
      'blocked' ||
      'held' ||
      'deferred' ||
      'processing' ||
      'waiting_for_retention' => AccountDeletionStatus.deferred,
      'anonymized' ||
      'completed' ||
      'deleted' => AccountDeletionStatus.anonymized,
      _ when json['deleted'] == true => AccountDeletionStatus.anonymized,
      _ => throw const FormatException(
        'Deletion response has no confirmed status',
      ),
    };
    List<String> strings(Object? value) => (value as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final retained = strings(json['retained_categories']);
    return AccountDeletionResult(
      status: status,
      requestId: (json['deletion_request_id'] ?? json['request_id'] ?? '')
          .toString()
          .trim(),
      retainedCategories: List.unmodifiable(retained),
      deferredReasons: List.unmodifiable(
        strings(json['deferred_reasons'] ?? json['hold_reasons']),
      ),
      removedCategories: List.unmodifiable(strings(json['removed_categories'])),
    );
  }
}
