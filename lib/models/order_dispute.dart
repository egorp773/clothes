enum DisputeReason {
  notReceived('not_received'),
  wrongItem('wrong_item'),
  fake('fake'),
  hiddenDamage('hidden_damage'),
  descriptionMismatch('description_mismatch'),
  other('other');

  const DisputeReason(this.wireName);

  final String wireName;
}

enum OrderDisputeStatus {
  open,
  underReview,
  resolvedBuyer,
  resolvedSeller,
  rejected,
  cancelled;

  String get wireName => switch (this) {
    OrderDisputeStatus.open => 'open',
    OrderDisputeStatus.underReview => 'under_review',
    OrderDisputeStatus.resolvedBuyer => 'resolved_buyer',
    OrderDisputeStatus.resolvedSeller => 'resolved_seller',
    OrderDisputeStatus.rejected => 'rejected',
    OrderDisputeStatus.cancelled => 'cancelled',
  };

  static OrderDisputeStatus parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return OrderDisputeStatus.values.firstWhere(
      (status) => status.wireName == normalized,
      orElse: () => OrderDisputeStatus.open,
    );
  }
}

enum DisputeEvidenceType {
  image,
  video,
  document,
  chatMessage,
  tracking,
  text;

  String get wireName => switch (this) {
    DisputeEvidenceType.chatMessage => 'chat_message',
    _ => name,
  };

  static DisputeEvidenceType parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return DisputeEvidenceType.values.firstWhere(
      (type) => type.wireName == normalized,
      orElse: () => DisputeEvidenceType.text,
    );
  }
}

class DisputeEvidenceReference {
  const DisputeEvidenceReference({
    required this.type,
    required this.reference,
    this.note = '',
  });

  final DisputeEvidenceType type;
  final String reference;
  final String note;

  factory DisputeEvidenceReference.fromJson(Map<String, dynamic> json) {
    return DisputeEvidenceReference(
      type: DisputeEvidenceType.parse(json['evidence_type'] ?? json['type']),
      reference: (json['storage_path'] ?? json['reference'] ?? '')
          .toString()
          .trim(),
      note: (json['note'] ?? '').toString().trim(),
    );
  }
}

class OrderDispute {
  const OrderDispute({
    required this.id,
    required this.orderId,
    required this.createdBy,
    required this.reason,
    required this.description,
    required this.evidence,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String createdBy;
  final DisputeReason reason;
  final String description;
  final List<DisputeEvidenceReference> evidence;
  List<String> get evidencePaths => evidence
      .map((item) => item.reference)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final OrderDisputeStatus status;
  final DateTime createdAt;

  factory OrderDispute.fromJson(Map<String, dynamic> json) {
    final reasonValue = (json['reason'] ?? '').toString();
    return OrderDispute(
      id: (json['id'] ?? '').toString(),
      orderId: (json['order_id'] ?? '').toString(),
      createdBy: (json['created_by'] ?? '').toString(),
      reason: DisputeReason.values.firstWhere(
        (reason) => reason.wireName == reasonValue,
        orElse: () => DisputeReason.other,
      ),
      description: (json['description'] ?? '').toString(),
      evidence: (json['evidence'] as List<dynamic>? ?? const [])
          .map((value) {
            if (value is Map) {
              return DisputeEvidenceReference.fromJson(
                Map<String, dynamic>.from(value),
              );
            }
            return DisputeEvidenceReference(
              type: DisputeEvidenceType.text,
              reference: value.toString(),
            );
          })
          .toList(growable: false),
      status: OrderDisputeStatus.parse(json['status']),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString())?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
