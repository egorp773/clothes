import 'package:flutter/material.dart';

import '../models/user_entitlements.dart';

class SellerActivationScreen extends StatefulWidget {
  const SellerActivationScreen({
    super.key,
    required this.entitlements,
    required this.onRequestActivation,
    required this.onRefresh,
  });

  final UserEntitlements entitlements;
  final Future<String?> Function() onRequestActivation;
  final Future<void> Function() onRefresh;

  @override
  State<SellerActivationScreen> createState() => _SellerActivationScreenState();
}

class _SellerActivationScreenState extends State<SellerActivationScreen> {
  bool _loading = false;
  String? _error;

  SellerEntitlement get _seller => widget.entitlements.seller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль продавца')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Платформа предоставляет IT-сервис. Вещь продаёт пользователь напрямую покупателю.',
            ),
            const SizedBox(height: 20),
            ListTile(
              key: const Key('seller-type-private-individual'),
              leading: const Icon(Icons.radio_button_checked),
              title: const Text('Частное физическое лицо'),
              subtitle: const Text(
                'Продажа собственных вещей без профессиональной торговли',
              ),
            ),
            for (final type in SellerType.values.where(
              (value) => value != SellerType.privateIndividual,
            ))
              ListTile(
                key: Key('seller-type-${type.wireName}'),
                enabled: false,
                leading: const Icon(Icons.radio_button_unchecked),
                title: Text(_sellerTypeTitle(type)),
                subtitle: const Text('В этой версии приложения недоступно'),
              ),
            const SizedBox(height: 16),
            _SellerStatusCard(seller: _seller),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('seller-activation-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            if (_seller.status == SellerAccountStatus.absent)
              FilledButton(
                key: const Key('seller-activation-submit'),
                onPressed: _loading ? null : _request,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Отправить заявку'),
              )
            else
              OutlinedButton(
                key: const Key('seller-activation-refresh'),
                onPressed: _loading ? null : _refresh,
                child: const Text('Обновить статус'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _request() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await widget.onRequestActivation();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
    if (error == null) await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sellerTypeTitle(SellerType type) => switch (type) {
    SellerType.privateIndividual => 'Частное физическое лицо',
    SellerType.selfEmployed => 'Самозанятый',
    SellerType.individualEntrepreneur => 'Индивидуальный предприниматель',
    SellerType.legalEntity => 'Юридическое лицо',
  };
}

class _SellerStatusCard extends StatelessWidget {
  const _SellerStatusCard({required this.seller});

  final SellerEntitlement seller;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (seller.status) {
      SellerAccountStatus.absent => (
        'Продавец не активирован',
        'Для публикации нужна отдельная заявка.',
      ),
      SellerAccountStatus.pending => (
        'Заявка проверяется',
        'Публикация будет закрыта до серверного подтверждения.',
      ),
      SellerAccountStatus.blocked => (
        'Продажи заблокированы',
        'Объявления и новые сделки недоступны.',
      ),
      SellerAccountStatus.verified
          when seller.verificationStatus ==
              SellerVerificationStatus.reviewRequired =>
        ('Нужна дополнительная проверка', 'Публикация временно закрыта.'),
      SellerAccountStatus.verified when seller.canSell => (
        'Продавец подтверждён',
        'Можно публиковать собственные вещи.',
      ),
      _ => ('Публикация недоступна', 'Сервер не подтвердил право продавать.'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body),
          ],
        ),
      ),
    );
  }
}
