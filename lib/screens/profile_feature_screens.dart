import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_typography.dart';
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
  fontFamily: AppTypography.fontFamily,
  fontSize: 21,
  height: 1,
  fontWeight: AppTypography.bold,
  letterSpacing: 0,
  color: _ink,
);
const _featureBodyStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 13.5,
  height: 1.35,
  fontWeight: AppTypography.medium,
  letterSpacing: 0,
  color: _ink,
);
const _featureSmallStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 12,
  height: 1.2,
  fontWeight: AppTypography.medium,
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
  final Set<String> _openingNotificationIds = <String>{};
  bool _isMarkingAllRead = false;

  @override
  void didUpdateWidget(covariant ProfileNotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notifications, widget.notifications)) {
      _notifications = [...widget.notifications];
    }
  }

  Future<void> _markRead(ProfileNotification notification) async {
    if (!_openingNotificationIds.add(notification.id)) return;
    final wasUnread = !notification.isRead;
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
      try {
        await widget.onMarkRead(notification.id);
      } catch (_) {
        if (mounted) {
          setState(() {
            _notifications = _notifications
                .map(
                  (item) => item.id == notification.id
                      ? item.copyWith(isRead: false)
                      : item,
                )
                .toList();
          });
          _showNotificationError('Не удалось отметить уведомление прочитанным');
        }
      }
    }
    try {
      await widget.onNotificationTap(
        wasUnread ? notification.copyWith(isRead: true) : notification,
      );
    } catch (_) {
      if (mounted) {
        _showNotificationError('Не удалось открыть уведомление');
      }
    } finally {
      _openingNotificationIds.remove(notification.id);
    }
  }

  Future<void> _markAllRead() async {
    if (_isMarkingAllRead) return;
    final previous = [..._notifications];
    _isMarkingAllRead = true;
    setState(() {
      _notifications = _notifications
          .map((notification) => notification.copyWith(isRead: true))
          .toList();
    });
    try {
      await widget.onMarkAllRead();
    } catch (_) {
      if (mounted) {
        setState(() => _notifications = previous);
        _showNotificationError('Не удалось отметить уведомления прочитанными');
      }
    } finally {
      _isMarkingAllRead = false;
    }
  }

  void _showNotificationError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
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

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({
    super.key,
    required this.onEditProfile,
    required this.onNotificationSettings,
    required this.onAddresses,
    required this.onSupport,
    required this.onFaq,
    required this.onDocuments,
  });

  final VoidCallback onEditProfile;
  final VoidCallback onNotificationSettings;
  final VoidCallback onAddresses;
  final VoidCallback onSupport;
  final VoidCallback onFaq;
  final VoidCallback onDocuments;

  @override
  Widget build(BuildContext context) {
    return _PlainProfilePage(
      title: 'настройки',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          const Text('профиль и аккаунт', style: _featureTitleStyle),
          const SizedBox(height: 8),
          _SettingsRouteTile(
            key: const Key('profile-settings-edit-profile'),
            icon: Icons.person_outline_rounded,
            title: 'Редактировать профиль',
            subtitle: 'Имя, фото, контакты и город',
            onTap: onEditProfile,
          ),
          _SettingsRouteTile(
            key: const Key('profile-settings-notifications'),
            icon: Icons.notifications_none_rounded,
            title: 'Уведомления',
            subtitle: 'Push, сообщения, заказы и звук',
            onTap: onNotificationSettings,
          ),
          _SettingsRouteTile(
            key: const Key('profile-settings-addresses'),
            icon: Icons.location_on_outlined,
            title: 'Адреса доставки',
            subtitle: 'Получатель, домашний адрес и выбранный ПВЗ',
            onTap: onAddresses,
          ),
          const SizedBox(height: 20),
          const Text('помощь и информация', style: _featureTitleStyle),
          const SizedBox(height: 8),
          _SettingsRouteTile(
            key: const Key('profile-settings-support'),
            icon: Icons.support_agent_rounded,
            title: 'Поддержка',
            subtitle: 'Каналы связи и их текущий статус',
            onTap: onSupport,
          ),
          _SettingsRouteTile(
            key: const Key('profile-settings-faq'),
            icon: Icons.help_outline_rounded,
            title: 'Частые вопросы',
            subtitle: 'Просмотры, история, доставка и аккаунт',
            onTap: onFaq,
          ),
          _SettingsRouteTile(
            key: const Key('profile-settings-documents'),
            icon: Icons.description_outlined,
            title: 'Документы',
            subtitle: 'Правила сервиса и статус публикации',
            onTap: onDocuments,
          ),
          const SizedBox(height: 16),
          const Text(
            'Изменение контактов, безопасность входа и удаление аккаунта находятся в разделе «Редактировать профиль».',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }
}

enum ProfileInformationTopic {
  support,
  faq,
  deliveryAndPayment,
  documents,
  careers,
}

class ProfileInformationScreen extends StatelessWidget {
  const ProfileInformationScreen({super.key, required this.topic});

  final ProfileInformationTopic topic;

  @override
  Widget build(BuildContext context) {
    return switch (topic) {
      ProfileInformationTopic.support => _PlainProfilePage(
        title: 'поддержка',
        child: const _SupportInformation(),
      ),
      ProfileInformationTopic.faq => _PlainProfilePage(
        title: 'частые вопросы',
        child: const _FaqInformation(),
      ),
      ProfileInformationTopic.deliveryAndPayment => _PlainProfilePage(
        title: 'доставка и оплата',
        child: const _DeliveryInformation(),
      ),
      ProfileInformationTopic.documents => _PlainProfilePage(
        title: 'документы',
        child: const _DocumentsInformation(),
      ),
      ProfileInformationTopic.careers => _PlainProfilePage(
        title: 'вакансии',
        child: const _CareersInformation(),
      ),
    };
  }
}

class _SupportInformation extends StatelessWidget {
  const _SupportInformation();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        _InformationLead(
          icon: Icons.support_agent_rounded,
          title: 'Каналы поддержки готовятся к запуску',
          body:
              'Официальный чат, номер телефона и email пока не опубликованы. До их появления не передавайте данные заказа и оплаты сторонним аккаунтам.',
        ),
        SizedBox(height: 18),
        _InformationCard(
          title: 'Чат в приложении',
          body:
              'Будет доступен здесь после подключения операторов и регламента обработки обращений.',
          status: 'ГОТОВИТСЯ',
        ),
        SizedBox(height: 10),
        _InformationCard(
          title: 'Телефон и email',
          body:
              'Контакты появятся только после регистрации официальной линии поддержки.',
          status: 'НЕ ОПУБЛИКОВАНЫ',
        ),
        SizedBox(height: 18),
        Text(
          'Если вопрос касается интерфейса, сначала проверьте раздел «Частые вопросы».',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            height: 1.4,
            fontWeight: AppTypography.medium,
            color: _muted,
          ),
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

class _FaqInformation extends StatelessWidget {
  const _FaqInformation();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 12),
        _FaqTile(
          question: 'Когда считается просмотр?',
          answer:
              'Просмотр засчитывается при открытии объявления или образа. Простое пролистывание каталога и показ карточки в ленте просмотром не считаются.',
        ),
        _FaqTile(
          question: 'Как очистить недавно просмотренное?',
          answer:
              'Откройте «Недавно просмотренное» в профиле и нажмите «Очистить» сверху. После подтверждения удалится история вещей и образов.',
        ),
        _FaqTile(
          question: 'Какой адрес нужен для пункта выдачи?',
          answer:
              'Домашний адрес и пункт выдачи хранятся отдельно. Для доставки в ПВЗ выбирается конкретный пункт с его названием, адресом и идентификатором службы доставки.',
        ),
        _FaqTile(
          question: 'Когда списываются деньги?',
          answer:
              'Оплата должна подтверждаться только через подключённую безопасную сделку. Пока платёжный провайдер не активирован, приложение не должно имитировать успешное списание.',
        ),
        _FaqTile(
          question: 'Как связаться с продавцом?',
          answer:
              'Откройте объявление или профиль продавца и перейдите в сообщения. История переписки сохраняется в разделе «Сообщения».',
        ),
        _FaqTile(
          question: 'Как удалить аккаунт?',
          answer:
              'Профиль → Настройки → Редактировать профиль → Управление аккаунтом → Удалить аккаунт. Действие требует отдельного подтверждения.',
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

class _DeliveryInformation extends StatelessWidget {
  const _DeliveryInformation();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        _InformationLead(
          icon: Icons.local_shipping_outlined,
          title: 'Доставка без подмены адресов',
          body:
              'Домашний адрес используется для курьерской доставки. Для ПВЗ сохраняются отдельные данные выбранного пункта — служба, идентификатор, название и фактический адрес.',
        ),
        SizedBox(height: 18),
        _InformationCard(
          title: 'Расчёт доставки',
          body:
              'Срок и стоимость должны приходить от выбранной службы доставки. Недоступный тариф не заменяется случайным адресом или фиктивной ценой.',
          status: 'ПРАВИЛО СЕРВИСА',
        ),
        SizedBox(height: 10),
        _InformationCard(
          title: 'Безопасная оплата',
          body:
              'Заказ считается оплаченным только после серверного подтверждения платёжного провайдера. Ошибка должна оставлять заказ неоплаченным и показывать понятную причину.',
          status: 'ПОДКЛЮЧАЕТСЯ',
        ),
        SizedBox(height: 10),
        _InformationCard(
          title: 'Внешние службы',
          body:
              'CDEK, Почта России и Яндекс Доставка станут доступны после заключения договоров и активации рабочих ключей.',
          status: 'ОЖИДАЮТ ДОГОВОРОВ',
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

class _DocumentsInformation extends StatelessWidget {
  const _DocumentsInformation();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        _InformationLead(
          icon: Icons.description_outlined,
          title: 'Юридические тексты ещё не опубликованы',
          body:
              'До релиза здесь должны появиться финальные документы с публичными ссылками, реквизитами владельца сервиса и датой вступления в силу.',
        ),
        SizedBox(height: 18),
        _DocumentStatusRow(title: 'Политика конфиденциальности'),
        _DocumentStatusRow(title: 'Пользовательское соглашение'),
        _DocumentStatusRow(title: 'Правила сообщества и модерации'),
        _DocumentStatusRow(title: 'Условия оплаты, доставки и возврата'),
        _DocumentStatusRow(title: 'Правила безопасной сделки и споров'),
        SizedBox(height: 18),
        Text(
          'Удаление аккаунта уже доступно в настройках профиля. Публикация документов и постоянных web-ссылок остаётся обязательным условием релиза.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            height: 1.4,
            fontWeight: AppTypography.medium,
            color: _muted,
          ),
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

class _CareersInformation extends StatelessWidget {
  const _CareersInformation();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        _InformationLead(
          icon: Icons.work_outline_rounded,
          title: 'Открытых вакансий сейчас нет',
          body:
              'Раздел сохранён для будущих вакансий. Официальный адрес для откликов будет опубликован вместе с первой позицией.',
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

class _InformationLead extends StatelessWidget {
  const _InformationLead({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 25, color: _ink),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 17,
              height: 1.15,
              fontWeight: AppTypography.bold,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: _featureBodyStyle.copyWith(color: _muted)),
        ],
      ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.title,
    required this.body,
    required this.status,
  });

  final String title;
  final String body;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: AppTypography.bold,
                    color: _ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(label: status),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: _featureBodyStyle.copyWith(color: _muted)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 9,
          height: 1,
          fontWeight: AppTypography.bold,
          color: _muted,
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 16),
        iconColor: _ink,
        collapsedIconColor: _ink,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          question,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            height: 1.25,
            fontWeight: AppTypography.semiBold,
            color: _ink,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: _featureBodyStyle.copyWith(color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentStatusRow extends StatelessWidget {
  const _DocumentStatusRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 19, color: _muted),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                fontWeight: AppTypography.semiBold,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const _StatusBadge(label: 'ДО РЕЛИЗА'),
        ],
      ),
    );
  }
}

class _SettingsRouteTile extends StatelessWidget {
  const _SettingsRouteTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 21, color: _ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileAddressesScreen extends StatefulWidget {
  const ProfileAddressesScreen({
    super.key,
    required this.profile,
    required this.onSave,
    required this.onOpenCatalog,
  });

  final DeliveryProfile profile;
  final Future<void> Function(DeliveryProfile profile) onSave;
  final VoidCallback onOpenCatalog;

  @override
  State<ProfileAddressesScreen> createState() => _ProfileAddressesScreenState();
}

class _ProfileAddressesScreenState extends State<ProfileAddressesScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _city;
  late final TextEditingController _address;
  late DeliveryProfile _profile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _name = TextEditingController(text: _profile.fullName);
    _phone = TextEditingController(text: _profile.phone);
    _email = TextEditingController(text: _profile.email);
    _city = TextEditingController(text: _profile.city);
    _address = TextEditingController(text: _profile.address);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final email = _email.text.trim();
    final error = _name.text.trim().length < 2
        ? 'Укажите имя получателя'
        : phoneDigits.length < 10
        ? 'Проверьте телефон получателя'
        : email.isNotEmpty &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? 'Проверьте email'
        : _city.text.trim().isEmpty
        ? 'Укажите город'
        : _address.text.trim().length < 5
        ? 'Укажите улицу и дом'
        : null;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _isSaving = true);
    final next = _profile.copyWith(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      email: email,
      city: _city.text.trim(),
      address: _address.text.trim(),
    );
    try {
      await widget.onSave(next);
      if (!mounted) return;
      setState(() => _profile = next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Адрес и данные получателя сохранены')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить адрес. Попробуйте ещё раз.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearPickupPoint() async {
    final next = _profile.copyWith(
      pickupProvider: '',
      pickupPointId: '',
      pickupPointName: '',
      pickupPointAddress: '',
    );
    try {
      await widget.onSave(next);
      if (!mounted) return;
      setState(() => _profile = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось удалить пункт. Попробуйте ещё раз.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPickup =
        _profile.pickupPointId.trim().isNotEmpty &&
        _profile.pickupPointAddress.trim().isNotEmpty;
    return _PlainProfilePage(
      title: 'мои адреса',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('адрес доставки', style: _featureTitleStyle),
          const SizedBox(height: 8),
          const Text(
            'Адрес квартиры хранится отдельно от выбранного пункта выдачи.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
          const SizedBox(height: 16),
          _ProfileAddressField(
            key: const Key('address-recipient-name'),
            controller: _name,
            label: 'Имя и фамилия',
            textInputAction: TextInputAction.next,
          ),
          _ProfileAddressField(
            key: const Key('address-recipient-phone'),
            controller: _phone,
            label: 'Телефон',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          _ProfileAddressField(
            controller: _email,
            label: 'Email (необязательно)',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          _ProfileAddressField(
            key: const Key('address-city'),
            controller: _city,
            label: 'Город',
            textInputAction: TextInputAction.next,
          ),
          _ProfileAddressField(
            key: const Key('address-line'),
            controller: _address,
            label: 'Улица, дом, квартира',
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              key: const Key('save-profile-address'),
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.black38,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _isSaving ? 'СОХРАНЯЕМ' : 'СОХРАНИТЬ АДРЕС',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text('пункт выдачи', style: _featureTitleStyle),
          const SizedBox(height: 10),
          if (hasPickup)
            Container(
              key: const Key('saved-pickup-point'),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.store_mall_directory_outlined, size: 21),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile.pickupPointName.trim().isEmpty
                              ? 'Выбранный пункт'
                              : _profile.pickupPointName.trim(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _profile.pickupPointAddress.trim(),
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('clear-saved-pickup-point'),
                    tooltip: 'Удалить пункт',
                    onPressed: _clearPickupPoint,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
          else ...[
            const Text(
              'Пункт выдачи выбирается при оформлении заказа и не заменяет домашний адрес.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: widget.onOpenCatalog,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('ПЕРЕЙТИ В КАТАЛОГ'),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ProfileAddressField extends StatelessWidget {
  const _ProfileAddressField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF7F7F8),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 1.3),
          ),
        ),
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
    required this.onShareProduct,
    required this.onToggleProductLike,
    required this.onOpenCatalog,
  });

  final List<AppOrder> orders;
  final List<Product> recommendedProducts;
  final String currentUserId;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product> onShareProduct;
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
              onShareProduct: widget.onShareProduct,
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
  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return _PlainProfilePage(
      title: 'дашборд продавца',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.all_inclusive_rounded, size: 17, color: _ink),
                SizedBox(width: 7),
                Text(
                  'За весь период',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: AppTypography.semiBold,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Статистика рассчитана по всем заказам аккаунта.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11.5,
              fontWeight: AppTypography.medium,
              color: _muted,
            ),
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
                  title: 'ОТМЕНЫ И ВОЗВРАТЫ',
                  value: '${stats.returnsPercent.round()}%',
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
    required this.onShareProduct,
    required this.onToggleLike,
  });

  final List<Product> products;
  final VoidCallback onOpenCatalog;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product> onShareProduct;
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
                onMenu: () => onProductTap(product),
                onShare: () => onShareProduct(product),
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

class _SellerScoreCard extends StatelessWidget {
  const _SellerScoreCard({required this.stats});

  final SellerDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final rating = stats.rating.clamp(0, 5).toDouble();
    final hasRating = stats.ordersCount > 0 && rating > 0;
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
                hasRating ? rating.toStringAsFixed(1) : '—',
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
                  hasRating ? '/5.0' : 'нет завершённых сделок',
                  style: _featureBodyStyle.copyWith(
                    fontSize: hasRating ? 14 : 12,
                    color: Colors.white,
                  ),
                ),
              ),
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
                const Icon(Icons.info_outline_rounded, size: 18, color: _lime),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Комиссия платформы будет показана после утверждения тарифов и подключения безопасной сделки.',
                    style: _featureSmallStyle.copyWith(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Colors.white,
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    this.isAccent = false,
  });

  final String title;
  final String value;
  final bool isAccent;

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
              color: foreground,
            ),
          ),
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
