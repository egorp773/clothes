import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/message_thread.dart';
import '../widgets/app_image.dart';

const _ink = Color(0xFF070707);
const _muted = Color(0xFF7A7A82);
const _line = Color(0xFFE8E8EA);
const _soft = Color(0xFFF5F5F6);
const _chatBg = Color(0xFFF1F2F4);

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    required this.threads,
    required this.onSendMessage,
    required this.onSearchUsers,
    required this.onStartDirectChat,
    required this.currentUserId,
    required this.threadsListenable,
    required this.resolveThread,
  });

  final List<MessageThread> threads;
  final Future<void> Function(String threadId, String text) onSendMessage;
  final Future<List<AppUserProfile>> Function(String query) onSearchUsers;
  final Future<MessageThread?> Function(AppUserProfile user) onStartDirectChat;
  final String currentUserId;
  final Listenable threadsListenable;
  final MessageThread? Function(String threadId) resolveThread;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<AppUserProfile> _searchResults = const [];
  bool _isSearching = false;
  String _query = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() => _query = value.trim());
    _searchDebounce = Timer(const Duration(milliseconds: 240), () async {
      final clean = _query.replaceAll('@', '');
      if (clean.length < 2) {
        if (!mounted) return;
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
        return;
      }

      if (mounted) setState(() => _isSearching = true);
      final results = await widget.onSearchUsers(_query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  Future<void> _openThread(MessageThread thread) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(
          thread: thread,
          onSendMessage: widget.onSendMessage,
          currentUserId: widget.currentUserId,
          threadsListenable: widget.threadsListenable,
          resolveThread: widget.resolveThread,
        ),
      ),
    );
  }

  Future<void> _openUser(AppUserProfile user) async {
    final thread = await widget.onStartDirectChat(user);
    if (!mounted || thread == null) return;
    _searchController.clear();
    setState(() {
      _query = '';
      _searchResults = const [];
    });
    await _openThread(thread);
  }

  @override
  Widget build(BuildContext context) {
    final isSearchMode = _query.isNotEmpty;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          _MessagesHeader(
            controller: _searchController,
            onChanged: _onSearchChanged,
            totalThreads: widget.threads.length,
          ),
          Expanded(
            child: isSearchMode
                ? _SearchResults(
                    isSearching: _isSearching,
                    query: _query,
                    results: _searchResults,
                    onTapUser: _openUser,
                  )
                : widget.threads.isEmpty
                ? const _EmptyMessages()
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 112),
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.threads.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 84, color: _line),
                    itemBuilder: (context, index) {
                      final thread = widget.threads[index];
                      return _ThreadTile(
                        thread: thread,
                        currentUserId: widget.currentUserId,
                        onTap: () => _openThread(thread),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({
    required this.controller,
    required this.onChanged,
    required this.totalThreads,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int totalThreads;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(18, topInset + 14, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Сообщения',
                  style: TextStyle(
                    fontSize: 25,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _soft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    totalThreads.toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SearchField(controller: controller, onChanged: onChanged),
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
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Найти человека по @username',
          hintStyle: const TextStyle(color: Color(0xFF9A9AA1)),
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: Color(0xFF9A9AA1),
          ),
          filled: true,
          fillColor: _soft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        style: const TextStyle(fontSize: 15, color: _ink),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.isSearching,
    required this.query,
    required this.results,
    required this.onTapUser,
  });

  final bool isSearching;
  final String query;
  final List<AppUserProfile> results;
  final ValueChanged<AppUserProfile> onTapUser;

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
      );
    }
    if (results.isEmpty) {
      return _CenteredHint(
        title: query.replaceAll('@', '').length < 2
            ? 'Введите минимум 2 символа'
            : 'Пользователь не найден',
        subtitle: 'Ищи по username, например @seller',
        icon: Icons.person_search_outlined,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 112),
      itemCount: results.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 84, color: _line),
      itemBuilder: (context, index) {
        final profile = results[index];
        return ListTile(
          onTap: () => onTapUser(profile),
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          leading: _Avatar(
            imageUrl: profile.avatarUrl,
            name: profile.name,
            isSquare: false,
          ),
          title: Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              height: 1.15,
              fontWeight: FontWeight.w500,
              color: _ink,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              profile.handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: _muted),
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFB8B8BE)),
        );
      },
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.thread,
    required this.onSendMessage,
    required this.currentUserId,
    required this.threadsListenable,
    required this.resolveThread,
  });

  final MessageThread thread;
  final Future<void> Function(String threadId, String text) onSendMessage;
  final String currentUserId;
  final Listenable threadsListenable;
  final MessageThread? Function(String threadId) resolveThread;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  late MessageThread _thread;
  late List<ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    _messages = List.of(_thread.messages);
    widget.threadsListenable.addListener(_refreshThread);
  }

  void _refreshThread() {
    final latest = widget.resolveThread(_thread.id);
    if (latest == null || !mounted) return;

    final hasChanged =
        latest.updatedAt != _thread.updatedAt ||
        latest.messages.length != _thread.messages.length ||
        latest.lastMessage != _thread.lastMessage;
    if (!hasChanged) return;

    setState(() {
      _thread = latest;
      _messages = List.of(latest.messages);
    });
  }

  @override
  void dispose() {
    widget.threadsListenable.removeListener(_refreshThread);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _messages = [
        ..._messages,
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: text,
          createdAt: DateTime.now(),
          isMine: true,
        ),
      ];
      _controller.clear();
    });

    await widget.onSendMessage(_thread.id, text);
    if (!mounted) return;
    setState(() => _isSending = false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatBg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ChatHeader(thread: _thread, currentUserId: widget.currentUserId),
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyChat(thread: _thread)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                      physics: const BouncingScrollPhysics(),
                      itemCount:
                          _messages.length + (_thread.isProductChat ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_thread.isProductChat && index == 0) {
                          return _ProductContextCard(thread: _thread);
                        }
                        final messageIndex =
                            index - (_thread.isProductChat ? 1 : 0);
                        final message = _messages[messageIndex];
                        final previous = messageIndex == 0
                            ? null
                            : _messages[messageIndex - 1];
                        final showDate =
                            previous == null ||
                            !_isSameDay(previous.createdAt, message.createdAt);
                        return Column(
                          children: [
                            if (showDate) _DateChip(date: message.createdAt),
                            _MessageBubble(message: message),
                            const SizedBox(height: 6),
                          ],
                        );
                      },
                    ),
            ),
            _MessageComposer(
              controller: _controller,
              isSending: _isSending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return const _CenteredHint(
      title: 'Пока нет сообщений',
      subtitle: 'Напиши продавцу по вещи или найди человека по username.',
      icon: Icons.mode_comment_outlined,
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: _soft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: _ink),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _ink,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.35, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.currentUserId,
    required this.onTap,
  });

  final MessageThread thread;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = thread.otherPartyName(currentUserId);
    final subtitle = thread.isProductChat
        ? thread.productTitle
        : thread.otherPartyHandle(currentUserId);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
        child: Row(
          children: [
            _ThreadAvatar(thread: thread, currentUserId: currentUserId),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            color: _ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeLabel(thread.updatedAt),
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    thread.lastMessage.isEmpty
                        ? 'Напишите сообщение'
                        : thread.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: thread.lastMessage.isEmpty ? _muted : _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadAvatar extends StatelessWidget {
  const _ThreadAvatar({required this.thread, required this.currentUserId});

  final MessageThread thread;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    if (thread.isProductChat) {
      return _Avatar(
        imageUrl: thread.productImage,
        name: thread.productTitle,
        isSquare: true,
      );
    }
    return _Avatar(
      imageUrl: thread.otherPartyAvatar(currentUserId),
      name: thread.otherPartyName(currentUserId),
      isSquare: false,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.imageUrl,
    required this.name,
    required this.isSquare,
  });

  final String imageUrl;
  final String name;
  final bool isSquare;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(isSquare ? 10 : 999);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: _soft,
          border: isSquare ? Border.all(color: _line) : null,
        ),
        child: imageUrl.isNotEmpty
            ? AppImage(
                imageUrl: imageUrl,
                width: 54,
                height: 54,
                fit: isSquare ? BoxFit.fill : BoxFit.cover,
                alignment: Alignment.center,
              )
            : Center(
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
              ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1 || parts[1].isEmpty) return first.toUpperCase();
    return (first + parts[1].characters.first).toUpperCase();
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.thread, required this.currentUserId});

  final MessageThread thread;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final subtitle = thread.isProductChat
        ? thread.productTitle
        : thread.otherPartyHandle(currentUserId);
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Container(
      height: topInset + 62,
      padding: EdgeInsets.fromLTRB(4, topInset + 4, 12, 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: _ink),
          ),
          _ThreadAvatar(thread: thread, currentUserId: currentUserId),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.otherPartyName(currentUserId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_horiz, color: _ink),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.thread});

  final MessageThread thread;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        if (thread.isProductChat) _ProductContextCard(thread: thread),
        const SizedBox(height: 88),
        const Center(
          child: Text(
            'Начните диалог',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductContextCard extends StatelessWidget {
  const _ProductContextCard({required this.thread});

  final MessageThread thread;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 58,
                height: 58,
                child: thread.productImage.isEmpty
                    ? const ColoredBox(
                        color: _soft,
                        child: Icon(Icons.checkroom_outlined, color: _muted),
                      )
                    : AppImage(
                        imageUrl: thread.productImage,
                        width: 58,
                        height: 58,
                        fit: BoxFit.fill,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Диалог по вещи',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.productTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.18,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _dateLabel(date),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isMine ? _ink : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 5),
              bottomRight: Radius.circular(isMine ? 5 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 8, 10, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.24,
                    color: isMine ? Colors.white : _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _timeLabel(message.createdAt),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.64)
                        : const Color(0xFF9A9AA1),
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

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Сообщение',
                    hintStyle: const TextStyle(color: Color(0xFF9A9AA1)),
                    prefixIcon: const Icon(
                      Icons.add,
                      size: 22,
                      color: Color(0xFF9A9AA1),
                    ),
                    border: InputBorder.none,
                    filled: true,
                    fillColor: _soft,
                    contentPadding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 15, color: _ink),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isSending ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSending ? const Color(0xFF9A9AA1) : _ink,
                  shape: BoxShape.circle,
                ),
                child: isSending
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward,
                        size: 21,
                        color: Colors.white,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _timeLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _dateLabel(DateTime value) {
  final now = DateTime.now();
  if (_isSameDay(value, now)) return 'Сегодня';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(value, yesterday)) return 'Вчера';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}
