import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
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
    this.initialName = '',
    this.initialHandle = '',
    this.initialCity = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.onRetryDocuments,
    this.onSignOut,
    this.onDeleteAccount,
    this.onSaveProfile,
  });

  final List<LegalDocumentRequirement> documents;
  final Future<String?> Function(RegistrationIntent intent) onSubmit;
  final RegistrationIntent? initialIntent;
  final String initialName;
  final String initialHandle;
  final String initialCity;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback? onRetryDocuments;
  final Future<void> Function()? onSignOut;
  final Future<AccountDeletionResult> Function()? onDeleteAccount;
  final Future<String?> Function(String name, String handle, String city)?
  onSaveProfile;

  @override
  State<LegalOnboardingScreen> createState() => _LegalOnboardingScreenState();
}

class _LegalOnboardingScreenState extends State<LegalOnboardingScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  late final TextEditingController _cityController;
  DateTime? _birthDate;
  final Set<LegalDocumentType> _accepted = {};
  bool _marketingAccepted = false;
  bool _submitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _handleController = TextEditingController(text: widget.initialHandle);
    _cityController = TextEditingController(text: widget.initialCity);
    final initial = widget.initialIntent;
    if (initial != null) {
      _birthDate = initial.birthDate;
      _accepted.addAll(
        initial.acceptedVersions.keys.where((type) => type.isMandatory),
      );
      _marketingAccepted = initial.marketingAccepted;
    }
  }

  @override
  void didUpdateWidget(covariant LegalOnboardingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshInitialValue(
      _nameController,
      oldWidget.initialName,
      widget.initialName,
    );
    _refreshInitialValue(
      _handleController,
      oldWidget.initialHandle,
      widget.initialHandle,
    );
    _refreshInitialValue(
      _cityController,
      oldWidget.initialCity,
      widget.initialCity,
    );
  }

  void _refreshInitialValue(
    TextEditingController controller,
    String previous,
    String next,
  ) {
    if (previous == next ||
        (controller.text != previous && controller.text.isNotEmpty)) {
      return;
    }
    controller.text = next;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _cityController.dispose();
    super.dispose();
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

  bool get _profileReady {
    if (widget.onSaveProfile == null) return true;
    final name = _nameController.text.trim();
    final handle = _handleController.text.trim();
    return name.length >= 2 &&
        RegExp(r'^@?[A-Za-z0-9_]{3,24}$').hasMatch(handle);
  }

  bool get _canSubmit =>
      !_submitting &&
      !widget.isSubmitting &&
      _documentsReady &&
      _allMandatoryAccepted &&
      _isAdult &&
      _profileReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Завершите регистрацию'),
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
            if (widget.onSaveProfile != null) ...[
              Text(
                'Расскажите немного о себе',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Эти данные будут видны другим пользователям. Их можно изменить позже.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('onboarding-profile-name'),
                controller: _nameController,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _localError = null),
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  hintText: 'Как к вам обращаться',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('onboarding-profile-handle'),
                controller: _handleController,
                enabled: !_submitting,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _localError = null),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: '@username',
                  helperText: '3–24 символа: латиница, цифры и _',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('onboarding-profile-city'),
                controller: _cityController,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _localError = null),
                decoration: const InputDecoration(
                  labelText: 'Город',
                  hintText: 'Необязательно',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 28),
            ],
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
            Text(
              'Условия и согласия',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Примите обязательные условия. Маркетинговые сообщения — по желанию.',
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
            const SizedBox(height: 8),
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
                  : const Text('Завершить регистрацию'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _BirthDateWheelPicker(
        initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
        minimumYear: now.year - 120,
        maximumYear: now.year,
      ),
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
      final saveProfile = widget.onSaveProfile;
      if (saveProfile != null) {
        final profileError = await saveProfile(
          _nameController.text,
          _handleController.text,
          _cityController.text,
        );
        if (profileError != null) {
          if (mounted) setState(() => _localError = profileError);
          return;
        }
      }
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

class _BirthDateWheelPicker extends StatefulWidget {
  const _BirthDateWheelPicker({
    required this.initialDate,
    required this.minimumYear,
    required this.maximumYear,
  });

  final DateTime initialDate;
  final int minimumYear;
  final int maximumYear;

  @override
  State<_BirthDateWheelPicker> createState() => _BirthDateWheelPickerState();
}

class _BirthDateWheelPickerState extends State<_BirthDateWheelPicker> {
  static const _months = <String>[
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  late int _day;
  late int _month;
  late int _year;
  late final int _yearCount;
  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _yearController;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDate.day;
    _month = widget.initialDate.month;
    _year = widget.initialDate.year
        .clamp(widget.minimumYear, widget.maximumYear)
        .toInt();
    _yearCount = widget.maximumYear - widget.minimumYear + 1;
    _dayController = FixedExtentScrollController(
      initialItem: 31 * 1000 + _day - 1,
    );
    _monthController = FixedExtentScrollController(
      initialItem: 12 * 1000 + _month - 1,
    );
    _yearController = FixedExtentScrollController(
      initialItem: _yearCount * 1000 + _year - widget.minimumYear,
    );
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  int get _maximumDay => DateTime(_year, _month + 1, 0).day;

  void _keepDayValid() {
    final validDay = math.min(_day, _maximumDay);
    if (validDay == _day) return;
    _day = validDay;
    _snapDayWheel(validDay);
  }

  void _snapDayWheel(int validDay) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dayController.hasClients) {
        _dayController.jumpToItem(31 * 1000 + validDay - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                ),
                Text(
                  'Дата рождения',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('birth-date-wheel-done'),
                    onPressed: () =>
                        Navigator.pop(context, DateTime(_year, _month, _day)),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _wheel(
                    key: const Key('birth-date-day-wheel'),
                    controller: _dayController,
                    itemCount: 31,
                    labelBuilder: (index) => '${index + 1}',
                    onChanged: (index) {
                      final next = index % 31 + 1;
                      final valid = math.min(next, _maximumDay);
                      setState(() => _day = valid);
                      if (valid != next) _snapDayWheel(valid);
                    },
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: _wheel(
                    key: const Key('birth-date-month-wheel'),
                    controller: _monthController,
                    itemCount: 12,
                    labelBuilder: (index) => _months[index],
                    onChanged: (index) {
                      setState(() {
                        _month = index % 12 + 1;
                        _keepDayValid();
                      });
                    },
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _wheel(
                    key: const Key('birth-date-year-wheel'),
                    controller: _yearController,
                    itemCount: _yearCount,
                    labelBuilder: (index) => '${widget.minimumYear + index}',
                    onChanged: (index) {
                      setState(() {
                        _year = widget.minimumYear + index % _yearCount;
                        _keepDayValid();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required Key key,
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) labelBuilder,
    required ValueChanged<int> onChanged,
  }) {
    return CupertinoPicker(
      key: key,
      scrollController: controller,
      itemExtent: 44,
      looping: true,
      selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
        capStartEdge: false,
        capEndEdge: false,
        background: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      onSelectedItemChanged: onChanged,
      children: [
        for (var index = 0; index < itemCount; index++)
          Center(
            child: Text(
              labelBuilder(index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
      ],
    );
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
