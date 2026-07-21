import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/account_deletion.dart';
import '../models/user_entitlements.dart';

class LegalOnboardingScreen extends StatefulWidget {
  const LegalOnboardingScreen({
    super.key,
    required this.documents,
    required this.onSubmit,
    this.initialIntent,
    this.isSubmitting = false,
    this.errorMessage,
    this.onRetryDocuments,
    this.onSignOut,
    this.onDeleteAccount,
    this.onExistingAccountLogin,
    this.preAuthentication = false,
  });

  final List<LegalDocumentRequirement> documents;
  final Future<String?> Function(RegistrationIntent intent) onSubmit;
  final RegistrationIntent? initialIntent;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback? onRetryDocuments;
  final Future<void> Function()? onSignOut;
  final Future<AccountDeletionResult> Function()? onDeleteAccount;
  final VoidCallback? onExistingAccountLogin;
  final bool preAuthentication;

  @override
  State<LegalOnboardingScreen> createState() => _LegalOnboardingScreenState();
}

class _LegalOnboardingScreenState extends State<LegalOnboardingScreen> {
  DateTime? _birthDate;
  final Set<LegalDocumentType> _accepted = {};
  bool _marketingAccepted = false;
  bool _submitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialIntent;
    if (initial != null) {
      _birthDate = initial.birthDate;
      _accepted.addAll(
        initial.acceptedVersions.keys.where((type) => type.isMandatory),
      );
      _marketingAccepted = initial.marketingAccepted;
    }
  }

  Map<LegalDocumentType, LegalDocumentRequirement> get _byType => {
    for (final document in widget.documents) document.type: document,
  };

  bool get _documentsReady => LegalDocumentType.values
      .where((type) => type.isMandatory)
      .every((type) => _byType[type]?.isUsable == true);

  bool get _allMandatoryAccepted => LegalDocumentType.values
      .where((type) => type.isMandatory)
      .every(_accepted.contains);

  bool get _isAdult => _birthDate != null && isAtLeast18(_birthDate!);

  bool get _canSubmit =>
      !_submitting &&
      !widget.isSubmitting &&
      _documentsReady &&
      _allMandatoryAccepted &&
      _isAdult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          widget.preAuthentication
              ? 'Перед регистрацией'
              : 'Завершите регистрацию',
        ),
        actions: [
          if (widget.onDeleteAccount != null)
            IconButton(
              key: const Key('legal-onboarding-delete-account'),
              tooltip: 'Удалить аккаунт',
              onPressed: _submitting ? null : _deleteAccount,
              icon: const Icon(Icons.delete_outline),
            ),
          if (widget.onSignOut != null)
            TextButton(
              key: const Key('legal-onboarding-sign-out'),
              onPressed: _submitting
                  ? null
                  : () async => widget.onSignOut?.call(),
              child: const Text('Выйти'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Покупать и продавать на площадке могут только пользователи старше 18 лет.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text('Дата рождения', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('legal-birth-date'),
              onPressed: _submitting ? null : _pickBirthDate,
              icon: const Icon(Icons.cake_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _birthDate == null
                      ? 'Указать дату'
                      : _formatDate(_birthDate!),
                ),
              ),
            ),
            if (_birthDate != null && !_isAdult) ...[
              const SizedBox(height: 8),
              Text(
                'Сервис доступен только пользователям 18+.',
                key: const Key('legal-underage-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            Text('Обязательные документы', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Каждый документ принимается отдельно. Сервер сохранит точную версию и время согласия.',
            ),
            const SizedBox(height: 8),
            if (!_documentsReady)
              _DocumentsUnavailable(onRetry: widget.onRetryDocuments)
            else
              for (final type in LegalDocumentType.values.where(
                (value) => value.isMandatory,
              ))
                _DocumentConsentTile(
                  key: Key('legal-consent-${type.wireName}'),
                  document: _byType[type]!,
                  value: _accepted.contains(type),
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() {
                            if (value) {
                              _accepted.add(type);
                            } else {
                              _accepted.remove(type);
                            }
                            _localError = null;
                          });
                        },
                ),
            const SizedBox(height: 18),
            Text('Маркетинговые сообщения', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (_byType[LegalDocumentType.marketing] case final marketing?)
              _DocumentConsentTile(
                key: const Key('legal-consent-marketing'),
                document: marketing,
                value: _marketingAccepted,
                optionalLabel: 'необязательно',
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _marketingAccepted = value),
              )
            else
              const Text(
                'Маркетинговое согласие недоступно и считается отклонённым.',
                key: Key('marketing-consent-unavailable'),
              ),
            if ((_localError ?? widget.errorMessage)?.isNotEmpty == true) ...[
              const SizedBox(height: 14),
              Text(
                _localError ?? widget.errorMessage!,
                key: const Key('legal-onboarding-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              key: const Key('legal-onboarding-submit'),
              onPressed: _canSubmit ? _submit : null,
              child: _submitting || widget.isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.preAuthentication
                          ? 'Продолжить к способу входа'
                          : 'Завершить регистрацию',
                    ),
            ),
            if (widget.onExistingAccountLogin != null) ...[
              const SizedBox(height: 10),
              TextButton(
                key: const Key('legal-existing-account-login'),
                onPressed: _submitting ? null : widget.onExistingAccountLogin,
                child: const Text('У меня уже есть аккаунт'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Дата рождения',
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _localError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _birthDate == null) return;
    final versions = <LegalDocumentType, String>{
      for (final type in LegalDocumentType.values.where(
        (value) => value.isMandatory,
      ))
        type: _byType[type]!.version,
      if (_byType[LegalDocumentType.marketing] case final marketing?)
        LegalDocumentType.marketing: marketing.version,
    };
    final intent = RegistrationIntent(
      birthDate: _birthDate!,
      acceptedVersions: versions,
      marketingAccepted: _marketingAccepted,
    );
    setState(() {
      _submitting = true;
      _localError = null;
    });
    try {
      final error = await widget.onSubmit(intent);
      if (!mounted) return;
      if (error != null) setState(() => _localError = error);
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError =
              'Не удалось зафиксировать согласия. Доступ остаётся закрыт.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteAccount() async {
    final callback = widget.onDeleteAccount;
    if (callback == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Удаляемые персональные данные будут удалены или обезличены. '
          'История сделок и записи, которые нужно хранить по закону, могут '
          'сохраняться ограниченный срок.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    final result = await callback();
    if (!mounted) return;
    setState(() => _submitting = false);
    final message = !result.isSuccess
        ? result.errorMessage!
        : result.isFinalized
        ? 'Аккаунт обезличен. Категории, обязательные к хранению, не удаляются до окончания установленных сроков.'
        : 'Удаление пока невозможно: ${result.deferredReasons.isEmpty ? 'есть незавершённые обязательства' : result.deferredReasons.join(', ')}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year}';
  }
}

class _DocumentConsentTile extends StatelessWidget {
  const _DocumentConsentTile({
    super.key,
    required this.document,
    required this.value,
    required this.onChanged,
    this.optionalLabel,
  });

  final LegalDocumentRequirement document;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? optionalLabel;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      onChanged: onChanged == null ? null : (next) => onChanged!(next ?? false),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(document.title),
          if (optionalLabel != null)
            Text(
              ' · $optionalLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      subtitle: TextButton(
        key: Key('legal-link-${document.type.wireName}'),
        onPressed: () => _openDocument(document.url),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
        child: Text('Версия ${document.version} · открыть'),
      ),
    );
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _DocumentsUnavailable extends StatelessWidget {
  const _DocumentsUnavailable({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Не удалось проверить действующие версии документов. Регистрация временно закрыта.',
              key: Key('legal-documents-unavailable'),
            ),
            if (onRetry != null)
              TextButton(
                key: const Key('legal-documents-retry'),
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
          ],
        ),
      ),
    );
  }
}
