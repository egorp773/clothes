import 'package:flutter/material.dart';

import '../models/message_thread.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({
    super.key,
    required this.threads,
    required this.onSendMessage,
    required this.currentUserId,
    required this.threadsListenable,
    required this.resolveThread,
  });

  final List<MessageThread> threads;
  final Future<void> Function(String threadId, String text) onSendMessage;
  final String currentUserId;
  final Listenable threadsListenable;
  final MessageThread? Function(String threadId) resolveThread;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 14, left: 18, right: 18),
          child: Text(
            'Сообщения',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF070707),
            ),
          ),
        ),
        Expanded(
          child: threads.isEmpty
              ? const _EmptyMessages()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
                  physics: const BouncingScrollPhysics(),
                  itemCount: threads.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    return _ThreadTile(
                      thread: thread,
                      currentUserId: currentUserId,
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (context) => ChatScreen(
                              thread: thread,
                              onSendMessage: onSendMessage,
                              currentUserId: currentUserId,
                              threadsListenable: threadsListenable,
                              resolveThread: resolveThread,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
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
    _messages = _thread.messages.isNotEmpty
        ? List.of(_thread.messages)
        : [
            ChatMessage(
              id: '${_thread.id}-initial',
              text: _thread.lastMessage,
              createdAt: _thread.updatedAt,
              isMine: true,
            ),
          ];
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
      _messages = latest.messages.isNotEmpty
          ? List.of(latest.messages)
          : [
              ChatMessage(
                id: '${latest.id}-initial',
                text: latest.lastMessage,
                createdAt: latest.updatedAt,
                isMine: true,
              ),
            ];
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(thread: _thread, currentUserId: widget.currentUserId),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                physics: const BouncingScrollPhysics(),
                itemCount: _messages.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  return _MessageBubble(message: _messages[index]);
                },
              ),
            ),
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _MessageComposer(
                controller: _controller,
                isSending: _isSending,
                onSend: _send,
              ),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF3F3F4),
            ),
            child: const Center(
              child: Icon(
                Icons.chat_bubble_outline,
                size: 40,
                color: Color(0xFF050505),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Пока нет сообщений',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF070707),
            ),
          ),
          const SizedBox(height: 9),
          const SizedBox(
            width: 280,
            child: Text(
              'Здесь появятся диалоги с другими пользователями.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF85858B),
                height: 1.35,
              ),
            ),
          ),
        ],
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE9E9EC)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF3F3F4),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 24,
                color: Color(0xFF050505),
              ),
            ),
            const SizedBox(width: 12),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF070707),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.productTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF111111),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 22, color: Color(0xFFB8B8BE)),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.thread, required this.currentUserId});

  final MessageThread thread;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE9E9EC))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          ),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF070707),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  thread.productTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8F8F94),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: message.isMine ? Colors.black : const Color(0xFFF3F3F4),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              color: message.isMine ? Colors.white : const Color(0xFF111111),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE9E9EC))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Сообщение',
                  hintStyle: const TextStyle(color: Color(0xFF8F8F94)),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: const Color(0xFFF4F4F5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: isSending ? null : onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSending ? const Color(0xFF8E8E93) : Colors.black,
                shape: BoxShape.circle,
              ),
              child: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward,
                      size: 20,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
