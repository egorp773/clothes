import 'package:flutter/material.dart';

import '../../models/message_thread.dart';
import '../../widgets/app_image.dart';
import 'chat_actions.dart';
import 'chat_avatar.dart';
import 'chat_tokens.dart';

enum ConversationInfoResult { search }

class ConversationInfoScreen extends StatefulWidget {
  const ConversationInfoScreen({
    super.key,
    required this.thread,
    required this.currentUserId,
    this.actions,
    this.onOpenProduct,
    this.onOpenSeller,
  });

  final MessageThread thread;
  final String currentUserId;
  final ChatActions? actions;
  final void Function(String productId)? onOpenProduct;
  final VoidCallback? onOpenSeller;

  @override
  State<ConversationInfoScreen> createState() => _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<ConversationInfoScreen> {
  late bool _isMuted;
  late bool _isPinned;
  late bool _isArchived;
  late String _title;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.thread.isMuted;
    _isPinned = widget.thread.isPinned;
    _isArchived = widget.thread.isArchived;
    _title = widget.thread.displayTitle(widget.currentUserId);
  }

  Future<void> _update({
    bool? isMuted,
    bool? isPinned,
    bool? isArchived,
    String? title,
  }) async {
    if (_saving) return;
    final callback = widget.actions?.updateThread;
    if (callback == null) return;
    setState(() {
      _saving = true;
      if (isMuted != null) _isMuted = isMuted;
      if (isPinned != null) _isPinned = isPinned;
      if (isArchived != null) _isArchived = isArchived;
      if (title != null && title.trim().isNotEmpty) _title = title.trim();
    });
    final saved = await callback(
      widget.thread.id,
      isMuted: isMuted,
      isPinned: isPinned,
      isArchived: isArchived,
      title: title,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      setState(() {
        _isMuted = widget.thread.isMuted;
        _isPinned = widget.thread.isPinned;
        _isArchived = widget.thread.isArchived;
        _title = widget.thread.displayTitle(widget.currentUserId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить настройку'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rename() async {
    if (!widget.thread.isGroup || widget.actions?.updateThread == null) return;
    final controller = TextEditingController(text: _title);
    final nextTitle = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: _SheetHandle()),
                    const SizedBox(height: 18),
                    const Text(
                      'Название беседы',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: ChatTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Введите название',
                        filled: true,
                        fillColor: ChatTokens.soft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: ChatTokens.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Сохранить',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (nextTitle == null || nextTitle.isEmpty || nextTitle == _title) return;
    await _update(title: nextTitle);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.thread.isGroup
        ? widget.thread.displaySubtitle(widget.currentUserId)
        : widget.thread.otherPartyHandle(widget.currentUserId);
    final images = widget.thread.messages
        .where((message) => message.isImage && !message.isDeleted)
        .map((message) => message.attachment?.url ?? '')
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final products = widget.thread.messages
        .where((message) => message.isProductShare && !message.isDeleted)
        .map((message) => message.sharedProduct!)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: ChatTokens.background,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                child: Column(
                  children: [
                    Hero(
                      tag: 'chat-avatar-${widget.thread.id}',
                      child: ChatAvatar.thread(
                        thread: widget.thread,
                        currentUserId: widget.currentUserId,
                        size: 92,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              color: ChatTokens.ink,
                            ),
                          ),
                        ),
                        if (widget.thread.isGroup &&
                            widget.actions?.updateThread != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _rename,
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: ChatTokens.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (widget.onOpenSeller != null) ...[
                          _QuickAction(
                            icon: Icons.person_outline_rounded,
                            label: 'Профиль',
                            onTap: widget.onOpenSeller,
                          ),
                          const SizedBox(width: 10),
                        ],
                        _QuickAction(
                          icon: Icons.search_rounded,
                          label: 'Поиск',
                          onTap: () => Navigator.pop(
                            context,
                            ConversationInfoResult.search,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _QuickAction(
                          icon: _isMuted
                              ? Icons.notifications_off_rounded
                              : Icons.notifications_none_rounded,
                          label: _isMuted ? 'Без звука' : 'Уведомления',
                          selected: _isMuted,
                          onTap: widget.actions?.updateThread == null
                              ? null
                              : () => _update(isMuted: !_isMuted),
                        ),
                        const SizedBox(width: 10),
                        _QuickAction(
                          icon: _isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          label: _isPinned ? 'Закреплён' : 'Закрепить',
                          selected: _isPinned,
                          onTap: widget.actions?.updateThread == null
                              ? null
                              : () => _update(isPinned: !_isPinned),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (widget.thread.isProductChat)
              SliverToBoxAdapter(
                child: _SectionCard(
                  title: 'Объявление',
                  child: _ProductContext(
                    thread: widget.thread,
                    onTap: widget.onOpenProduct == null
                        ? null
                        : () => widget.onOpenProduct!(widget.thread.productId),
                  ),
                ),
              ),
            if (widget.thread.isGroup)
              SliverToBoxAdapter(
                child: _SectionCard(
                  title: 'Участники · ${widget.thread.memberIds.length}',
                  child: Column(
                    children: widget.thread.members
                        .map(
                          (member) => _MemberRow(
                            member: member,
                            isCurrent: member.id == widget.currentUserId,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            if (images.isNotEmpty || products.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionCard(
                  title: 'Медиа и объявления',
                  child: _MediaGrid(
                    images: images,
                    products: products,
                    onOpenProduct: widget.onOpenProduct,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _SectionCard(
                title: 'Настройки',
                child: Column(
                  children: [
                    _SettingRow(
                      icon: Icons.push_pin_outlined,
                      title: 'Закрепить чат',
                      value: _isPinned,
                      onChanged: widget.actions?.updateThread == null
                          ? null
                          : (value) => _update(isPinned: value),
                    ),
                    const Divider(
                      height: 1,
                      indent: 48,
                      color: ChatTokens.line,
                    ),
                    _SettingRow(
                      icon: Icons.notifications_off_outlined,
                      title: 'Без звука',
                      value: _isMuted,
                      onChanged: widget.actions?.updateThread == null
                          ? null
                          : (value) => _update(isMuted: value),
                    ),
                    const Divider(
                      height: 1,
                      indent: 48,
                      color: ChatTokens.line,
                    ),
                    _SettingRow(
                      icon: Icons.archive_outlined,
                      title: 'В архиве',
                      value: _isArchived,
                      onChanged: widget.actions?.updateThread == null
                          ? null
                          : (value) => _update(isArchived: value),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Container(
      height: topInset + 58,
      padding: EdgeInsets.fromLTRB(4, topInset + 2, 12, 2),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          const Expanded(
            child: Text(
              'Информация',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ChatTokens.ink,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ChatTokens.ink,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: ChatTokens.fast,
          height: 72,
          decoration: BoxDecoration(
            color: selected ? ChatTokens.ink : ChatTokens.soft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : ChatTokens.ink,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? Colors.white : ChatTokens.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ChatTokens.muted,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ProductContext extends StatelessWidget {
  const _ProductContext({required this.thread, this.onTap});

  final MessageThread thread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: ChatTokens.soft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AppImage(
              imageUrl: thread.productImage,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(11),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                thread.productTitle.trim().isEmpty
                    ? 'Объявление из чата'
                    : thread.productTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: ChatTokens.ink,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: ChatTokens.muted),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isCurrent});

  final ConversationMember member;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ChatAvatar(imageUrl: member.avatarUrl, name: member.name, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrent ? '${member.name} · вы' : member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: ChatTokens.ink,
                  ),
                ),
                if (member.handle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    member.handle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: ChatTokens.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.images,
    required this.products,
    required this.onOpenProduct,
  });

  final List<String> images;
  final List<SharedProductPreview> products;
  final void Function(String productId)? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final items = <({String image, String productId})>[
      ...images.map((image) => (image: image, productId: '')),
      ...products.map(
        (product) => (image: product.image, productId: product.id),
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: item.productId.isEmpty || onOpenProduct == null
              ? null
              : () => onOpenProduct!(item.productId),
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppImage(
                imageUrl: item.image,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(10),
              ),
              if (item.productId.isNotEmpty)
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: ChatTokens.ink,
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          Icon(icon, size: 21, color: ChatTokens.ink),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14.5, color: ChatTokens.ink),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: ChatTokens.ink,
            inactiveTrackColor: const Color(0xFFD8D8DC),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFD7D7DB),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
