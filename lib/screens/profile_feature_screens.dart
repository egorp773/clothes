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

class ProfileNotificationsScreen extends StatefulWidget {
  const ProfileNotificationsScreen({
    super.key,
    required this.notifications,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onNotificationTap,
  });

  final List<ProfileNotification> notifications;
  final Future<void> Function(String notificationId) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function(ProfileNotification notification)
  onNotificationTap;

  @override
  State<ProfileNotificationsScreen> createState() =>
      _ProfileNotificationsScreenState();
}

class _ProfileNotificationsScreenState
    extends State<ProfileNotificationsScreen> {
  late List<ProfileNotification> _notifications = [...widget.notifications];

  @override
  void didUpdateWidget(covariant ProfileNotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notifications, widget.notifications)) {
      _notifications = [...widget.notifications];
    }
  }

  Future<void> _markRead(ProfileNotification notification) async {
    if (!notification.isRead) {
      setState(() {
        _notifications = _notifications
            .map(
              (item) => item.id == notification.id
                  ? item.copyWith(isRead: true)
                  : item,
            )
            .toList();
      });
      await widget.onMarkRead(notification.id);
    }
    await widget.onNotificationTap(notification);
  }

  Future<void> _markAllRead() async {
    setState(() {
      _notifications = _notifications
          .map((notification) => notification.copyWith(isRead: true))
          .toList();
    });
    await widget.onMarkAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final sorted =
        _notifications
            .where(
              (notification) =>
                  notification.kind != 'message' &&
                  (notification.title.trim().isNotEmpty ||
                      notification.body.trim().isNotEmpty),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final now = DateTime.now();
    final today = <ProfileNotification>[];
    final yesterday = <ProfileNotification>[];
    final earlier = <ProfileNotification>[];
    for (final notification in sorted) {
      final created = notification.createdAt.toLocal();
      final days = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(created.year, created.month, created.day)).inDays;
      if (days <= 0) {
        today.add(notification);
      } else if (days == 1) {
        yesterday.add(notification);
      } else {
        earlier.add(notification);
      }
    }
    final hasUnread = sorted.any((notification) => !notification.isRead);
    return _PlainProfilePage(
      title: 'уведомления',
      action: hasUnread
          ? TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(
                foregroundColor: _ink,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'прочитать все',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            )
          : null,
      child: sorted.isEmpty
          ? const _NotificationEmptyState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (today.isNotEmpty)
                  _NotificationSection(
                    title: 'сегодня',
                    notifications: today,
                    onMarkRead: _markRead,
                  ),
                if (yesterday.isNotEmpty)
                  _NotificationSection(
                    title: 'вчера',
                    notifications: yesterday,
                    onMarkRead: _markRead,
                  ),
                if (earlier.isNotEmpty)
                  _NotificationSection(
                    title: 'раньше',
                    notifications: earlier,
                    onMarkRead: _markRead,
                  ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Получайте только важное. Настройки можно изменить в любой момент.',
            style: _featureBodyStyle.copyWith(
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: _PreferenceRow(
              title: 'Push-уведомления',
              subtitle: 'Главный переключатель',
              icon: Icons.notifications_none_rounded,
              value: _preferences.pushEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(pushEnabled: value);
                });
              },
            ),
          ),
          const SizedBox(height: 26),
          const Text('что присылать', style: _featureTitleStyle),
          const SizedBox(height: 10),
          _PreferenceRow(
            title: 'Сообщения',
            subtitle: 'Новые сообщения от покупателей и продавцов',
            icon: Icons.chat_bubble_outline_rounded,
            value: _preferences.pushEnabled && _preferences.messagesEnabled,
            enabled: _preferences.pushEnabled,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(messagesEnabled: value);
              });
            },
          ),
          _PreferenceRow(
            title: 'Заказы и доставка',
            subtitle: 'Статусы сделок и важные действия',
            icon: Icons.local_shipping_outlined,
            value: _preferences.pushEnabled && _preferences.ordersEnabled,
            enabled: _preferences.pushEnabled,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(ordersEnabled: value);
              });
            },
          ),
          _PreferenceRow(
            title: 'Избранное',
            subtitle: 'Лайки, снижение цены и интерес к вещам',
            icon: Icons.favorite_border_rounded,
            value: _preferences.pushEnabled && _preferences.favoritesEnabled,
            enabled: _preferences.pushEnabled,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(favoritesEnabled: value);
              });
            },
          ),
          _PreferenceRow(
            title: 'Скидки и новости',
            subtitle: 'Редкие полезные предложения',
            icon: Icons.local_offer_outlined,
            value: _preferences.pushEnabled && _preferences.promotionsEnabled,
            enabled: _preferences.pushEnabled,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(promotionsEnabled: value);
              });
            },
          ),
          const SizedBox(height: 20),
          const Text('как присылать', style: _featureTitleStyle),
          const SizedBox(height: 10),
          _PreferenceRow(
            title: 'Звук уведомлений',
            subtitle: 'Для важных событий и сообщений',
            icon: Icons.volume_up_outlined,
            value: _preferences.pushEnabled && _preferences.soundEnabled,
            enabled: _preferences.pushEnabled,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(soundEnabled: value);
              });
            },
          ),
          const SizedBox(height: 28),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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
          const SizedBox(height: 10),
        ],
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

  List<AppOrder> get _ownedOrders {
    final currentUserId = widget.currentUserId.trim();
    if (currentUserId.isEmpty) return const [];
    return widget.orders
        .where(
          (order) =>
              order.buyerId == currentUserId || order.sellerId == currentUserId,
        )
        .toList();
  }

  List<AppOrder> get _orders {
    final orders = _ownedOrders.where((order) {
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
    orders.sort((a, b) {
      final activityOrder = (_isOrderActive(a.status) ? 0 : 1).compareTo(
        _isOrderActive(b.status) ? 0 : 1,
      );
      if (activityOrder != 0) return activityOrder;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return orders;
  }

  bool get _hasFilters => _role != null || _statuses.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ownedOrders = _ownedOrders;
    final filteredOrders = _orders;
    return _OrdersShell(
      title: 'мои заказы',
      showSearch: false,
      header: ownedOrders.isEmpty
          ? null
          : _OrderFilters(
              role: _role,
              hasStatusFilter: _statuses.isNotEmpty,
              onRoleChanged: (role) => setState(() => _role = role),
              onStatusTap: _showStatusSheet,
            ),
      child: ownedOrders.isEmpty
          ? _EmptyOrders(
              products: widget.recommendedProducts,
              onOpenCatalog: widget.onOpenCatalog,
              onProductTap: widget.onProductTap,
              onToggleLike: widget.onToggleProductLike,
            )
          : filteredOrders.isEmpty
          ? _NoFilteredOrders(onReset: _resetFilters)
          : _OrdersList(
              orders: filteredOrders,
              currentUserId: widget.currentUserId,
              onOrderTap: _showOrderDetails,
            ),
    );
  }

  void _resetFilters() {
    if (!_hasFilters) return;
    setState(() {
      _role = null;
      _statuses.clear();
    });
  }

  void _showOrderDetails(AppOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) =>
          _OrderDetailsSheet(order: order, currentUserId: widget.currentUserId),
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
  const _PlainProfilePage({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

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
                  trailing: action,
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
    return Material(
      color: notification.isRead ? Colors.white : const Color(0xFFF5F7F1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _notificationKindColor(notification.kind),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _notificationKindIcon(notification.kind),
                  size: 20,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title.isEmpty ? body : title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _featureBodyStyle.copyWith(height: 1.2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _notificationTime(notification.createdAt),
                          style: _featureSmallStyle.copyWith(
                            fontSize: 10.5,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty && body != title) ...[
                      const SizedBox(height: 6),
                      Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: _featureBodyStyle.copyWith(
                          fontSize: 12.5,
                          height: 1.38,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!notification.isRead) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF69A800),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationSection extends StatelessWidget {
  const _NotificationSection({
    required this.title,
    required this.notifications,
    required this.onMarkRead,
  });

  final String title;
  final List<ProfileNotification> notifications;
  final Future<void> Function(ProfileNotification notification) onMarkRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _featureSmallStyle.copyWith(color: _muted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          for (final notification in notifications) ...[
            _NotificationTile(
              notification: notification,
              onTap: () => onMarkRead(notification),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F3F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 31,
                color: _ink,
              ),
            ),
            const SizedBox(height: 18),
            const Text('Пока всё спокойно', style: _featureTitleStyle),
            const SizedBox(height: 8),
            Text(
              'Изменения заказов, избранного и другие важные события появятся здесь.',
              textAlign: TextAlign.center,
              style: _featureBodyStyle.copyWith(
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
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
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 21, color: _ink),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _featureBodyStyle.copyWith(height: 1.1)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: _featureSmallStyle.copyWith(
                        color: _muted,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onChanged(!value) : null,
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
          'У вас пока нет покупок и продаж.\nСамое время начать!',
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

class _NoFilteredOrders extends StatelessWidget {
  const _NoFilteredOrders({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 30, 30, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 42,
              color: Color(0xFFB0B0B5),
            ),
            const SizedBox(height: 14),
            const Text(
              'Заказов по этим фильтрам нет',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Попробуйте выбрать другую роль или статус.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Сбросить фильтры'),
            ),
          ],
        ),
      ),
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
  const _OrdersList({
    required this.orders,
    required this.currentUserId,
    required this.onOrderTap,
  });

  final List<AppOrder> orders;
  final String currentUserId;
  final ValueChanged<AppOrder> onOrderTap;

  @override
  Widget build(BuildContext context) {
    final active = orders
        .where((order) => _isOrderActive(order.status))
        .toList();
    final finished = orders
        .where((order) => !_isOrderActive(order.status))
        .toList();
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_pagePadding, 10, _pagePadding, 120),
      children: [
        if (active.isNotEmpty) ...[
          const _OrderListTitle('Активные'),
          for (final order in active)
            _OrderRow(
              order: order,
              currentUserId: currentUserId,
              onTap: () => onOrderTap(order),
            ),
        ],
        if (finished.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: active.isEmpty ? 0 : 14),
            child: const _OrderListTitle('Завершённые'),
          ),
          for (final order in finished)
            _OrderRow(
              order: order,
              currentUserId: currentUserId,
              onTap: () => onOrderTap(order),
            ),
        ],
      ],
    );
  }
}

class _OrderListTitle extends StatelessWidget {
  const _OrderListTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 11),
      child: Text(title, style: _featureTitleStyle.copyWith(fontSize: 17)),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.currentUserId,
    required this.onTap,
  });

  final AppOrder order;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trackingNumber = order.trackingNumber.trim();
    final role = order.sellerId == currentUserId
        ? AppOrderRole.seller
        : AppOrderRole.buyer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('order-row-${order.id}'),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE6E6E9)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _OrderRoleBadge(role: role),
                    const Spacer(),
                    Text(
                      _formatOrderDate(order.createdAt),
                      style: _featureSmallStyle.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 82,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AppImage(
                          imageUrl: order.productImage,
                          fit: BoxFit.cover,
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
                            order.productTitle.trim().isEmpty
                                ? 'Товар'
                                : order.productTitle.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _featureBodyStyle.copyWith(
                              fontSize: 13.5,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 7),
                          _OrderStatusBadge(status: order.status),
                          const SizedBox(height: 8),
                          Text(
                            _orderTotalLabel(order),
                            style: _featureBodyStyle.copyWith(
                              fontSize: 13,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _orderDeliveryLabel(order),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _featureSmallStyle.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 21,
                        color: Color(0xFF8A8A8F),
                      ),
                    ),
                  ],
                ),
                if (trackingNumber.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE8E8EA)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 17,
                        color: _muted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Трек $trackingNumber',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _featureSmallStyle.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('order-tracking-copy-${order.id}'),
                        tooltip: 'Скопировать трек-номер',
                        onPressed: () =>
                            _copyTrackingNumber(context, trackingNumber),
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderRoleBadge extends StatelessWidget {
  const _OrderRoleBadge({required this.role});

  final AppOrderRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role == AppOrderRole.buyer ? 'Покупка' : 'Продажа',
        style: _featureSmallStyle.copyWith(fontSize: 10.5),
      ),
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.status});

  final AppOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = _orderStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _orderStatusTitle(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _featureSmallStyle.copyWith(
          fontSize: 10,
          color: colors.foreground,
        ),
      ),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  const _OrderDetailsSheet({required this.order, required this.currentUserId});

  final AppOrder order;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final trackingNumber = order.trackingNumber.trim();
    final role = order.sellerId == currentUserId
        ? AppOrderRole.seller
        : AppOrderRole.buyer;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomInset),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5D5D8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Expanded(
                    child: Text('Заказ', style: _featureTitleStyle),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _OrderRoleBadge(role: role),
                  const SizedBox(width: 8),
                  Flexible(child: _OrderStatusBadge(status: order.status)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 82,
                    height: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: AppImage(
                        imageUrl: order.productImage,
                        fit: BoxFit.cover,
                        placeholderColor: const Color(0xFFF1F1F2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.productTitle.trim().isEmpty
                              ? 'Товар'
                              : order.productTitle.trim(),
                          style: _featureBodyStyle.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _orderTotalLabel(order),
                          style: _featureBodyStyle.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatOrderDate(order.createdAt),
                          style: _featureSmallStyle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: Color(0xFFE8E8EA)),
              const SizedBox(height: 14),
              _OrderDetailValue(
                label: 'Доставка',
                value: _orderDeliveryLabel(order),
              ),
              if (order.deliveryAddress.trim().isNotEmpty)
                _OrderDetailValue(
                  label: 'Адрес',
                  value: order.deliveryAddress.trim(),
                ),
              if (trackingNumber.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text(
                          'Трек-номер',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _muted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          trackingNumber,
                          style: _featureSmallStyle.copyWith(fontSize: 11.5),
                        ),
                      ),
                      IconButton(
                        key: Key('order-detail-tracking-copy-${order.id}'),
                        tooltip: 'Скопировать трек-номер',
                        onPressed: () =>
                            _copyTrackingNumber(context, trackingNumber),
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDetailValue extends StatelessWidget {
  const _OrderDetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: _featureSmallStyle.copyWith(fontSize: 11.5),
            ),
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
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
}

IconData _notificationKindIcon(String kind) {
  switch (kind) {
    case 'message':
      return Icons.chat_bubble_outline_rounded;
    case 'order':
    case 'delivery':
      return Icons.local_shipping_outlined;
    case 'favorite':
    case 'like':
      return Icons.favorite_border_rounded;
    case 'promotion':
    case 'price_drop':
      return Icons.local_offer_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}

Color _notificationKindColor(String kind) {
  switch (kind) {
    case 'message':
      return const Color(0xFFE8F1FF);
    case 'order':
    case 'delivery':
      return const Color(0xFFE9F7E8);
    case 'favorite':
    case 'like':
      return const Color(0xFFFFECEA);
    case 'promotion':
    case 'price_drop':
      return const Color(0xFFFFF2C9);
    default:
      return const Color(0xFFF0F0F2);
  }
}

bool _isOrderActive(AppOrderStatus status) =>
    status != AppOrderStatus.completed && status != AppOrderStatus.canceled;

String _orderStatusTitle(AppOrderStatus status) => switch (status) {
  AppOrderStatus.pendingConfirmation => 'Ждёт подтверждения',
  AppOrderStatus.pendingShipment => 'Ждёт отправки',
  AppOrderStatus.inTransit => 'В пути',
  AppOrderStatus.deliveredToPickup => 'Можно забирать',
  AppOrderStatus.awaitingPayment => 'Ожидается выплата',
  AppOrderStatus.returning => 'Возврат',
  AppOrderStatus.disputed => 'Открыт спор',
  AppOrderStatus.completed => 'Завершён',
  AppOrderStatus.canceled => 'Отменён',
};

({Color background, Color foreground}) _orderStatusColors(
  AppOrderStatus status,
) => switch (status) {
  AppOrderStatus.pendingConfirmation || AppOrderStatus.pendingShipment => (
    background: const Color(0xFFFFF1D6),
    foreground: const Color(0xFF8A5700),
  ),
  AppOrderStatus.inTransit || AppOrderStatus.deliveredToPickup => (
    background: const Color(0xFFE8F1FF),
    foreground: const Color(0xFF245EA8),
  ),
  AppOrderStatus.awaitingPayment || AppOrderStatus.completed => (
    background: const Color(0xFFE9F7E8),
    foreground: const Color(0xFF28752D),
  ),
  AppOrderStatus.returning || AppOrderStatus.disputed => (
    background: const Color(0xFFFFECEA),
    foreground: const Color(0xFFA9342C),
  ),
  AppOrderStatus.canceled => (
    background: const Color(0xFFF0F0F2),
    foreground: const Color(0xFF66666C),
  ),
};

String _orderTotalLabel(AppOrder order) {
  final total = order.productPriceValue + order.deliveryPrice;
  if (total > 0) return 'Итого ${_formatMoney(total)} ₽';
  final price = order.productPrice.trim();
  return price.isEmpty ? 'Итог уточняется' : 'Итого $price';
}

String _orderDeliveryLabel(AppOrder order) {
  final parts = <String>[];
  if (order.deliveryPrice > 0) {
    parts.add('${_formatMoney(order.deliveryPrice)} ₽');
  }
  if (order.deliveryService.trim().isNotEmpty) {
    parts.add(order.deliveryService.trim());
  }
  return parts.isEmpty
      ? 'Доставка уточняется'
      : 'Доставка ${parts.join(' · ')}';
}

String _formatOrderDate(DateTime value) {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  final date = value.toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute';
}

void _copyTrackingNumber(BuildContext context, String value) {
  final trackingNumber = value.trim();
  if (trackingNumber.isEmpty) return;
  Clipboard.setData(ClipboardData(text: trackingNumber));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Трек-номер скопирован')));
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
