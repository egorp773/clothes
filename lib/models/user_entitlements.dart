enum LegalDocumentType {
  terms('terms', true),
  privacy('privacy_policy', true),
  personalData('personal_data_consent', true),
  marketing('marketing_consent', false);

  const LegalDocumentType(this.wireName, this.isMandatory);

  final String wireName;
  final bool isMandatory;

  static LegalDocumentType? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return switch (normalized) {
      'terms' ||
      'terms_of_service' ||
      'user_agreement' => LegalDocumentType.terms,
      'privacy' || 'privacy_policy' => LegalDocumentType.privacy,
      'personal_data' ||
      'personal_data_consent' ||
      'pd_consent' => LegalDocumentType.personalData,
      'marketing' || 'marketing_consent' => LegalDocumentType.marketing,
      _ => null,
    };
  }
}

class LegalDocumentRequirement {
  const LegalDocumentRequirement({
    required this.type,
    required this.version,
    required this.title,
    required this.url,
    required this.isAccepted,
  });

  final LegalDocumentType type;
  final String version;
  final String title;
  final String url;
  final bool isAccepted;

  bool get isUsable => version.trim().isNotEmpty && url.trim().isNotEmpty;

  LegalDocumentRequirement copyWith({bool? isAccepted}) {
    return LegalDocumentRequirement(
      type: type,
      version: version,
      title: title,
      url: url,
      isAccepted: isAccepted ?? this.isAccepted,
    );
  }

  factory LegalDocumentRequirement.fromJson(Map<String, dynamic> json) {
    final type = LegalDocumentType.tryParse(
      json['document_type'] ?? json['type'] ?? json['slug'],
    );
    if (type == null) {
      throw const FormatException('Unknown legal document type');
    }
    final version = (json['version'] ?? json['version_number'] ?? '')
        .toString()
        .trim();
    final title = (json['title'] ?? _defaultTitle(type)).toString().trim();
    final url =
        (json['url'] ??
                json['public_url'] ??
                json['document_url'] ??
                json['content_url'] ??
                '')
            .toString()
            .trim();
    return LegalDocumentRequirement(
      type: type,
      version: version,
      title: title,
      url: url,
      isAccepted:
          json['accepted'] == true ||
          json['is_accepted'] == true ||
          json['consented'] == true,
    );
  }

  static String _defaultTitle(LegalDocumentType type) => switch (type) {
    LegalDocumentType.terms => 'Пользовательское соглашение',
    LegalDocumentType.privacy => 'Политика обработки персональных данных',
    LegalDocumentType.personalData =>
      'Согласие на обработку персональных данных',
    LegalDocumentType.marketing => 'Согласие на маркетинговые сообщения',
  };
}

class RegistrationIntent {
  RegistrationIntent({
    required this.birthDate,
    required Map<LegalDocumentType, String> acceptedVersions,
    required this.marketingAccepted,
  }) : acceptedVersions = Map.unmodifiable(acceptedVersions);

  final DateTime birthDate;
  final Map<LegalDocumentType, String> acceptedVersions;
  final bool marketingAccepted;

  bool get isAdult => isAtLeast18(birthDate);

  bool get hasAllMandatoryDocuments => LegalDocumentType.values
      .where((type) => type.isMandatory)
      .every((type) => acceptedVersions[type]?.trim().isNotEmpty == true);

  bool get isValid => isAdult && hasAllMandatoryDocuments;

  Map<String, dynamic> toRequestBody() {
    final mandatory = <Map<String, dynamic>>[
      for (final type in LegalDocumentType.values.where(
        (value) => value.isMandatory,
      ))
        {
          'document_type': type.wireName,
          'version': acceptedVersions[type],
          'accepted': true,
        },
    ];
    final marketingVersion =
        acceptedVersions[LegalDocumentType.marketing]?.trim() ?? '';
    return {
      'birth_date': _isoDate(birthDate),
      'consents': [
        ...mandatory,
        if (marketingAccepted && marketingVersion.isNotEmpty)
          {
            'document_type': LegalDocumentType.marketing.wireName,
            'version': marketingVersion,
            'accepted': true,
          },
      ],
    };
  }
}

bool isAtLeast18(DateTime birthDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final eighteenthBirthday = DateTime(
    birthDate.year + 18,
    birthDate.month,
    birthDate.day,
  );
  final currentDate = DateTime(today.year, today.month, today.day);
  return !eighteenthBirthday.isAfter(currentDate);
}

enum SellerType {
  privateIndividual('private_individual'),
  selfEmployed('self_employed'),
  individualEntrepreneur('individual_entrepreneur'),
  legalEntity('legal_entity');

  const SellerType(this.wireName);

  final String wireName;

  bool get isEnabledInCurrentRelease => this == privateIndividual;

  static SellerType? tryParse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return SellerType.values
        .where((type) => type.wireName == normalized)
        .firstOrNull;
  }
}

enum SellerAccountStatus {
  absent,
  pending,
  verified,
  blocked;

  static SellerAccountStatus parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return SellerAccountStatus.values.firstWhere(
      (status) => status.name == normalized,
      orElse: () => SellerAccountStatus.absent,
    );
  }
}

enum SellerVerificationStatus {
  notStarted,
  pending,
  verified,
  reviewRequired,
  rejected;

  String get wireName => switch (this) {
    SellerVerificationStatus.notStarted => 'not_started',
    SellerVerificationStatus.pending => 'pending',
    SellerVerificationStatus.verified => 'verified',
    SellerVerificationStatus.reviewRequired => 'review_required',
    SellerVerificationStatus.rejected => 'rejected',
  };

  static SellerVerificationStatus parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'verification_required') {
      return SellerVerificationStatus.reviewRequired;
    }
    return SellerVerificationStatus.values.firstWhere(
      (status) => status.wireName == normalized,
      orElse: () => SellerVerificationStatus.notStarted,
    );
  }
}

enum SellerModerationStatus {
  clear,
  review,
  restricted,
  blocked;

  static SellerModerationStatus parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'approved' || normalized == 'active') {
      return SellerModerationStatus.clear;
    }
    if (normalized == 'pending' || normalized == 'under_review') {
      return SellerModerationStatus.review;
    }
    return SellerModerationStatus.values.firstWhere(
      (status) => status.name == normalized,
      orElse: () => SellerModerationStatus.review,
    );
  }
}

class SellerEntitlement {
  const SellerEntitlement({
    required this.type,
    required this.status,
    required this.verificationStatus,
    required this.moderationStatus,
    required this.riskScore,
    required this.salesBlocked,
    required this.publicationsHidden,
    required this.serverCanPublish,
  });

  const SellerEntitlement.absent()
    : type = null,
      status = SellerAccountStatus.absent,
      verificationStatus = SellerVerificationStatus.notStarted,
      moderationStatus = SellerModerationStatus.review,
      riskScore = 0,
      salesBlocked = true,
      publicationsHidden = false,
      serverCanPublish = false;

  final SellerType? type;
  final SellerAccountStatus status;
  final SellerVerificationStatus verificationStatus;
  final SellerModerationStatus moderationStatus;
  final int riskScore;
  final bool salesBlocked;
  final bool publicationsHidden;
  final bool serverCanPublish;

  bool get canSell =>
      serverCanPublish &&
      type?.isEnabledInCurrentRelease == true &&
      status == SellerAccountStatus.verified &&
      verificationStatus == SellerVerificationStatus.verified &&
      moderationStatus == SellerModerationStatus.clear &&
      !salesBlocked &&
      !publicationsHidden;

  factory SellerEntitlement.fromJson(Map<String, dynamic> json) {
    return SellerEntitlement(
      type: SellerType.tryParse(json['seller_type'] ?? json['type']),
      status: SellerAccountStatus.parse(json['status']),
      verificationStatus: SellerVerificationStatus.parse(
        json['verification_status'],
      ),
      moderationStatus: SellerModerationStatus.parse(json['moderation_status']),
      riskScore:
          (json['seller_risk_score'] as num?)?.toInt() ??
          (json['risk_score'] as num?)?.toInt() ??
          0,
      salesBlocked:
          json['sales_blocked'] == true ||
          json['is_blocked'] == true ||
          json['blocked'] == true,
      publicationsHidden: json['publications_hidden'] == true,
      serverCanPublish:
          json['seller_can_publish'] == true || json['can_publish'] == true,
    );
  }
}

class UserEntitlements {
  UserEntitlements({
    required this.isResolved,
    required this.legalOnboardingComplete,
    required this.ageVerified,
    required this.birthDate,
    required this.verificationMethod,
    required this.documents,
    required this.seller,
  });

  UserEntitlements.unavailable()
    : isResolved = false,
      legalOnboardingComplete = false,
      ageVerified = false,
      birthDate = null,
      verificationMethod = '',
      documents = const [],
      seller = const SellerEntitlement.absent();

  final bool isResolved;
  final bool legalOnboardingComplete;
  final bool ageVerified;
  final DateTime? birthDate;
  final String verificationMethod;
  final List<LegalDocumentRequirement> documents;
  final SellerEntitlement seller;

  bool get hasUsableMandatoryDocuments {
    for (final type in LegalDocumentType.values.where(
      (value) => value.isMandatory,
    )) {
      final matching = documents.where((document) => document.type == type);
      if (matching.length != 1 || !matching.single.isUsable) return false;
    }
    return true;
  }

  bool get allMandatoryDocumentsAccepted =>
      hasUsableMandatoryDocuments &&
      documents
          .where((document) => document.type.isMandatory)
          .every((document) => document.isAccepted);

  bool get canUseMarketplace =>
      isResolved &&
      legalOnboardingComplete &&
      allMandatoryDocumentsAccepted &&
      ageVerified;

  bool get canBuy => canUseMarketplace;
  bool get canSell => canUseMarketplace && seller.canSell;

  factory UserEntitlements.fromJson(Map<String, dynamic> source) {
    final json = _unwrapMap(source);
    final rawDocuments =
        json['legal_documents'] ??
        json['documents'] ??
        json['document_versions'] ??
        const <dynamic>[];
    final documents = <LegalDocumentRequirement>[];
    if (rawDocuments is List) {
      for (final raw in rawDocuments.whereType<Map>()) {
        try {
          documents.add(
            LegalDocumentRequirement.fromJson(Map<String, dynamic>.from(raw)),
          );
        } on FormatException {
          // Unknown document types never broaden access.
        }
      }
    }

    final sellerRaw = json['seller_account'] ?? json['seller'];
    final seller = sellerRaw is Map
        ? SellerEntitlement.fromJson(Map<String, dynamic>.from(sellerRaw))
        : json['seller_account_id'] != null ||
              json['seller_type'] != null ||
              json['seller_status'] != null
        ? SellerEntitlement.fromJson({
            'seller_type': json['seller_type'],
            'status': json['seller_status'],
            'verification_status': json['seller_verification_status'],
            'moderation_status': json['seller_moderation_status'],
            'seller_can_publish': json['seller_can_publish'],
            'seller_risk_score': json['seller_risk_score'],
            'sales_blocked': json['sales_blocked'],
            'publications_hidden': json['publications_hidden'],
          })
        : const SellerEntitlement.absent();
    final ageRaw = json['age'] is Map
        ? Map<String, dynamic>.from(json['age'] as Map)
        : json;
    final legalRaw = json['legal'] is Map
        ? Map<String, dynamic>.from(json['legal'] as Map)
        : json;
    final legalComplete =
        legalRaw['legal_onboarding_complete'] == true ||
        legalRaw['mandatory_consents_complete'] == true ||
        legalRaw['completed'] == true;
    final birthDate = DateTime.tryParse(
      (ageRaw['birth_date'] ?? '').toString(),
    );

    return UserEntitlements(
      isResolved: true,
      legalOnboardingComplete: legalComplete,
      ageVerified: ageRaw['age_verified'] == true,
      birthDate: birthDate,
      verificationMethod: (ageRaw['verification_method'] ?? '')
          .toString()
          .trim(),
      documents: List.unmodifiable(documents),
      seller: seller,
    );
  }

  static Map<String, dynamic> _unwrapMap(Map<String, dynamic> source) {
    final payload = source['entitlements'] ?? source['data'];
    return payload is Map ? Map<String, dynamic>.from(payload) : source;
  }
}

String _isoDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
