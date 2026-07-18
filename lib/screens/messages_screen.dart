import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_appearance.dart';
import '../core/app_typography.dart';
import 'package:video_player/video_player.dart';

import '../features/chat/chat_actions.dart';
import '../features/chat/chat_avatar.dart';
import '../features/chat/conversation_info_screen.dart';
import '../models/app_profile.dart';
import '../models/message_thread.dart';
import '../widgets/app_glass_surface.dart';
import '../widgets/app_image.dart';

enum _InboxFilter { all, unread, purchases, archived }

enum _AttachmentChoice { imageGallery, videoGallery, imageCamera, videoCamera }

void _logChatUiFailure(String operation, Object error, StackTrace stackTrace) {
  debugPrint('Chat UI $operation error: $error');
  debugPrintStack(stackTrace: stackTrace);
}

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    required this.threads,
    required this.onSendMessage,
    required this.onSearchUsers,
    required this.onStartDirectChat,
    required this.onCreateConversation,
    this.onOpenProduct,
    required this.currentUserId,
    required this.threadsListenable,
    required this.resolveThread,
    required this.lastSeenForUser,
    this.actions,
    this.onOpenSellerProfile,
    this.onBuyProduct,
    this.isLoading = false,
    this.errorMessage,
    this.isAuthenticated = true,
    this.onRetryLoad,
    this.onSignIn,
  });

  final List<MessageThread> threads;
  final Future<void> Function(String threadId, String text) onSendMessage;
  final Future<List<AppUserProfile>> Function(String query) onSearchUsers;
  final Future<MessageThread?> Function(AppUserProfile user) onStartDirectChat;
  final Future<MessageThread?> Function(
    List<AppUserProfile> users, {
    String title,
  })
  onCreateConversation;
  final void Function(String productId)? onOpenProduct;
  final String currentUserId;
  final Listenable threadsListenable;
  final MessageThread? Function(String threadId) resolveThread;
  final DateTime? Function(String userId) lastSeenForUser;
  final ChatActions? actions;
  final ValueChanged<MessageThread>? onOpenSellerProfile;
  final ValueChanged<MessageThread>? onBuyProduct;
  final bool isLoading;
  final String? errorMessage;
  final bool isAuthenticated;
  final VoidCallback? onRetryLoad;
  final VoidCallback? onSignIn;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<AppUserProfile> _searchResults = const [];
  bool _isSearching = false;
  String _query = '';
  _InboxFilter _filter = _InboxFilter.all;
  final Set<String> _openingUserIds = <String>{};

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
      final requestedQuery = _query;
      final clean = requestedQuery.replaceAll('@', '');
      if (clean.length < 2) {
        if (!mounted) return;
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
        return;
      }

      if (mounted) setState(() => _isSearching = true);
      List<AppUserProfile> results;
      try {
        results = await widget.onSearchUsers(requestedQuery);
      } catch (error, stackTrace) {
        _logChatUiFailure('search users', error, stackTrace);
        results = const [];
      }
      if (!mounted || requestedQuery != _query) return;
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
          onOpenProduct: widget.onOpenProduct,
          currentUserId: widget.currentUserId,
          threadsListenable: widget.threadsListenable,
          resolveThread: widget.resolveThread,
          lastSeenForUser: widget.lastSeenForUser,
          actions: widget.actions,
          onOpenSellerProfile: widget.onOpenSellerProfile == null
              ? null
              : () => widget.onOpenSellerProfile!(thread),
          onBuyProduct: widget.onBuyProduct == null
              ? null
              : () => widget.onBuyProduct!(thread),
        ),
      ),
    );
  }

  Future<void> _openUser(AppUserProfile user) async {
    final userKey = user.id.isEmpty ? '${user.handle}:${user.name}' : user.id;
    if (!_openingUserIds.add(userKey)) return;
    final sourceRoute = ModalRoute.of(context);
    try {
      final thread = await widget.onStartDirectChat(user);
      if (!mounted ||
          sourceRoute?.isCurrent != true ||
          !TickerMode.valuesOf(context).enabled) {
        return;
      }
      if (thread == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть диалог. Попробуйте ещё раз.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      _searchController.clear();
      setState(() {
        _query = '';
        _searchResults = const [];
      });
      await _openThread(thread);
    } catch (error, stackTrace) {
      _logChatUiFailure('open direct conversation', error, stackTrace);
      if (mounted &&
          sourceRoute?.isCurrent == true &&
          TickerMode.valuesOf(context).enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть диалог. Попробуйте ещё раз.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _openingUserIds.remove(userKey);
    }
  }

  Future<void> _compose() async {
    final thread = await showModalBottomSheet<MessageThread>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _NewConversationSheet(
        onSearchUsers: widget.onSearchUsers,
        onCreateConversation: widget.onCreateConversation,
      ),
    );
    if (!mounted || thread == null) return;
    await _openThread(thread);
  }

  Future<void> _showThreadActions(MessageThread thread) async {
    final update = widget.actions?.updateThread;
    if (update == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: sheetContext.appPalette.surfaceRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.push_pin_outlined),
                title: Text(thread.isPinned ? 'Открепить' : 'Закрепить'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    _applyThreadUpdate(
                      update,
                      thread.id,
                      isPinned: !thread.isPinned,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.notifications_off_outlined),
                title: Text(
                  thread.isMuted ? 'Включить звук' : 'Выключить звук',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    _applyThreadUpdate(
                      update,
                      thread.id,
                      isMuted: !thread.isMuted,
                    ),
                  );
                },
              ),
              if (thread.unreadCount > 0)
                ListTile(
                  leading: Icon(Icons.mark_chat_read_outlined),
                  title: Text('Отметить прочитанным'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_markThreadReadFromInbox(thread.id));
                  },
                ),
              ListTile(
                leading: Icon(
                  thread.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  thread.isArchived ? 'Вернуть из архива' : 'В архив',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    _applyThreadUpdate(
                      update,
                      thread.id,
                      isArchived: !thread.isArchived,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyThreadUpdate(
    UpdateThreadCallback update,
    String threadId, {
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
  }) async {
    var saved = false;
    try {
      saved = await update(
        threadId,
        isPinned: isPinned,
        isMuted: isMuted,
        isArchived: isArchived,
      );
    } catch (error, stackTrace) {
      _logChatUiFailure('update conversation', error, stackTrace);
      saved = false;
    }
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось изменить настройки чата'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _markThreadReadFromInbox(String threadId) async {
    final markRead = widget.actions?.markRead;
    if (markRead == null) return;
    try {
      await markRead(threadId);
    } catch (error, stackTrace) {
      _logChatUiFailure('mark conversation read', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить статус прочтения'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSearchMode = _query.isNotEmpty;
    final allThreads = widget.threads
        .where((thread) => _shouldShowThread(thread, widget.currentUserId))
        .toList();
    final visibleThreads =
        allThreads.where((thread) {
          return switch (_filter) {
            _InboxFilter.all => !thread.isArchived,
            _InboxFilter.unread => !thread.isArchived && thread.unreadCount > 0,
            _InboxFilter.purchases =>
              !thread.isArchived && thread.isProductChat,
            _InboxFilter.archived => thread.isArchived,
          };
        }).toList()..sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    final localMatches = _query.isEmpty
        ? const <MessageThread>[]
        : allThreads.where((thread) {
            final query = _query.toLowerCase();
            return thread
                    .displayTitle(widget.currentUserId)
                    .toLowerCase()
                    .contains(query) ||
                thread.lastMessage.toLowerCase().contains(query) ||
                thread.messages.any(
                  (message) =>
                      message.previewText.toLowerCase().contains(query),
                );
          }).toList();
    final errorText = widget.errorMessage?.trim() ?? '';
    final hasCachedThreads = allThreads.isNotEmpty;
    final Widget content;
    if (!widget.isAuthenticated) {
      content = _InboxStatus(
        icon: Icons.lock_outline_rounded,
        title: 'Войдите, чтобы открыть сообщения',
        subtitle: 'Диалоги и черновики доступны только в вашем профиле.',
        actionLabel: widget.onSignIn == null ? null : 'Войти',
        onAction: widget.onSignIn,
      );
    } else if (widget.isLoading && !hasCachedThreads) {
      content = const _InboxStatus(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Загружаем диалоги',
        subtitle: 'Это займёт несколько секунд.',
        isLoading: true,
      );
    } else if (errorText.isNotEmpty && !hasCachedThreads) {
      content = _InboxStatus(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось загрузить сообщения',
        subtitle: errorText,
        actionLabel: widget.onRetryLoad == null ? null : 'Повторить',
        onAction: widget.onRetryLoad,
      );
    } else if (isSearchMode) {
      content = _SearchResults(
        isSearching: _isSearching,
        query: _query,
        results: _searchResults,
        onTapUser: _openUser,
        threads: localMatches,
        currentUserId: widget.currentUserId,
        onTapThread: _openThread,
      );
    } else if (visibleThreads.isEmpty) {
      content = const _EmptyMessages();
    } else {
      content = ListView.separated(
        padding: const EdgeInsets.only(bottom: 112),
        physics: const BouncingScrollPhysics(),
        itemCount: visibleThreads.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, indent: 84, color: context.appPalette.border),
        itemBuilder: (context, index) {
          final thread = visibleThreads[index];
          return _ThreadTile(
            thread: thread,
            currentUserId: widget.currentUserId,
            onTap: () => _openThread(thread),
            onLongPress: () => _showThreadActions(thread),
          );
        },
      );
    }
    // ListTile ink and backgrounds need a local Material. A ColoredBox here
    // hid those effects behind itself and triggers a framework assertion.
    return Material(
      color: context.appBackdrop.scaffoldColor,
      child: Column(
        children: [
          _MessagesHeader(
            controller: _searchController,
            onChanged: _onSearchChanged,
            totalThreads: visibleThreads.length,
            onCompose: widget.isAuthenticated && !widget.isLoading
                ? _compose
                : (widget.onSignIn ?? () {}),
            filter: _filter,
            onFilterChanged: (filter) => setState(() => _filter = filter),
            archivedCount: allThreads
                .where((thread) => thread.isArchived)
                .length,
          ),
          if (widget.isAuthenticated &&
              errorText.isNotEmpty &&
              hasCachedThreads)
            _InboxSyncErrorBanner(
              message: errorText,
              onRetry: widget.onRetryLoad,
            ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

bool _shouldShowThread(MessageThread thread, String currentUserId) {
  if (currentUserId.isNotEmpty && !thread.containsUser(currentUserId)) {
    return false;
  }
  final title = thread.displayTitle(currentUserId).trim();
  final hasOtherParty = currentUserId.isEmpty
      ? title.isNotEmpty
      : thread.isGroup || thread.otherPartyId(currentUserId).trim().isNotEmpty;
  return hasOtherParty;
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({
    required this.controller,
    required this.onChanged,
    required this.totalThreads,
    required this.onCompose,
    required this.filter,
    required this.onFilterChanged,
    required this.archivedCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int totalThreads;
  final VoidCallback onCompose;
  final _InboxFilter filter;
  final ValueChanged<_InboxFilter> onFilterChanged;
  final int archivedCount;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(18, topInset + 12, 18, 14),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        border: Border(
          bottom: BorderSide(color: context.appPalette.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            key: const Key('messages-header-row'),
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'сообщения',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 22,
                      height: 1,
                      fontWeight: AppTypography.bold,
                      letterSpacing: -0.4,
                      color: context.appPalette.ink,
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: onCompose,
                  style: IconButton.styleFrom(
                    overlayColor: Colors.transparent,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: Size.zero,
                    fixedSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.edit_square, size: 18),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: context.appPalette.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Text(
                      totalThreads.toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.appPalette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SearchField(controller: controller, onChanged: onChanged),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _FilterChip(
                  label: 'Все',
                  selected: filter == _InboxFilter.all,
                  onTap: () => onFilterChanged(_InboxFilter.all),
                ),
                _FilterChip(
                  label: 'Непрочитанные',
                  selected: filter == _InboxFilter.unread,
                  onTap: () => onFilterChanged(_InboxFilter.unread),
                ),
                _FilterChip(
                  label: 'Покупки',
                  selected: filter == _InboxFilter.purchases,
                  onTap: () => onFilterChanged(_InboxFilter.purchases),
                ),
                if (archivedCount > 0)
                  _FilterChip(
                    label: 'Архив · $archivedCount',
                    selected: filter == _InboxFilter.archived,
                    onTap: () => onFilterChanged(_InboxFilter.archived),
                  ),
              ],
            ),
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
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Найти человека по @username',
          hintStyle: TextStyle(color: context.appPalette.muted),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: context.appPalette.muted,
          ),
          filled: true,
          fillColor: context.appPalette.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(fontSize: 15, color: context.appPalette.ink),
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
    required this.threads,
    required this.currentUserId,
    required this.onTapThread,
  });

  final bool isSearching;
  final String query;
  final List<AppUserProfile> results;
  final ValueChanged<AppUserProfile> onTapUser;
  final List<MessageThread> threads;
  final String currentUserId;
  final ValueChanged<MessageThread> onTapThread;

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.appPalette.ink,
        ),
      );
    }
    if (results.isEmpty && threads.isEmpty) {
      return _CenteredHint(
        title: query.replaceAll('@', '').length < 2
            ? 'Введите минимум 2 символа'
            : 'Пользователь не найден',
        subtitle: 'Ищи по username, например @seller',
        icon: Icons.person_search_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        if (threads.isNotEmpty) ...[
          const _SearchSectionTitle('Чаты и сообщения'),
          ...threads.map(
            (thread) => _ThreadTile(
              thread: thread,
              currentUserId: currentUserId,
              onTap: () => onTapThread(thread),
            ),
          ),
        ],
        if (results.isNotEmpty) ...[
          const _SearchSectionTitle('Люди'),
          ...results.map(
            (profile) => ListTile(
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.appPalette.ink,
                ),
              ),
              subtitle: Text(
                profile.handle,
                style: TextStyle(fontSize: 14, color: context.appPalette.muted),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: context.appPalette.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchSectionTitle extends StatelessWidget {
  const _SearchSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.appPalette.muted,
        ),
      ),
    );
  }
}

class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet({
    required this.onSearchUsers,
    required this.onCreateConversation,
  });

  final Future<List<AppUserProfile>> Function(String query) onSearchUsers;
  final Future<MessageThread?> Function(
    List<AppUserProfile> users, {
    String title,
  })
  onCreateConversation;

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final Map<String, AppUserProfile> _selected = {};
  Timer? _debounce;
  List<AppUserProfile> _results = const [];
  bool _searching = false;
  bool _creating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _search(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.replaceAll('@', '').length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      List<AppUserProfile> results;
      try {
        results = await widget.onSearchUsers(query);
      } catch (error, stackTrace) {
        _logChatUiFailure('search conversation members', error, stackTrace);
        results = const [];
      }
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  void _toggle(AppUserProfile user) {
    setState(() {
      if (_selected.containsKey(user.id)) {
        _selected.remove(user.id);
      } else {
        _selected[user.id] = user;
      }
    });
  }

  Future<void> _create() async {
    if (_selected.isEmpty || _creating) return;
    setState(() => _creating = true);
    MessageThread? thread;
    try {
      thread = await widget.onCreateConversation(
        _selected.values.toList(growable: false),
        title: _titleController.text,
      );
    } catch (error, stackTrace) {
      _logChatUiFailure('create conversation', error, stackTrace);
      thread = null;
    }
    if (!mounted) return;
    if (thread != null) {
      Navigator.pop(context, thread);
    } else {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать беседу'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboard),
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Material(
          color: context.appPalette.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: context.appPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 5, 10, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Новая беседа',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: context.appPalette.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _SearchField(
                    controller: _searchController,
                    onChanged: _search,
                  ),
                ),
                if (_selected.isNotEmpty) ...[
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                      scrollDirection: Axis.horizontal,
                      itemCount: _selected.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final user = _selected.values.elementAt(index);
                        return GestureDetector(
                          onTap: () => _toggle(user),
                          child: SizedBox(
                            width: 58,
                            child: Stack(
                              children: [
                                _Avatar(
                                  imageUrl: user.avatarUrl,
                                  name: user.name,
                                  isSquare: false,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: CircleAvatar(
                                    radius: 9,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_selected.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                      child: TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: 'Название беседы (необязательно)',
                          filled: true,
                          fillColor: context.appPalette.surfaceMuted,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                ],
                Divider(height: 1, color: context.appPalette.border),
                Expanded(
                  child: _searching
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.appPalette.ink,
                          ),
                        )
                      : _results.isEmpty
                      ? const _CenteredHint(
                          title: 'Найдите друзей',
                          subtitle: 'Введите имя или @username',
                          icon: Icons.group_add_outlined,
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 84,
                            color: context.appPalette.border,
                          ),
                          itemBuilder: (context, index) {
                            final user = _results[index];
                            final selected = _selected.containsKey(user.id);
                            return ListTile(
                              onTap: () => _toggle(user),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 5,
                              ),
                              leading: _Avatar(
                                imageUrl: user.avatarUrl,
                                name: user.name,
                                isSquare: false,
                              ),
                              title: Text(
                                user.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: context.appPalette.ink,
                                ),
                              ),
                              subtitle: Text(user.handle),
                              trailing: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : context.appPalette.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : context.appPalette.border,
                                  ),
                                ),
                                child: selected
                                    ? Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _selected.isEmpty || _creating
                          ? null
                          : _create,
                      style: FilledButton.styleFrom(
                        overlayColor: Colors.transparent,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _creating
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : Text(
                              _selected.length > 1
                                  ? 'Создать беседу · ${_selected.length + 1}'
                                  : 'Начать диалог',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
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

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.thread,
    required this.onSendMessage,
    this.onOpenProduct,
    required this.currentUserId,
    required this.threadsListenable,
    required this.resolveThread,
    required this.lastSeenForUser,
    this.actions,
    this.onOpenSellerProfile,
    this.onBuyProduct,
  });

  final MessageThread thread;
  final Future<void> Function(String threadId, String text) onSendMessage;
  final void Function(String productId)? onOpenProduct;
  final String currentUserId;
  final Listenable threadsListenable;
  final MessageThread? Function(String threadId) resolveThread;
  final DateTime? Function(String userId) lastSeenForUser;
  final ChatActions? actions;
  final VoidCallback? onOpenSellerProfile;
  final VoidCallback? onBuyProduct;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _chatSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  Timer? _draftDebounce;
  bool _isSending = false;
  final Set<String> _retryingMessageIds = <String>{};
  bool _isMarkingRead = false;
  bool _markReadAgain = false;
  ChatMessage? _replyTo;
  ChatMessage? _editingMessage;
  bool _isChatSearching = false;
  String _chatQuery = '';
  late MessageThread _thread;
  late List<ChatMessage> _messages;
  DateTime? _lastSeenAt;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    _messages = List.of(_thread.messages);
    _lastSeenAt = widget.lastSeenForUser(
      _thread.otherPartyId(widget.currentUserId),
    );
    _controller.text = _thread.draft;
    _controller.addListener(_saveDraftLater);
    widget.threadsListenable.addListener(_refreshThread);
    unawaited(_markCurrentThreadRead());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _refreshThread() {
    final latest = widget.resolveThread(_thread.id);
    if (latest == null || !mounted) return;
    final latestLastSeen = widget.lastSeenForUser(
      latest.otherPartyId(widget.currentUserId),
    );

    final messagesChanged = _messagesChanged(latest);
    final hasChanged =
        latest.updatedAt != _thread.updatedAt ||
        messagesChanged ||
        latest.lastMessage != _thread.lastMessage ||
        latest.unreadCount != _thread.unreadCount ||
        latest.displayTitle(widget.currentUserId) !=
            _thread.displayTitle(widget.currentUserId) ||
        latest.displayAvatar(widget.currentUserId) !=
            _thread.displayAvatar(widget.currentUserId) ||
        latest.productImage != _thread.productImage ||
        latest.groupAvatar != _thread.groupAvatar ||
        _memberProfilesChanged(latest) ||
        latestLastSeen != _lastSeenAt;
    if (!hasChanged) return;

    final shouldStickToBottom = _isNearBottom;

    setState(() {
      _thread = latest;
      _messages = List.of(latest.messages);
      _lastSeenAt = latestLastSeen;
    });
    if (latest.unreadCount > 0) unawaited(_markCurrentThreadRead());
    if (messagesChanged && shouldStickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 180;
  }

  bool _messagesChanged(MessageThread latest) {
    if (latest.messages.length != _thread.messages.length) return true;
    for (var index = 0; index < latest.messages.length; index++) {
      if (!_sameMessage(latest.messages[index], _thread.messages[index])) {
        return true;
      }
    }
    return false;
  }

  bool _sameMessage(ChatMessage left, ChatMessage right) {
    final leftAttachment = left.attachment;
    final rightAttachment = right.attachment;
    final leftProduct = left.sharedProduct;
    final rightProduct = right.sharedProduct;
    return left.id == right.id &&
        left.text == right.text &&
        left.createdAt == right.createdAt &&
        left.isMine == right.isMine &&
        left.senderId == right.senderId &&
        left.senderName == right.senderName &&
        left.senderAvatar == right.senderAvatar &&
        left.type == right.type &&
        left.replyToId == right.replyToId &&
        left.replyToText == right.replyToText &&
        left.replyToSenderName == right.replyToSenderName &&
        left.editedAt == right.editedAt &&
        left.deletedAt == right.deletedAt &&
        left.isPending == right.isPending &&
        left.hasError == right.hasError &&
        listEquals(left.readBy, right.readBy) &&
        _sameReactions(left.reactions, right.reactions) &&
        leftAttachment?.url == rightAttachment?.url &&
        leftAttachment?.name == rightAttachment?.name &&
        leftAttachment?.mimeType == rightAttachment?.mimeType &&
        leftAttachment?.size == rightAttachment?.size &&
        leftAttachment?.width == rightAttachment?.width &&
        leftAttachment?.height == rightAttachment?.height &&
        leftAttachment?.durationMs == rightAttachment?.durationMs &&
        leftAttachment?.bucket == rightAttachment?.bucket &&
        leftAttachment?.storagePath == rightAttachment?.storagePath &&
        leftAttachment?.thumbnailUrl == rightAttachment?.thumbnailUrl &&
        leftProduct?.id == rightProduct?.id &&
        leftProduct?.title == rightProduct?.title &&
        leftProduct?.image == rightProduct?.image &&
        leftProduct?.price == rightProduct?.price &&
        leftProduct?.sellerHandle == rightProduct?.sellerHandle;
  }

  bool _sameReactions(
    Map<String, List<String>> left,
    Map<String, List<String>> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!listEquals(entry.value, right[entry.key])) return false;
    }
    return true;
  }

  Future<void> _markCurrentThreadRead() async {
    final markRead = widget.actions?.markRead;
    if (markRead == null) return;
    if (_isMarkingRead) {
      _markReadAgain = true;
      return;
    }

    _isMarkingRead = true;
    try {
      do {
        _markReadAgain = false;
        try {
          await markRead(_thread.id);
        } catch (error, stackTrace) {
          _logChatUiFailure('sync read receipt', error, stackTrace);
          // Realtime or the next foreground refresh will retry the receipt.
        }
      } while (_markReadAgain && mounted);
    } finally {
      _isMarkingRead = false;
    }
  }

  bool _memberProfilesChanged(MessageThread latest) {
    if (latest.members.length != _thread.members.length) return true;
    for (final member in latest.members) {
      final previous = _thread.memberById(member.id);
      if (previous == null ||
          previous.name != member.name ||
          previous.handle != member.handle ||
          previous.avatarUrl != member.avatarUrl) {
        return true;
      }
    }
    return false;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    widget.threadsListenable.removeListener(_refreshThread);
    _draftDebounce?.cancel();
    final saveDraft = widget.actions?.saveDraft;
    if (saveDraft != null) {
      unawaited(_saveDraftSafely(saveDraft, _controller.text));
    }
    _controller.removeListener(_saveDraftLater);
    _controller.dispose();
    _chatSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _saveDraftLater() {
    final saveDraft = widget.actions?.saveDraft;
    if (saveDraft == null) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_saveDraftSafely(saveDraft, _controller.text));
    });
  }

  Future<void> _saveDraftSafely(
    SaveDraftCallback saveDraft,
    String draft,
  ) async {
    try {
      await saveDraft(_thread.id, draft);
    } catch (error, stackTrace) {
      _logChatUiFailure('save draft', error, stackTrace);
      // Drafts are also retained by the TextEditingController during the
      // current session; a later change will retry persistence.
    }
  }

  void _replyToMessage(ChatMessage message) {
    HapticFeedback.selectionClick();
    setState(() {
      _replyTo = message;
      _editingMessage = null;
    });
  }

  void _editChatMessage(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyTo = null;
      _controller.text = message.text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  Future<void> _deleteChatMessage(ChatMessage message) async {
    final remove = widget.actions?.deleteMessage;
    if (remove == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить сообщение?'),
        content: Text('Оно исчезнет у всех участников беседы.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var removed = false;
    try {
      removed = await remove(_thread.id, message.id);
    } catch (error, stackTrace) {
      _logChatUiFailure('delete message', error, stackTrace);
      removed = false;
    }
    if (!mounted || removed) return;
    _showError('Не удалось удалить сообщение. Попробуйте ещё раз.');
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    if (message.isDeleted || message.type == 'system') return;
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: sheetContext.appPalette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetContext.appPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: Icon(Icons.reply_rounded),
                  title: Text('Ответить'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _replyToMessage(message);
                  },
                ),
                if (message.text.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.copy_rounded),
                    title: Text('Копировать'),
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: message.text),
                      );
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                if (message.isMine &&
                    !message.isProductShare &&
                    widget.actions?.editMessage != null)
                  ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Редактировать'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editChatMessage(message);
                    },
                  ),
                if (message.isMine && widget.actions?.deleteMessage != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFE5484D),
                    ),
                    title: Text(
                      'Удалить',
                      style: TextStyle(color: Color(0xFFE5484D)),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _deleteChatMessage(message);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAttachmentSheet() async {
    if (_isSending) return;
    if (widget.actions?.sendMedia == null &&
        widget.actions?.sendImage == null) {
      return;
    }
    final canSendVideo = widget.actions?.sendMedia != null;
    final choice = await showModalBottomSheet<_AttachmentChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Material(
        color: context.appPalette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Вложение',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _AttachmentAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Фото',
                      onTap: () => Navigator.pop(
                        context,
                        _AttachmentChoice.imageGallery,
                      ),
                    ),
                    if (canSendVideo) ...[
                      const SizedBox(width: 12),
                      _AttachmentAction(
                        icon: Icons.video_library_outlined,
                        label: 'Видео',
                        onTap: () => Navigator.pop(
                          context,
                          _AttachmentChoice.videoGallery,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _AttachmentAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Снять фото',
                      onTap: () =>
                          Navigator.pop(context, _AttachmentChoice.imageCamera),
                    ),
                    if (canSendVideo) ...[
                      const SizedBox(width: 12),
                      _AttachmentAction(
                        icon: Icons.videocam_outlined,
                        label: 'Снять видео',
                        onTap: () => Navigator.pop(
                          context,
                          _AttachmentChoice.videoCamera,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null) return;
    final isVideo =
        choice == _AttachmentChoice.videoGallery ||
        choice == _AttachmentChoice.videoCamera;
    final source =
        choice == _AttachmentChoice.imageCamera ||
            choice == _AttachmentChoice.videoCamera
        ? ImageSource.camera
        : ImageSource.gallery;
    final caption = _controller.text.trim();
    if (caption.characters.length > 8000) {
      _showError('Подпись должна быть не длиннее 8000 символов.');
      return;
    }
    XFile? media;
    try {
      media = isVideo
          ? await _imagePicker.pickVideo(
              source: source,
              maxDuration: const Duration(minutes: 3),
            )
          : await _imagePicker.pickImage(
              source: source,
              imageQuality: 88,
              maxWidth: 1800,
            );
    } on PlatformException catch (error, stackTrace) {
      _logChatUiFailure('pick media', error, stackTrace);
      if (!mounted) return;
      final denied =
          error.code.toLowerCase().contains('denied') ||
          error.code.toLowerCase().contains('permission');
      _showError(
        denied
            ? 'Разрешите доступ к камере или медиатеке в настройках устройства.'
            : 'Не удалось открыть медиатеку. Попробуйте ещё раз.',
      );
      return;
    } catch (error, stackTrace) {
      _logChatUiFailure('pick media', error, stackTrace);
      if (mounted) {
        _showError('Не удалось открыть медиатеку. Попробуйте ещё раз.');
      }
      return;
    }
    if (media == null) return;
    setState(() => _isSending = true);
    var sent = false;
    try {
      final sendMedia = widget.actions!.sendMedia;
      if (sendMedia != null) {
        sent = await sendMedia(
          _thread.id,
          media,
          kind: isVideo ? ChatMediaKind.video : ChatMediaKind.image,
          caption: caption,
          replyTo: _replyTo,
        );
      } else if (!isVideo && widget.actions!.sendImage != null) {
        sent = await widget.actions!.sendImage!(
          _thread.id,
          media,
          caption: caption,
          replyTo: _replyTo,
        );
      }
    } catch (error, stackTrace) {
      _logChatUiFailure('send media', error, stackTrace);
      sent = false;
    }
    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (sent) {
        _controller.clear();
        _replyTo = null;
      }
    });
    if (!sent && mounted) {
      _showError('Не удалось отправить медиа. Попробуйте ещё раз.');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    if (text.characters.length > 8000) {
      _showError('Сообщение должно быть не длиннее 8000 символов.');
      return;
    }

    final editing = _editingMessage;
    if (editing != null) {
      final edit = widget.actions?.editMessage;
      if (edit == null) return;
      setState(() => _isSending = true);
      var saved = false;
      try {
        saved = await edit(_thread.id, editing.id, text);
      } catch (error, stackTrace) {
        _logChatUiFailure('edit message', error, stackTrace);
        saved = false;
      }
      if (!mounted) return;
      setState(() {
        _isSending = false;
        if (saved) {
          _editingMessage = null;
          _controller.clear();
        }
      });
      if (!saved) {
        _showError('Не удалось сохранить изменения. Попробуйте ещё раз.');
      }
      return;
    }

    final reply = _replyTo;
    final temporaryId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final pendingMessage = ChatMessage(
      id: temporaryId,
      text: text,
      createdAt: DateTime.now(),
      isMine: true,
      senderId: widget.currentUserId,
      replyToId: reply?.id ?? '',
      replyToText: reply?.previewText ?? '',
      replyToSenderName: reply?.senderName ?? '',
      isPending: true,
    );

    setState(() {
      _messages = [..._messages, pendingMessage];
      _replyTo = null;
      _controller.clear();
    });

    var sent = false;
    try {
      // The pending-aware path owns the client id for both plain messages and
      // replies, so realtime reconciliation and retry stay idempotent.
      if (widget.actions?.sendPendingText != null) {
        sent = await widget.actions!.sendPendingText!(
          _thread.id,
          pendingMessage,
        );
      } else if (reply != null && widget.actions?.sendReply != null) {
        sent = await widget.actions!.sendReply!(_thread.id, text, reply);
      } else if (widget.actions?.sendText != null) {
        sent = await widget.actions!.sendText!(_thread.id, text);
      } else {
        await widget.onSendMessage(_thread.id, text);
        sent = true;
      }
    } catch (error, stackTrace) {
      _logChatUiFailure('send text message', error, stackTrace);
      sent = false;
    }
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere(
        (message) => message.id == temporaryId,
      );
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          isPending: false,
          hasError: !sent,
        );
      }
      // A slow delivery failure must not overwrite text the user has already
      // started typing for the next message. The failed bubble remains
      // retryable even when the composer now contains a different draft.
      if (!sent &&
          widget.actions?.retryText == null &&
          _controller.text.isEmpty &&
          _replyTo == null &&
          _editingMessage == null) {
        _controller.text = text;
        _controller.selection = TextSelection.collapsed(offset: text.length);
        _replyTo = reply;
      }
    });
    if (!sent) {
      _showError('Сообщение не доставлено. Проверьте подключение.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    _scrollToBottom();
  }

  Future<void> _retryMessage(ChatMessage message) async {
    final retry = message.type == 'text'
        ? widget.actions?.retryText
        : message.isMedia
        ? widget.actions?.retryMedia
        : null;
    if (retry == null ||
        !message.hasError ||
        _retryingMessageIds.contains(message.id)) {
      return;
    }

    setState(() {
      _retryingMessageIds.add(message.id);
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          isPending: true,
          hasError: false,
        );
      }
    });

    var sent = false;
    try {
      sent = await retry(_thread.id, message);
    } catch (error, stackTrace) {
      _logChatUiFailure('retry text message', error, stackTrace);
      sent = false;
    }
    if (!mounted) return;

    setState(() {
      _retryingMessageIds.remove(message.id);
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          isPending: false,
          hasError: !sent,
        );
      }
    });
    if (!sent) {
      _showError('Повторная отправка не удалась. Проверьте подключение.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openConversationInfo() async {
    final result = await Navigator.of(context).push<ConversationInfoResult>(
      MaterialPageRoute<ConversationInfoResult>(
        builder: (context) => ConversationInfoScreen(
          thread: _thread,
          currentUserId: widget.currentUserId,
          actions: widget.actions,
          onOpenProduct: widget.onOpenProduct,
          onOpenSeller: widget.onOpenSellerProfile,
        ),
      ),
    );
    if (!mounted || result != ConversationInfoResult.search) return;
    setState(() => _isChatSearching = true);
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = _chatQuery.trim().isEmpty
        ? _messages
        : _messages
              .where(
                (message) => message.previewText.toLowerCase().contains(
                  _chatQuery.trim().toLowerCase(),
                ),
              )
              .toList(growable: false);
    return Scaffold(
      backgroundColor: context.appBackdrop.scaffoldColor,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_isChatSearching)
              _ChatSearchHeader(
                controller: _chatSearchController,
                resultCount: visibleMessages.length,
                onChanged: (value) => setState(() => _chatQuery = value),
                onClose: () => setState(() {
                  _isChatSearching = false;
                  _chatQuery = '';
                  _chatSearchController.clear();
                }),
              )
            else
              _ChatHeader(
                thread: _thread,
                currentUserId: widget.currentUserId,
                lastSeenAt: _lastSeenAt,
                onTap: _openConversationInfo,
                onSearch: () => setState(() => _isChatSearching = true),
                onOpenSeller: widget.onOpenSellerProfile,
              ),
            if (_thread.isProductChat)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _ProductContextCard(
                  thread: _thread,
                  onBuy: widget.onBuyProduct,
                  onTap: widget.onOpenProduct == null
                      ? null
                      : () => widget.onOpenProduct!(_thread.productId),
                ),
              ),
            Expanded(
              child: visibleMessages.isEmpty
                  ? _EmptyChat(thread: _thread)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                      physics: const BouncingScrollPhysics(),
                      itemCount: visibleMessages.length,
                      itemBuilder: (context, index) {
                        final messageIndex = index;
                        final message = visibleMessages[messageIndex];
                        final previous = messageIndex == 0
                            ? null
                            : visibleMessages[messageIndex - 1];
                        final next = messageIndex + 1 >= visibleMessages.length
                            ? null
                            : visibleMessages[messageIndex + 1];
                        final showDate =
                            previous == null ||
                            !_isSameDay(previous.createdAt, message.createdAt);
                        final continuesWithNext =
                            next != null &&
                            next.senderId == message.senderId &&
                            next.isMine == message.isMine &&
                            _isSameDay(next.createdAt, message.createdAt) &&
                            next.createdAt
                                    .difference(message.createdAt)
                                    .inMinutes <
                                5;
                        return Column(
                          children: [
                            if (showDate) _DateChip(date: message.createdAt),
                            if (message.type == 'system')
                              _SystemMessage(message: message)
                            else
                              _MessageBubble(
                                message: message,
                                showSender: _thread.isGroup && !message.isMine,
                                senderAvatar: _thread.avatarForUser(
                                  message.senderId,
                                ),
                                onOpenProduct: widget.onOpenProduct,
                                onLongPress: () => _showMessageActions(message),
                                onRetry:
                                    message.hasError &&
                                        ((message.type == 'text' &&
                                                widget.actions?.retryText !=
                                                    null) ||
                                            (message.isMedia &&
                                                widget.actions?.retryMedia !=
                                                    null))
                                    ? () => _retryMessage(message)
                                    : null,
                              ),
                            SizedBox(height: continuesWithNext ? 2 : 8),
                          ],
                        );
                      },
                    ),
            ),
            _MessageComposer(
              controller: _controller,
              isSending: _isSending,
              onSend: _send,
              replyTo: _replyTo,
              editingMessage: _editingMessage,
              onCancelContext: () => setState(() {
                _replyTo = null;
                _editingMessage = null;
                _controller.clear();
              }),
              onAttach: _showAttachmentSheet,
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxSyncErrorBanner extends StatelessWidget {
  const _InboxSyncErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('inbox-sync-error-banner'),
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appPalette.border, width: 0.6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 19,
            color: context.appPalette.muted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                color: context.appPalette.ink,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const Key('inbox-sync-retry'),
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
        ],
      ),
    );
  }
}

class _InboxStatus extends StatelessWidget {
  const _InboxStatus({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.appPalette.ink,
                        ),
                      ),
                    )
                  : Icon(icon, size: 30, color: context.appPalette.ink),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.appPalette.ink,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: context.appPalette.muted,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
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
              decoration: BoxDecoration(
                color: context.appPalette.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: context.appPalette.ink),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: context.appPalette.ink,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: context.appPalette.muted,
              ),
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
    this.onLongPress,
  });

  final MessageThread thread;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final title = thread.displayTitle(currentUserId);
    final subtitle = thread.isProductChat
        ? thread.productTitle
        : thread.displaySubtitle(currentUserId);
    final hasDraft = thread.draft.trim().isNotEmpty;
    final preview = hasDraft
        ? 'Черновик: ${thread.draft.trim()}'
        : thread.lastMessage.isEmpty
        ? 'Напишите сообщение'
        : thread.lastMessage;
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      onTap: onTap,
      onLongPress: onLongPress,
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
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            color: context.appPalette.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _threadTimeLabel(thread.updatedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appPalette.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appPalette.muted,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: thread.unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: hasDraft
                                ? Theme.of(context).colorScheme.primary
                                : thread.lastMessage.isEmpty
                                ? context.appPalette.muted
                                : context.appPalette.ink,
                          ),
                        ),
                      ),
                      if (thread.isPinned)
                        Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.push_pin,
                            size: 14,
                            color: context.appPalette.muted,
                          ),
                        ),
                      if (thread.isMuted)
                        Padding(
                          padding: EdgeInsets.only(left: 5),
                          child: Icon(
                            Icons.volume_off_rounded,
                            size: 15,
                            color: context.appPalette.muted,
                          ),
                        ),
                      if (thread.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 7),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: thread.isMuted
                                ? context.appPalette.surfaceMuted
                                : Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            thread.unreadCount > 99
                                ? '99+'
                                : thread.unreadCount.toString(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: thread.isMuted
                                  ? context.appPalette.ink
                                  : Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
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
    return ChatAvatar.thread(
      thread: thread,
      currentUserId: currentUserId,
      size: 54,
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
          color: context.appPalette.surfaceMuted,
          border: isSquare
              ? Border.all(color: context.appPalette.border)
              : null,
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
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: context.appPalette.ink,
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
  const _ChatHeader({
    required this.thread,
    required this.currentUserId,
    required this.lastSeenAt,
    required this.onTap,
    required this.onSearch,
    this.onOpenSeller,
  });

  final MessageThread thread;
  final String currentUserId;
  final DateTime? lastSeenAt;
  final VoidCallback onTap;
  final VoidCallback onSearch;
  final VoidCallback? onOpenSeller;

  @override
  Widget build(BuildContext context) {
    final activity = thread.isGroup
        ? thread.displaySubtitle(currentUserId)
        : _activityLabel(lastSeenAt);
    final isOnline = !thread.isGroup && _isOnline(lastSeenAt);
    final topInset = MediaQuery.of(context).viewPadding.top;

    return Container(
      height: topInset + 62,
      padding: EdgeInsets.fromLTRB(4, topInset + 4, 12, 4),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        border: Border(
          bottom: BorderSide(color: context.appPalette.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new,
              size: 20,
              color: context.appPalette.ink,
            ),
          ),
          Expanded(
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  _ThreadAvatar(thread: thread, currentUserId: currentUserId),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          thread.displayTitle(currentUserId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.1,
                            fontWeight: FontWeight.w500,
                            color: context.appPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (!thread.isGroup) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? const Color(0xFF2FBF71)
                                      : const Color(0xFFC9C9CE),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                activity,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isOnline
                                      ? const Color(0xFF2C9F62)
                                      : context.appPalette.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onSearch,
            icon: Icon(Icons.search_rounded, color: context.appPalette.ink),
          ),
          if (onOpenSeller != null)
            IconButton(
              tooltip: 'Профиль продавца',
              onPressed: onOpenSeller,
              icon: Icon(
                Icons.person_outline_rounded,
                color: context.appPalette.ink,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatSearchHeader extends StatelessWidget {
  const _ChatSearchHeader({
    required this.controller,
    required this.resultCount,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final int resultCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Container(
      height: topInset + 62,
      padding: EdgeInsets.fromLTRB(6, topInset + 7, 10, 7),
      color: context.appPalette.surface,
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Поиск в чате',
                filled: true,
                fillColor: context.appPalette.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              controller.text.isEmpty ? '' : '$resultCount',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.appPalette.muted),
            ),
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
        SizedBox(height: thread.isProductChat ? 58 : 88),
        Center(
          child: Text(
            'Начните диалог',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.appPalette.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductContextCard extends StatelessWidget {
  const _ProductContextCard({required this.thread, this.onTap, this.onBuy});

  final MessageThread thread;
  final VoidCallback? onTap;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final title = thread.productTitle.trim();
    final imageOnly = title.isEmpty;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(imageOnly ? 6 : 8),
      width: imageOnly ? 96 : double.infinity,
      constraints: BoxConstraints(maxWidth: imageOnly ? 96 : 420),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceRaised.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appPalette.border),
      ),
      child: imageOnly
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 84,
                height: 84,
                child: thread.productImage.isEmpty
                    ? ColoredBox(
                        color: context.appPalette.surfaceMuted,
                        child: Icon(
                          Icons.checkroom_outlined,
                          color: context.appPalette.muted,
                        ),
                      )
                    : AppImage(
                        imageUrl: thread.productImage,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
              ),
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: thread.productImage.isEmpty
                        ? ColoredBox(
                            color: context.appPalette.surfaceMuted,
                            child: Icon(
                              Icons.checkroom_outlined,
                              color: context.appPalette.muted,
                            ),
                          )
                        : AppImage(
                            imageUrl: thread.productImage,
                            width: 48,
                            height: 48,
                            fit: BoxFit.fill,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.18,
                      fontWeight: FontWeight.w500,
                      color: context.appPalette.ink,
                    ),
                  ),
                ),
                if (onBuy != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 36,
                    child: FilledButton(
                      onPressed: onBuy,
                      style: FilledButton.styleFrom(
                        overlayColor: Colors.transparent,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: Text(
                        'Купить',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );

    return Center(
      child: onTap == null
          ? card
          : InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: card,
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
            color: context.appPalette.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _dateLabel(date),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: context.appPalette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showSender,
    this.senderAvatar = '',
    this.onOpenProduct,
    this.onLongPress,
    this.onRetry,
  });

  final ChatMessage message;
  final bool showSender;
  final String senderAvatar;
  final void Function(String productId)? onOpenProduct;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final isRich = message.isProductShare || message.isMedia;
    final bubbleWidth = (MediaQuery.sizeOf(context).width * 0.72)
        .clamp(180.0, 410.0)
        .toDouble();
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: bubbleWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: message.isProductShare
              ? context.appPalette.surfaceRaised
              : isMine
              ? Theme.of(context).colorScheme.primary
              : context.appPalette.surfaceRaised,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 5),
            bottomRight: Radius.circular(isMine ? 5 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: context.appPalette.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isRich ? 6 : 13,
            isRich ? 6 : 8,
            isRich ? 6 : 10,
            7,
          ),
          child: Column(
            crossAxisAlignment: showSender
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender && message.senderName.trim().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 1, 6, 5),
                  child: Text(
                    message.senderName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2C79D6),
                    ),
                  ),
                ),
              ],
              if (message.isReply)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: isMine
                        ? Theme.of(
                            context,
                          ).colorScheme.onPrimary.withValues(alpha: 0.12)
                        : context.appPalette.surfaceMuted,
                    border: Border(
                      left: BorderSide(
                        color: context.appPalette.accent,
                        width: 3,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToSenderName.isNotEmpty)
                        Text(
                          message.replyToSenderName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isMine
                                ? Theme.of(context).colorScheme.onPrimary
                                : context.appPalette.ink,
                          ),
                        ),
                      Text(
                        message.replyToText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isMine
                              ? Theme.of(
                                  context,
                                ).colorScheme.onPrimary.withValues(alpha: 0.72)
                              : context.appPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              if (message.isDeleted)
                Text(
                  'Сообщение удалено',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: isMine
                        ? Theme.of(
                            context,
                          ).colorScheme.onPrimary.withValues(alpha: 0.65)
                        : context.appPalette.muted,
                  ),
                )
              else if (message.isImage)
                AppImage(
                  imageUrl: message.attachment!.url,
                  width: 246,
                  height: 226,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(13),
                )
              else if (message.isVideo)
                _ChatVideoPlayer(attachment: message.attachment!)
              else if (message.isProductShare)
                _SharedProductCard(
                  product: message.sharedProduct!,
                  onTap: onOpenProduct == null
                      ? null
                      : () => onOpenProduct!(message.sharedProduct!.id),
                )
              else
                Text(
                  message.text,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.24,
                    color: isMine
                        ? Theme.of(context).colorScheme.onPrimary
                        : context.appPalette.ink,
                  ),
                ),
              if (message.isMedia && message.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: isMine
                          ? Theme.of(context).colorScheme.onPrimary
                          : context.appPalette.ink,
                    ),
                  ),
                ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEdited)
                      Text(
                        'изм.  ',
                        style: TextStyle(
                          fontSize: 10,
                          color: isMine
                              ? Theme.of(
                                  context,
                                ).colorScheme.onPrimary.withValues(alpha: 0.64)
                              : context.appPalette.muted,
                        ),
                      ),
                    Text(
                      _timeLabel(message.createdAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: message.isProductShare
                            ? context.appPalette.muted
                            : isMine
                            ? Theme.of(
                                context,
                              ).colorScheme.onPrimary.withValues(alpha: 0.64)
                            : context.appPalette.muted,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.hasError
                            ? Icons.error_outline_rounded
                            : message.isPending
                            ? Icons.schedule_rounded
                            : message.isReadByAnotherUser()
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 14,
                        color: message.hasError
                            ? const Color(0xFFFF6B6B)
                            : Theme.of(
                                context,
                              ).colorScheme.onPrimary.withValues(alpha: 0.7),
                      ),
                      if (message.hasError && onRetry != null) ...[
                        const SizedBox(width: 4),
                        const Text(
                          'Повторить',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFB4B4),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: message.hasError && onRetry != null,
      label: message.hasError && onRetry != null
          ? 'Сообщение не отправлено. Повторить отправку'
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: message.hasError ? onRetry : null,
        onLongPress: onLongPress,
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: showSender
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ChatAvatar(
                      imageUrl: senderAvatar,
                      name: message.senderName,
                      size: 30,
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: bubble),
                  ],
                )
              : bubble,
        ),
      ),
    );
  }
}

class _ChatVideoPlayer extends StatefulWidget {
  const _ChatVideoPlayer({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<_ChatVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _ChatVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.url != widget.attachment.url) {
      _disposeController();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    _failed = false;
    _wasPlaying = false;
    final rawUrl = widget.attachment.url.trim();
    if (rawUrl.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    late final VideoPlayerController controller;
    if (rawUrl.startsWith('assets/')) {
      controller = VideoPlayerController.asset(rawUrl);
    } else if (uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob')) {
      controller = VideoPlayerController.networkUrl(uri);
    } else if (!kIsWeb && uri?.scheme == 'file') {
      controller = VideoPlayerController.file(File.fromUri(uri!));
    } else if (!kIsWeb) {
      controller = VideoPlayerController.file(File(rawUrl));
    } else {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      _wasPlaying = controller.value.isPlaying;
      controller.addListener(_handlePlaybackState);
      if (mounted && identical(_controller, controller)) setState(() {});
    } catch (error, stackTrace) {
      _logChatUiFailure('initialize chat video', error, stackTrace);
      if (mounted && identical(_controller, controller)) {
        setState(() => _failed = true);
      }
    }
  }

  void _handlePlaybackState() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final isPlaying = controller.value.isPlaying;
    if (_wasPlaying == isPlaying) return;
    _wasPlaying = isPlaying;
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted && identical(_controller, controller)) setState(() {});
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_handlePlaybackState);
      unawaited(controller.dispose());
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller?.value.isInitialized == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 246,
        height: 226,
        child: ColoredBox(
          color: const Color(0xFF151518),
          child: _failed
              ? Center(
                  child: Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white70,
                    size: 34,
                  ),
                )
              : !isReady
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayback,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller!.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      if (!controller.value.isPlaying)
                        Center(
                          child: CircleAvatar(
                            radius: 25,
                            backgroundColor: Color(0xB8000000),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: context.appPalette.accent,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white12,
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : context.appPalette.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : context.appPalette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: context.appPalette.surfaceMuted.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: context.appPalette.muted,
          ),
        ),
      ),
    );
  }
}

class _SharedProductCard extends StatelessWidget {
  const _SharedProductCard({required this.product, this.onTap});

  final SharedProductPreview product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      width: 238,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppImage(
            imageUrl: product.image,
            width: 238,
            height: 148,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(13),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 9, 7, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: context.appPalette.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.price,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.appPalette.ink,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: context.appPalette.ink,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? card
        : InkWell(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: card,
          );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.replyTo,
    required this.editingMessage,
    required this.onCancelContext,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final ChatMessage? replyTo;
  final ChatMessage? editingMessage;
  final VoidCallback onCancelContext;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final contextMessage = editingMessage ?? replyTo;
    final borderRadius = BorderRadius.circular(24);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (contextMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(13, 7, 6, 7),
                decoration: BoxDecoration(
                  color: context.appPalette.surfaceRaised.withValues(
                    alpha: context.appGlass.enabled ? 0.82 : 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.appPalette.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 2.5,
                      height: 34,
                      decoration: BoxDecoration(
                        color: context.appPalette.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editingMessage != null
                                ? 'Редактирование'
                                : 'Ответ${replyTo!.senderName.trim().isEmpty ? '' : ' · ${replyTo!.senderName.trim()}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: context.appPalette.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            contextMessage.previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.appPalette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Отменить',
                      onPressed: onCancelContext,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: context.appPalette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AppGlassSurface(
                    role: AppGlassRole.input,
                    interactiveGlint: false,
                    borderRadius: borderRadius,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.appGlass.enabled
                            ? Colors.transparent
                            : context.appPalette.surfaceMuted,
                        borderRadius: borderRadius,
                        border: context.appGlass.enabled
                            ? null
                            : Border.all(color: context.appPalette.border),
                      ),
                      child: TextField(
                        key: const Key('message-composer-field'),
                        controller: controller,
                        enabled: !isSending,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(8000),
                        ],
                        decoration: InputDecoration(
                          // The role-based material owns both Glass-on and
                          // Glass-off fills. Inheriting the global filled
                          // decoration would paint a gray rectangle over it.
                          filled: false,
                          hintText: 'Написать сообщение',
                          hintStyle: TextStyle(
                            fontSize: 14.5,
                            color: context.appPalette.muted,
                          ),
                          prefixIcon: IconButton(
                            tooltip: 'Прикрепить',
                            onPressed: isSending ? null : onAttach,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.add_rounded,
                              size: 22,
                              color: context.appPalette.muted,
                            ),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.fromLTRB(
                            0,
                            12,
                            15,
                            12,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          color: context.appPalette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    final length = value.text.characters.length;
                    final enabled =
                        !isSending &&
                        value.text.trim().isNotEmpty &&
                        length <= 8000;
                    return Semantics(
                      button: true,
                      enabled: enabled,
                      label: editingMessage == null
                          ? 'Отправить сообщение'
                          : 'Сохранить изменения',
                      child: GestureDetector(
                        key: const Key('message-send-button'),
                        behavior: HitTestBehavior.opaque,
                        onTap: enabled ? onSend : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: enabled
                                ? Theme.of(context).colorScheme.primary
                                : context.appPalette.surfaceMuted,
                            shape: BoxShape.circle,
                            border: enabled
                                ? null
                                : Border.all(color: context.appPalette.border),
                            boxShadow: enabled
                                ? [
                                    BoxShadow(
                                      color: context.appPalette.shadow,
                                      blurRadius: 12,
                                      spreadRadius: -5,
                                      offset: const Offset(0, 5),
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSending
                              ? Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  ),
                                )
                              : Icon(
                                  editingMessage == null
                                      ? Icons.arrow_upward
                                      : Icons.check_rounded,
                                  size: 21,
                                  color: enabled
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : context.appPalette.muted,
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 86,
          decoration: BoxDecoration(
            color: context.appPalette.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 25, color: context.appPalette.ink),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.appPalette.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _threadTimeLabel(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (_isSameDay(local, now)) return _timeLabel(local);

  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(local, yesterday)) return 'вчера';

  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  if (local.year == now.year) return '$day.$month';
  return '$day.$month.${local.year}';
}

bool _isOnline(DateTime? value) {
  if (value == null) return false;
  return DateTime.now().difference(value.toLocal()) <
      const Duration(seconds: 90);
}

String _activityLabel(DateTime? value) {
  if (value == null) return 'был давно';

  final lastSeen = value.toLocal();
  final difference = DateTime.now().difference(lastSeen);
  if (difference < const Duration(seconds: 90)) return 'онлайн';
  if (difference < const Duration(minutes: 2)) return 'был только что';
  if (difference < const Duration(hours: 1)) {
    final minutes = difference.inMinutes;
    return 'был $minutes ${_plural(minutes, 'минуту', 'минуты', 'минут')} назад';
  }
  if (difference < const Duration(days: 1)) {
    final hours = difference.inHours;
    return 'был $hours ${_plural(hours, 'час', 'часа', 'часов')} назад';
  }
  if (difference < const Duration(days: 7)) {
    final days = difference.inDays;
    return 'был $days ${_plural(days, 'день', 'дня', 'дней')} назад';
  }

  final day = lastSeen.day.toString().padLeft(2, '0');
  final month = lastSeen.month.toString().padLeft(2, '0');
  return 'был $day.$month.${lastSeen.year}';
}

String _plural(int value, String one, String few, String many) {
  final mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  switch (value % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (_isSameDay(local, now)) return 'Сегодня';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(local, yesterday)) return 'Вчера';
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}
