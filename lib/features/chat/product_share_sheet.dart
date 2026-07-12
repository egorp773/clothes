import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_profile.dart';
import '../../models/message_thread.dart';
import '../../models/product.dart';
import '../../widgets/app_image.dart';

const _shareInk = Color(0xFF0B0B0C);
const _shareMuted = Color(0xFF74747C);
const _shareLine = Color(0xFFE9E9EC);
const _shareSoft = Color(0xFFF5F5F6);
const _shareAccent = Color(0xFFFF3158);

Future<void> showProductShareSheet(
  BuildContext context, {
  required Product product,
  required List<MessageThread> threads,
  required String currentUserId,
  required Future<List<AppUserProfile>> Function(String query) searchUsers,
  required Future<bool> Function(String threadId, Product product)
  shareToThread,
  required Future<MessageThread?> Function(
    AppUserProfile recipient,
    Product product,
  )
  shareToUser,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (context) => _ProductShareSheet(
      product: product,
      threads: threads,
      currentUserId: currentUserId,
      searchUsers: searchUsers,
      shareToThread: shareToThread,
      shareToUser: shareToUser,
    ),
  );
}

class _ProductShareSheet extends StatefulWidget {
  const _ProductShareSheet({
    required this.product,
    required this.threads,
    required this.currentUserId,
    required this.searchUsers,
    required this.shareToThread,
    required this.shareToUser,
  });

  final Product product;
  final List<MessageThread> threads;
  final String currentUserId;
  final Future<List<AppUserProfile>> Function(String query) searchUsers;
  final Future<bool> Function(String threadId, Product product) shareToThread;
  final Future<MessageThread?> Function(
    AppUserProfile recipient,
    Product product,
  )
  shareToUser;

  @override
  State<_ProductShareSheet> createState() => _ProductShareSheetState();
}

class _ProductShareSheetState extends State<_ProductShareSheet> {
  final _searchController = TextEditingController();
  final Set<String> _selectedThreadIds = {};
  final Map<String, AppUserProfile> _selectedUsers = {};
  Timer? _debounce;
  List<AppUserProfile> _searchResults = const [];
  bool _searching = false;
  bool _sending = false;

  List<MessageThread> get _recentThreads {
    final result =
        widget.threads
            .where(
              (thread) =>
                  thread.containsUser(widget.currentUserId) &&
                  (thread.isGroup ||
                      thread.otherPartyId(widget.currentUserId).isNotEmpty),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result.take(12).toList(growable: false);
  }

  int get _selectionCount => _selectedThreadIds.length + _selectedUsers.length;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.replaceAll('@', '').length < 2) {
      setState(() {
        _searching = false;
        _searchResults = const [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final results = await widget.searchUsers(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    });
  }

  void _toggleThread(MessageThread thread) {
    setState(() {
      if (!_selectedThreadIds.remove(thread.id)) {
        _selectedThreadIds.add(thread.id);
      }
    });
  }

  void _toggleUser(AppUserProfile user) {
    setState(() {
      if (_selectedUsers.containsKey(user.id)) {
        _selectedUsers.remove(user.id);
      } else {
        _selectedUsers[user.id] = user;
      }
    });
  }

  Future<void> _send() async {
    if (_selectionCount == 0 || _sending) return;
    setState(() => _sending = true);
    var sent = 0;
    var failed = 0;
    for (final threadId in _selectedThreadIds) {
      if (await widget.shareToThread(threadId, widget.product)) {
        sent++;
      } else {
        failed++;
      }
    }
    for (final user in _selectedUsers.values) {
      if (await widget.shareToUser(user, widget.product) != null) {
        sent++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    final message = failed == 0
        ? 'Отправлено: $sent'
        : 'Отправлено: $sent, не удалось: $failed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      ClipboardData(text: 'https://clothes.app/products/${widget.product.id}'),
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(maxHeight: height * 0.84),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Handle(),
                _Header(product: widget.product),
                const Divider(height: 1, color: _shareLine),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_recentThreads.isNotEmpty) ...[
                          const Text(
                            'Недавние',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _shareInk,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 104,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: _recentThreads.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, index) {
                                final thread = _recentThreads[index];
                                return _RecentRecipient(
                                  thread: thread,
                                  currentUserId: widget.currentUserId,
                                  selected: _selectedThreadIds.contains(
                                    thread.id,
                                  ),
                                  onTap: () => _toggleThread(thread),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _SearchField(
                          controller: _searchController,
                          onChanged: _search,
                        ),
                        if (_searching)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _shareInk,
                              ),
                            ),
                          )
                        else if (_searchResults.isNotEmpty)
                          ..._searchResults.map(
                            (user) => _UserResult(
                              user: user,
                              selected: _selectedUsers.containsKey(user.id),
                              onTap: () => _toggleUser(user),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _ShareAction(
                              icon: Icons.link_rounded,
                              label: 'Копировать',
                              onTap: _copyLink,
                            ),
                            const SizedBox(width: 18),
                            _ShareAction(
                              icon: Icons.more_horiz_rounded,
                              label: 'Ещё',
                              onTap: _copyLink,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _selectionCount == 0
                      ? const SizedBox.shrink()
                      : Container(
                          key: const ValueKey('share-send-bar'),
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(top: BorderSide(color: _shareLine)),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton(
                              onPressed: _sending ? null : _send,
                              style: FilledButton.styleFrom(
                                backgroundColor: _shareInk,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _shareInk,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Отправить · $_selectionCount',
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD8D8DC),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 12, 14),
      child: Row(
        children: [
          AppImage(
            imageUrl: product.image,
            width: 54,
            height: 66,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Поделиться объявлением',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _shareInk,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${product.title} · ${product.price}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.2,
                    color: _shareMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _shareInk),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Найти по @username',
        hintStyle: const TextStyle(color: Color(0xFF96969D)),
        prefixIcon: const Icon(Icons.search_rounded, color: _shareMuted),
        filled: true,
        fillColor: _shareSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _RecentRecipient extends StatelessWidget {
  const _RecentRecipient({
    required this.thread,
    required this.currentUserId,
    required this.selected,
    required this.onTap,
  });

  final MessageThread thread;
  final String currentUserId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = thread.displayTitle(currentUserId);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            _RecipientAvatar(
              imageUrl: thread.isProductChat
                  ? thread.productImage
                  : thread.displayAvatar(currentUserId),
              name: thread.isProductChat ? thread.productTitle : title,
              badgeImage: thread.isProductChat
                  ? thread.displayAvatar(currentUserId)
                  : '',
              isProduct: thread.isProductChat,
              selected: selected,
              isGroup: thread.isGroup,
              members: thread.members,
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.1,
                color: _shareInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar({
    required this.imageUrl,
    required this.name,
    required this.selected,
    this.badgeImage = '',
    this.isProduct = false,
    this.isGroup = false,
    this.members = const [],
  });

  final String imageUrl;
  final String name;
  final bool selected;
  final String badgeImage;
  final bool isProduct;
  final bool isGroup;
  final List<ConversationMember> members;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 58,
      height: 58,
      padding: EdgeInsets.all(selected ? 2 : 0),
      decoration: BoxDecoration(
        shape: isProduct ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isProduct ? BorderRadius.circular(14) : null,
        border: Border.all(
          color: selected ? _shareAccent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isProduct ? 12 : 999),
              child: imageUrl.isNotEmpty
                  ? AppImage(imageUrl: imageUrl, fit: BoxFit.cover)
                  : isGroup && members.length >= 2
                  ? _GroupInitials(members: members)
                  : ColoredBox(
                      color: _shareSoft,
                      child: Center(
                        child: Text(
                          name.trim().isEmpty
                              ? '?'
                              : name.trim().characters.first.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: _shareInk,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (selected)
            const Positioned(
              right: -2,
              top: -2,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: _shareAccent,
                child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
              ),
            ),
          if (badgeImage.isNotEmpty)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 21,
                height: 21,
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: AppImage(imageUrl: badgeImage, fit: BoxFit.cover),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupInitials extends StatelessWidget {
  const _GroupInitials({required this.members});

  final List<ConversationMember> members;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF202124),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.45, -0.35),
            child: _InitialDot(member: members.first),
          ),
          Align(
            alignment: const Alignment(0.45, 0.35),
            child: _InitialDot(member: members[1]),
          ),
        ],
      ),
    );
  }
}

class _InitialDot extends StatelessWidget {
  const _InitialDot({required this.member});

  final ConversationMember member;

  @override
  Widget build(BuildContext context) {
    final initial = member.name.trim().isEmpty
        ? '?'
        : member.name.trim().characters.first.toUpperCase();
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _UserResult extends StatelessWidget {
  const _UserResult({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final AppUserProfile user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      leading: _RecipientAvatar(
        imageUrl: user.avatarUrl,
        name: user.name,
        selected: selected,
      ),
      title: Text(
        user.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, color: _shareInk),
      ),
      subtitle: Text(user.handle, style: const TextStyle(color: _shareMuted)),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 25,
        height: 25,
        decoration: BoxDecoration(
          color: selected ? _shareInk : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _shareInk : const Color(0xFFD4D4D8),
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

class _ShareAction extends StatelessWidget {
  const _ShareAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: _shareSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _shareInk, size: 23),
          ),
          const SizedBox(height: 7),
          Text(label, style: const TextStyle(fontSize: 12, color: _shareInk)),
        ],
      ),
    );
  }
}
