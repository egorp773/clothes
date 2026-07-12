import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../models/profile_feature.dart';
import '../widgets/app_image.dart';
import 'catalog_screen.dart';

const _ink = Color(0xFF050505);
const _muted = Color(0xFF8A8A8F);
const _line = Color(0xFFD7D7DA);
const _chip = Color(0xFFDCDDE0);
const _lime = Color(0xFFB6FF00);
const _pagePadding = 18.0;
const _darkPanel = Color(0xFF1C1C1E);
const _featureTitleStyle = TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 21,
  height: 1,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
  color: _ink,
);
const _featureBodyStyle = TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 13.5,
  height: 1.35,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
  color: _ink,
);
const _featureSmallStyle = TextStyle(
  fontFamily: 'Montserrat',
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
  color: _ink,
);

class ProfileNotificationsScreen extends StatelessWidget {
  const ProfileNotificationsScreen({
    super.key,
    required this.notifications,
    required this.onMarkRead,
  });

  final List<ProfileNotification> notifications;
  final Future<void> Function(String notificationId) onMarkRead;

  @override
  Widget build(BuildContext context) {
    final sorted =
        notifications
            .where(
              (notification) =>
                  notification.title.trim().isNotEmpty ||
                  notification.body.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _PlainProfilePage(
      title: 'уведомления',
      child: sorted.isEmpty
          ? const _EmptyText(
              'Здесь будут храниться все пуши. Пока новых уведомлений нет, '
              'как только появятся - мы сохраним их здесь.',
            )
          : Column(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  _NotificationTile(
                    notification: sorted[i],
                    onTap: () => onMarkRead(sorted[i].id),
                  ),
                ],
              ],
            ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.preferences,
    required this.onSave,
  });

  final NotificationPreferences preferences;
  final Future<void> Function(NotificationPreferences preferences) onSave;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationPreferences _preferences = widget.preferences;
  bool _isSaving = false;

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await widget.onSave(_preferences);
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _PlainProfilePage(
      title: 'настройки уведомлений',
      child: SizedBox(
        height:
            MediaQuery.sizeOf(context).height -
            MediaQuery.of(context).viewPadding.top -
            142,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text(
              'Вы уже получаете сообщения о заказах.\nЗдесь можно выбрать, как получать\nуведомления о скидках и акциях:',
              style: _featureBodyStyle,
            ),
            const SizedBox(height: 26),
            _PreferenceRow(
              title: 'push-уведомления',
              value: _preferences.pushEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(pushEnabled: value);
                });
              },
            ),
            _PreferenceRow(
              title: 'email',
              value: _preferences.emailEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(emailEnabled: value);
                });
              },
            ),
            _PreferenceRow(
              title: 'sms и мессенджеры',
              value: _preferences.smsEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(smsEnabled: value);
                });
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor: Colors.black,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  _isSaving ? 'СОХРАНЯЕМ' : 'СОХРАНИТЬ',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileAddressesScreen extends StatelessWidget {
  const ProfileAddressesScreen({super.key, required this.onOpenCatalog});

  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    return _PlainProfilePage(
      title: 'мои адреса',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'адресов пока нет',
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Адрес доставки сохранится здесь после первого заказа.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.42,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onOpenCatalog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text(
                'ЗА ПОКУПКАМИ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileOrdersScreen extends StatefulWidget {
  const ProfileOrdersScreen({
    super.key,
    required this.orders,
    required this.recommendedProducts,
    required this.currentUserId,
    required this.onProductTap,
    required this.onToggleProductLike,
    required this.onOpenCatalog,
  });

  final List<AppOrder> orders;
  final List<Product> recommendedProducts;
  final String currentUserId;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId) onToggleProductLike;
  final VoidCallback onOpenCatalog;

  @override
  State<ProfileOrdersScreen> createState() => _ProfileOrdersScreenState();
}

class _ProfileOrdersScreenState extends State<ProfileOrdersScreen> {
  AppOrderRole? _role;
  final Set<AppOrderStatus> _statuses = {};

  List<AppOrder> get _orders {
    final orders = widget.orders.where((order) {
      if (_role == AppOrderRole.seller &&
          order.sellerId != widget.currentUserId) {
        return false;
      }
      if (_role == AppOrderRole.buyer &&
          order.buyerId != widget.currentUserId) {
        return false;
      }
      if (_statuses.isNotEmpty && !_statuses.contains(order.status)) {
        return false;
      }
      return true;
    }).toList();
    orders.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return orders;
  }

  @override
  Widget build(BuildContext context) {
    return _OrdersShell(
      title: 'мои заказы',
      showSearch: _orders.isNotEmpty,
      header: _orders.isEmpty
          ? null
          : _OrderFilters(
              role: _role,
              hasStatusFilter: _statuses.isNotEmpty,
              onRoleChanged: (role) => setState(() => _role = role),
              onStatusTap: _showStatusSheet,
            ),
      child: _orders.isEmpty
          ? _EmptyOrders(
              products: widget.recommendedProducts,
              onOpenCatalog: widget.onOpenCatalog,
              onProductTap: widget.onProductTap,
              onToggleLike: widget.onToggleProductLike,
            )
          : _OrdersList(orders: _orders),
    );
  }

  void _showStatusSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) {
        return _OrderStatusSheet(
          selected: _statuses,
          onApply: (statuses) {
            setState(() {
              _statuses
                ..clear()
                ..addAll(statuses);
            });
          },
        );
      },
    );
  }
}

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key, required this.stats});

  final SellerDashboardStats stats;

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  int _period = 1;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return _PlainProfilePage(
      title: 'дашборд продавца',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              _PeriodButton(
                label: 'Неделя',
                selected: _period == 0,
                onTap: () => setState(() => _period = 0),
              ),
              _PeriodButton(
                label: 'Месяц',
                selected: _period == 1,
                onTap: () => setState(() => _period = 1),
              ),
              _PeriodButton(
                label: 'Год',
                selected: _period == 2,
                onTap: () => setState(() => _period = 2),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SellerScoreCard(stats: stats),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'ВЫРУЧКА',
                  value: '${_formatMoney(stats.revenue)} ₽',
                  isAccent: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  title: 'ЗАКАЗОВ',
                  value: '${stats.ordersCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'СРЕДНИЙ ЧЕК',
                  value: '${_formatMoney(stats.averageOrder)} ₽',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  title: 'ВОЗВРАТЫ',
                  value: '${stats.returnsPercent.round()}%',
                  valueColor: _lime,
                  subtitle: 'норма < 6%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlainProfilePage extends StatelessWidget {
  const _PlainProfilePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    const horizontalPadding = _pagePadding;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topInset + 14,
                horizontalPadding,
                0,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TopProfileBar(
                  title: title,
                  onBack: () => Navigator.maybePop(context),
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _ink),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  2,
                  horizontalPadding,
                  40,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersShell extends StatelessWidget {
  const _OrdersShell({
    required this.title,
    required this.child,
    this.header,
    this.showSearch = false,
  });

  final String title;
  final Widget child;
  final Widget? header;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                _pagePadding,
                topInset + 14,
                _pagePadding,
                0,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TopProfileBar(
                  title: title,
                  onBack: () => Navigator.maybePop(context),
                  trailing: showSearch
                      ? const Icon(Icons.search, size: 22, color: _ink)
                      : null,
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _ink),
            ?header,
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Text(text, style: _featureBodyStyle.copyWith(height: 1.42)),
    );
  }
}

class _TopProfileBar extends StatelessWidget {
  const _TopProfileBar({
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -1),
      child: SizedBox(
        height: 39,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: const SizedBox(
                width: 39,
                height: 39,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.chevron_left, size: 28, color: _ink),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _featureTitleStyle,
              ),
            ),
            if (trailing != null)
              SizedBox(width: 39, height: 39, child: Center(child: trailing)),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final ProfileNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = notification.title.trim();
    final body = notification.body.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead ? const Color(0xFFF7F7F8) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title.isEmpty ? body : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _featureBodyStyle.copyWith(height: 1.15),
                  ),
                ),
                Text(
                  _notificationTime(notification.createdAt),
                  style: _featureSmallStyle.copyWith(
                    fontSize: 11,
                    color: _muted,
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty && body != title) ...[
              const SizedBox(height: 8),
              Text(
                body,
                style: _featureBodyStyle.copyWith(
                  fontSize: 13,
                  height: 1.4,
                  color: _muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: _featureBodyStyle.copyWith(height: 1)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? Colors.black : const Color(0xFFE1E1E4),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: value
                      ? null
                      : Border.all(color: Colors.black, width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({
    required this.products,
    required this.onOpenCatalog,
    required this.onProductTap,
    required this.onToggleLike,
  });

  final List<Product> products;
  final VoidCallback onOpenCatalog;
  final ValueChanged<Product> onProductTap;
  final Future<void> Function(String productId) onToggleLike;

  @override
  Widget build(BuildContext context) {
    final recommended = products
        .where((product) => !product.isHidden)
        .take(2)
        .toList();
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_pagePadding, 30, _pagePadding, 110),
      children: [
        const Text(
          'Вы ещё ничего не покупали. Самое время\nсделать заказ!',
          style: _featureBodyStyle,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onOpenCatalog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(),
            ),
            child: const Text(
              'ЗА ПОКУПКАМИ',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 56),
        const Text('рекомендуем', style: _featureTitleStyle),
        const SizedBox(height: 16),
        if (recommended.isEmpty)
          const Text('В каталоге пока нет товаров.', style: _featureBodyStyle)
        else
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recommended.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 7,
              mainAxisSpacing: 4,
              mainAxisExtent: 320,
            ),
            itemBuilder: (context, index) {
              final product = recommended[index];
              return ProductCard(
                product: product,
                scale: 1,
                onTap: () => onProductTap(product),
                onLike: () => onToggleLike(product.id),
                onMenu: () {},
                onShare: () {},
              );
            },
          ),
      ],
    );
  }
}

class _OrderFilters extends StatelessWidget {
  const _OrderFilters({
    required this.role,
    required this.hasStatusFilter,
    required this.onRoleChanged,
    required this.onStatusTap,
  });

  final AppOrderRole? role;
  final bool hasStatusFilter;
  final ValueChanged<AppOrderRole?> onRoleChanged;
  final VoidCallback onStatusTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(_pagePadding, 14, _pagePadding, 10),
        children: [
          _FilterChip(
            label: 'продаю',
            selected: role == AppOrderRole.seller,
            onTap: () => onRoleChanged(
              role == AppOrderRole.seller ? null : AppOrderRole.seller,
            ),
          ),
          _FilterChip(
            label: 'покупаю',
            selected: role == AppOrderRole.buyer,
            onTap: () => onRoleChanged(
              role == AppOrderRole.buyer ? null : AppOrderRole.buyer,
            ),
          ),
          _FilterChip(
            label: 'статус заказа ${hasStatusFilter ? '⌃' : '⌄'}',
            selected: hasStatusFilter,
            onTap: onStatusTap,
          ),
          _FilterChip(label: 'служба доставки', selected: false, onTap: () {}),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4E4E52) : _chip,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: _featureSmallStyle.copyWith(
            fontSize: 12,
            color: selected ? Colors.white : _ink,
          ),
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.orders});

  final List<AppOrder> orders;

  @override
  Widget build(BuildContext context) {
    final grouped = <AppOrderStatus, List<AppOrder>>{};
    for (final order in orders) {
      grouped.putIfAbsent(order.status, () => []).add(order);
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_pagePadding, 14, _pagePadding, 120),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10),
            child: Text(
              _statusGroupTitle(entry.key),
              style: _featureTitleStyle.copyWith(fontSize: 18),
            ),
          ),
          for (final order in entry.value) _OrderRow(order: order),
        ],
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order.deliveryService} ${order.trackingNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _featureSmallStyle.copyWith(fontSize: 11.5, height: 1),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: order.trackingNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Трек-номер скопирован')),
                  );
                },
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(Icons.copy, size: 15, color: _ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AppImage(
                    imageUrl: order.productImage,
                    fit: BoxFit.fill,
                    placeholderColor: const Color(0xFFF1F1F2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productTitle.split(' ').take(2).join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _featureSmallStyle.copyWith(
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.productTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _featureBodyStyle.copyWith(
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.productPrice,
            style: _featureBodyStyle.copyWith(fontSize: 13, height: 1),
          ),
        ],
      ),
    );
  }
}

class _OrderStatusSheet extends StatefulWidget {
  const _OrderStatusSheet({required this.selected, required this.onApply});

  final Set<AppOrderStatus> selected;
  final ValueChanged<Set<AppOrderStatus>> onApply;

  @override
  State<_OrderStatusSheet> createState() => _OrderStatusSheetState();
}

class _OrderStatusSheetState extends State<_OrderStatusSheet> {
  late final Set<AppOrderStatus> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, size: 22, color: _muted),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'статус заказа',
                      style: _featureBodyStyle.copyWith(
                        fontSize: 15,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(_selected.clear),
                  child: Text(
                    'сбросить',
                    style: _featureSmallStyle.copyWith(
                      fontSize: 11,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final status in AppOrderStatus.values)
              _StatusOption(
                label: _statusFilterTitle(status),
                selected: _selected.contains(status),
                onTap: () {
                  setState(() {
                    if (!_selected.remove(status)) _selected.add(status);
                  });
                },
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(_selected);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(),
                ),
                child: const Text(
                  'ПРИМЕНИТЬ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: selected ? Colors.black : const Color(0xFFD9D9DB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _featureBodyStyle.copyWith(fontSize: 13, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.black : const Color(0xFFF0F0F2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: _featureSmallStyle.copyWith(
            fontSize: 12.5,
            color: selected ? Colors.white : _ink,
          ),
        ),
      ),
    );
  }
}

class _SellerScoreCard extends StatelessWidget {
  const _SellerScoreCard({required this.stats});

  final SellerDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final rating = stats.rating.clamp(0, 5).toDouble();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: _darkPanel,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'РЕЙТИНГ ПРОДАВЦА',
            style: _featureSmallStyle.copyWith(fontSize: 10, color: _muted),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rating.toStringAsFixed(1),
                style: _featureTitleStyle.copyWith(
                  fontSize: 34,
                  height: 1,
                  color: _lime,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/5.0',
                  style: _featureBodyStyle.copyWith(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'КОМИССИЯ ПЛАТФОРМЫ',
            style: _featureSmallStyle.copyWith(fontSize: 10, color: _muted),
          ),
          Row(
            children: [
              Text(
                '${stats.commissionPercent}%',
                style: _featureTitleStyle.copyWith(
                  fontSize: 38,
                  height: 1,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF709300),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'топ',
                  style: _featureSmallStyle.copyWith(
                    fontSize: 10,
                    color: _lime,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Stack(
            children: [
              Container(
                height: 7,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF3B6A), Color(0xFFFFB04A), _lime],
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: CircleAvatar(radius: 6.5, backgroundColor: _lime),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CommissionLabel('Базовый\n18%'),
              _CommissionLabel('Стандарт\n14%'),
              _CommissionLabel('Хороший\n11%'),
              _CommissionLabel('Отличный\n9%'),
              _CommissionLabel('Топ\n7%', active: true),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: CircleAvatar(radius: 3.5, backgroundColor: _lime),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: _featureSmallStyle.copyWith(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.white,
                      ),
                      children: [
                        const TextSpan(text: 'Ваш рейтинг в '),
                        const TextSpan(
                          text: 'топе',
                          style: TextStyle(color: _lime),
                        ),
                        const TextSpan(text: '! Ваша\nкомиссия '),
                        TextSpan(
                          text: '${stats.commissionPercent}%',
                          style: const TextStyle(color: _lime),
                        ),
                        const TextSpan(text: ' с каждой\nпродажи.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommissionLabel extends StatelessWidget {
  const _CommissionLabel(this.text, {this.active = false});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: _featureSmallStyle.copyWith(
        fontSize: 7,
        height: 1.1,
        color: active ? _lime : const Color(0xFF67676D),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.isAccent = false,
    this.valueColor,
  });

  final String title;
  final String value;
  final String? subtitle;
  final bool isAccent;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final foreground = isAccent ? Colors.black : Colors.white;
    return Container(
      height: 116,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
      decoration: BoxDecoration(
        color: isAccent ? _lime : _darkPanel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _featureSmallStyle.copyWith(
              fontSize: 9.5,
              color: isAccent ? Colors.black : _muted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: _featureTitleStyle.copyWith(
              fontSize: 24,
              height: 1,
              color: valueColor ?? foreground,
            ),
          ),
          if (subtitle != null) ...[
            const Spacer(),
            Text(
              subtitle!,
              style: _featureSmallStyle.copyWith(fontSize: 9.5, color: _muted),
            ),
          ],
        ],
      ),
    );
  }
}

String _notificationTime(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return 'Сегодня в ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
}

String _statusGroupTitle(AppOrderStatus status) {
  switch (status) {
    case AppOrderStatus.completed:
      return 'завершён';
    case AppOrderStatus.canceled:
      return 'отменён';
    default:
      return _statusFilterTitle(status);
  }
}

String _statusFilterTitle(AppOrderStatus status) {
  switch (status) {
    case AppOrderStatus.pendingConfirmation:
      return 'ждут подтверждения';
    case AppOrderStatus.pendingShipment:
      return 'ждут отправки';
    case AppOrderStatus.inTransit:
      return 'в пути';
    case AppOrderStatus.deliveredToPickup:
      return 'доставлен в пункт выдачи';
    case AppOrderStatus.awaitingPayment:
      return 'можно получить оплату';
    case AppOrderStatus.returning:
      return 'на возврате';
    case AppOrderStatus.disputed:
      return 'спорные';
    case AppOrderStatus.completed:
      return 'завершенные';
    case AppOrderStatus.canceled:
      return 'отмененные';
  }
}

String _formatMoney(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(' ');
  }
  return buffer.toString();
}
