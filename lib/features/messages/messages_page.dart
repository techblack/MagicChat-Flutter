part of '../../main.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage(
      {required this.repository,
      this.serverUrl,
      this.realtimeSession,
      this.realtimeStore,
      this.cacheScope,
      required this.selectedId,
      required this.onSelect,
      this.onOpenConversation,
      this.onBack,
      this.onOpenMessage,
      this.onOpenInternalLink,
      this.sendMessageShortcut = MessageSendShortcut.enter,
      this.enableFileDrop = true,
      this.screenshotController,
      this.screenshotRequestToken = 0,
      this.focusMessageId,
      this.focusMessageSequence,
      this.onMessageFocused,
      this.onUnreadChanged,
      this.messagesReselectToken = 0,
      this.chatAppearance = const ChatAppearance(),
      this.conversationAppearance,
      this.onConversationAppearanceChanged,
      super.key});
  final MagicChatRepository repository;
  final String? serverUrl;
  final RealtimeSession? realtimeSession;
  final RealtimeStore? realtimeStore;
  final MessageCacheScope? cacheScope;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpenConversation;
  final VoidCallback? onBack;
  final void Function(
          String conversationId, String messageId, int? messageSequence)?
      onOpenMessage;
  final ValueChanged<String>? onOpenInternalLink;
  final MessageSendShortcut sendMessageShortcut;
  final bool enableFileDrop;
  final DesktopScreenshotController? screenshotController;
  final int screenshotRequestToken;
  final String? focusMessageId;
  final int? focusMessageSequence;
  final VoidCallback? onMessageFocused;
  final ValueChanged<int>? onUnreadChanged;
  final int messagesReselectToken;
  final ChatAppearance chatAppearance;
  final ChatConversationAppearance? conversationAppearance;
  final Future<void> Function(
          String conversationId, ChatConversationAppearance appearance)?
      onConversationAppearanceChanged;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final split = constraints.maxWidth >= 700;
        final conversationList = Stack(children: [
          Positioned.fill(
              child: _ConversationList(
                  repository: repository,
                  realtimeSession: realtimeSession,
                  serverUrl: serverUrl,
                  cacheScope: cacheScope,
                  realtimeStore: realtimeStore,
                  selectedId: selectedId,
                  onSelect: onSelect,
                  onUnreadChanged: onUnreadChanged)),
          Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                  heroTag: 'messages-create-group',
                  onPressed: () => _createGroup(context),
                  tooltip: '新建群聊',
                  child: const Icon(Icons.group_add))),
        ]);
        final conversationView = selectedId == null
            ? const _ConversationSelectionState()
            : ConversationView(
                repository: repository,
                realtimeSession: realtimeSession,
                realtimeStore: realtimeStore,
                cacheScope: cacheScope,
                sendMessageShortcut: sendMessageShortcut,
                chatAppearance: chatAppearance,
                conversationAppearance: conversationAppearance,
                enableFileDrop: enableFileDrop,
                screenshotController: screenshotController,
                screenshotRequestToken: screenshotRequestToken,
                conversationId: selectedId,
                focusMessageId: focusMessageId,
                focusMessageSequence: focusMessageSequence,
                onOpenConversation: onOpenConversation ?? onSelect,
                onOpenInternalLink: onOpenInternalLink,
                onMessageFocused: onMessageFocused,
                messagesReselectToken: messagesReselectToken,
              );
        final conversationHeader = selectedId == null
            ? null
            : _ConversationHeader(
                repository: repository,
                realtimeStore: realtimeStore,
                conversationId: selectedId!,
                compact: !split,
                onBack: onBack ?? () => onSelect(''),
                onSearch: onOpenMessage == null
                    ? null
                    : (title) =>
                        _showAdvancedMessageSearch(context, selectedId!, title),
                onDetails: () => _showConversationDetails(context, selectedId!),
              );
        final conversationPane = selectedId == null
            ? conversationView
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                conversationHeader!,
                Expanded(child: conversationView),
              ]);
        if (!split) {
          return IndexedStack(
            index: selectedId == null ? 0 : 1,
            children: [
              conversationList,
              if (selectedId == null)
                const SizedBox.shrink()
              else
                conversationPane,
            ],
          );
        }
        if (conversationHeader == null) {
          return Row(children: [
            SizedBox(width: 300, child: conversationList),
            Expanded(child: conversationView),
          ]);
        }
        return Column(children: [
          Material(
            key: const ValueKey('conversation-wide-top-bar'),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              // 顶栏独立于下方的会话列表/消息窗格，完整覆盖这一整行；
              // 标题和操作按钮不再只占右侧消息窗格的宽度。
              child: conversationHeader,
            ),
          ),
          Expanded(
            child: Row(children: [
              SizedBox(width: 300, child: conversationList),
              Expanded(child: conversationView),
            ]),
          ),
        ]);
      });

  Future<void> _showAdvancedMessageSearch(
      BuildContext context, String conversationId, String title) async {
    final openMessage = onOpenMessage;
    if (openMessage == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AdvancedMessageSearchDialog(
        repository: repository,
        conversationId: conversationId,
        conversationName: title,
        cacheScope: cacheScope,
        conversationType:
            realtimeStore?.conversations[conversationId]?.type ?? 'direct',
        onOpenMessage: openMessage,
      ),
    );
  }

  Future<void> _showConversationDetails(
      BuildContext context, String conversationId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationDetailsPage(
          repository: repository,
          conversationId: conversationId,
          initialConversation: realtimeStore?.conversations[conversationId],
          serverUrl: serverUrl,
          cacheScope: cacheScope,
          realtimeStore: realtimeStore,
          onOpenConversation: onOpenConversation ?? onSelect,
          onConversationRemoved: () => onSelect(''),
          chatAppearance: chatAppearance,
          conversationAppearance: conversationAppearance,
          onConversationAppearanceChanged: onConversationAppearanceChanged,
        ),
      ),
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('新建群聊'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '群聊名称')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('创建'))
              ],
            ));
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      final members = await _selectMembers(context);
      if (members == null || !context.mounted) return;
      final conversation =
          await repository.createGroupConversation(name, memberIds: members);
      if (context.mounted) onSelect(conversation.id);
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败：${userFacingError(error)}')));
    }
  }

  Future<List<String>?> _selectMembers(BuildContext context) async {
    final contacts = await repository.contacts();
    if (!context.mounted) return null;
    final selected = <String>{};
    var query = '';
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('选择群成员'),
            content: SizedBox(
                width: 360,
                height: 380,
                child: Column(children: [
                  TextField(
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search), hintText: '搜索联系人'),
                    onChanged: (value) => setDialogState(
                        () => query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Builder(builder: (context) {
                      final visible = contacts
                          .where((contact) =>
                              query.isEmpty ||
                              contact.displayName.toLowerCase().contains(query))
                          .toList(growable: false);
                      if (visible.isEmpty) {
                        return Center(
                            child: Text(query.isEmpty ? '暂无联系人' : '没有匹配的联系人'));
                      }
                      return ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final contact = visible[index];
                          return CheckboxListTile(
                            key: ValueKey(contact.id),
                            value: selected.contains(contact.id),
                            title: Text(contact.displayName),
                            onChanged: (checked) => setDialogState(() {
                              if (checked == true) {
                                selected.add(contact.id);
                              } else {
                                selected.remove(contact.id);
                              }
                            }),
                          );
                        },
                      );
                    }),
                  ),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, selected.toList()),
                  child: const Text('完成')),
            ],
          );
        },
      ),
    );
  }
}

class _ConversationSelectionState extends StatelessWidget {
  const _ConversationSelectionState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('conversation-selection-state'),
      color: colors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: colors.primary),
              const SizedBox(height: 14),
              Text(
                '选择一个会话',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '从左侧列表打开聊天，消息会显示在这里',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationHeader extends StatefulWidget {
  const _ConversationHeader({
    required this.repository,
    required this.realtimeStore,
    required this.conversationId,
    required this.compact,
    required this.onBack,
    required this.onSearch,
    required this.onDetails,
  });

  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final String conversationId;
  final bool compact;
  final VoidCallback onBack;
  final ValueChanged<String>? onSearch;
  final Future<void> Function() onDetails;

  @override
  State<_ConversationHeader> createState() => _ConversationHeaderState();
}

class _ConversationHeaderState extends State<_ConversationHeader> {
  late Future<ChatConversation?> _conversationFuture;

  @override
  void initState() {
    super.initState();
    _conversationFuture = _loadConversation();
    widget.realtimeStore?.addListener(_onRealtimeChanged);
  }

  @override
  void didUpdateWidget(covariant _ConversationHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeStore != widget.realtimeStore) {
      oldWidget.realtimeStore?.removeListener(_onRealtimeChanged);
      widget.realtimeStore?.addListener(_onRealtimeChanged);
    }
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.repository != widget.repository) {
      _conversationFuture = _loadConversation();
    }
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    super.dispose();
  }

  void _onRealtimeChanged() {
    if (mounted &&
        widget.realtimeStore?.conversations
                .containsKey(widget.conversationId) ==
            true) {
      setState(() {
        _conversationFuture = _loadConversation();
      });
    }
  }

  Future<ChatConversation?> _loadConversation() async {
    final live = widget.realtimeStore?.conversations[widget.conversationId];
    if (live != null) return live;
    final conversations = await widget.repository.conversations();
    for (final conversation in conversations) {
      if (conversation.id == widget.conversationId) return conversation;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
        width: double.infinity,
        height: 52,
        child: FutureBuilder<ChatConversation?>(
          future: _conversationFuture,
          initialData:
              widget.realtimeStore?.conversations[widget.conversationId],
          builder: (context, snapshot) {
            final conversation = snapshot.data;
            final title = conversation?.displayTitle.trim().isNotEmpty == true
                ? conversation!.displayTitle.trim()
                : '聊天';
            final headerTitle = conversation?.type == 'group'
                ? '$title (${conversation!.effectiveMemberCount})'
                : title;
            final status =
                conversation?.type == 'direct' || conversation?.type == 'app'
                    ? widget.realtimeStore
                        ?.conversationStatuses[widget.conversationId]?.text
                    : null;
            return Stack(alignment: Alignment.center, children: [
              if (widget.compact)
                Positioned(
                  left: 0,
                  child: IconButton(
                    tooltip: '返回会话列表',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 104),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headerTitle,
                      key: const ValueKey('conversation-header-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, height: 1.15),
                    ),
                    if (status != null)
                      _ConversationStatusIndicator(text: status),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.onSearch != null)
                    IconButton(
                      tooltip: '检索当前会话',
                      onPressed: () => widget.onSearch!(title),
                      icon: const Icon(Icons.manage_search),
                    ),
                  IconButton(
                    tooltip: '聊天详情',
                    onPressed: widget.onDetails,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ]),
              ),
            ]);
          },
        ));
    return Material(
      key: const ValueKey('conversation-header-background'),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: widget.compact
          ? SafeArea(
              key: const ValueKey('conversation-header-safe-area'),
              bottom: false,
              child: content)
          : content,
    );
  }
}

class _ConversationStatusIndicator extends StatefulWidget {
  const _ConversationStatusIndicator({required this.text});

  final String text;

  @override
  State<_ConversationStatusIndicator> createState() =>
      _ConversationStatusIndicatorState();
}

class _ConversationStatusIndicatorState
    extends State<_ConversationStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      label: widget.text,
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.text,
              key: const ValueKey('conversation-status-text'),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color, height: 1.1)),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = _controller.value * 2 * pi - index * .75;
                final opacity = .35 + .65 * ((sin(phase) + 1) / 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Opacity(
                    opacity: opacity,
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                      child: const SizedBox.square(dimension: 3),
                    ),
                  ),
                );
              }),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ConversationList extends StatefulWidget {
  const _ConversationList(
      {required this.repository,
      this.realtimeSession,
      this.serverUrl,
      this.cacheScope,
      this.realtimeStore,
      required this.selectedId,
      required this.onSelect,
      this.onUnreadChanged});
  final MagicChatRepository repository;
  final RealtimeSession? realtimeSession;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final RealtimeStore? realtimeStore;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<int>? onUnreadChanged;
  @override
  State<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<_ConversationList> {
  Future<List<ChatConversation>>? _future;
  List<ChatConversation> _loadedConversations = const [];
  String? _currentUserId;
  ConversationFilter _filter = ConversationFilter.all;
  String _query = '';
  bool _markingAllRead = false;
  Timer? _fallbackPollTimer;
  bool _fallbackPollInFlight = false;
  @override
  void initState() {
    super.initState();
    _currentUserId = widget.realtimeStore?.currentUserId;
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    if (widget.realtimeSession != null) {
      _fallbackPollTimer = Timer.periodic(
          const Duration(seconds: 15), (_) => unawaited(_pollFallback()));
    }
    unawaited(_loadCurrentUser());
    _reload();
  }

  Future<void> _loadCurrentUser() async {
    if (_currentUserId != null) return;
    try {
      final user = await widget.repository.currentUser();
      widget.realtimeStore?.setCurrentUserId(user.id);
      if (mounted) setState(() => _currentUserId = user.id);
    } catch (_) {
      // 会话列表仍可展示；服务端会再次校验群操作权限。
    }
  }

  void _onRealtimeChanged() {
    if (!mounted) return;
    final event = widget.realtimeStore?.lastEvent;
    if (event == 'conversation.removed' || event == 'topic.created') {
      setState(_reload);
      return;
    }
    final liveConversations = widget.realtimeStore?.conversations.values;
    if (liveConversations != null) {
      widget.onUnreadChanged?.call(totalConversationUnread(liveConversations));
    }
    setState(() {
      _currentUserId = widget.realtimeStore?.currentUserId ?? _currentUserId;
    });
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    super.dispose();
  }

  Future<void> _pollFallback() async {
    final session = widget.realtimeSession;
    if (!mounted || session == null || session.ready || _fallbackPollInFlight)
      return;
    _fallbackPollInFlight = true;
    try {
      final future = _loadConversations();
      if (mounted) setState(() => _future = future);
      await future;
    } catch (_) {
      // 保留现有会话列表，下一周期继续尝试；实时重连不受 HTTP 失败影响。
    } finally {
      _fallbackPollInFlight = false;
    }
  }

  void _reload() {
    _future = _loadConversations();
  }

  Future<List<ChatConversation>> _loadConversations() async {
    final conversations = await widget.repository.conversations();
    if (widget.realtimeStore != null) {
      for (final conversation in conversations) {
        widget.realtimeStore!.conversations[conversation.id] = conversation;
      }
    }
    if (mounted) {
      widget.onUnreadChanged?.call(totalConversationUnread(conversations));
    }
    return conversations;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ChatConversation>>(
      future: _future,
      initialData: _loadedConversations.isEmpty ? null : _loadedConversations,
      builder: (context, snapshot) {
        if (snapshot.hasData) _loadedConversations = snapshot.data!;
        final loaded = snapshot.data ?? _loadedConversations;
        if (snapshot.hasError && loaded.isEmpty) {
          return Center(
              child: TextButton.icon(
                  onPressed: () => setState(_reload),
                  icon: const Icon(Icons.refresh),
                  label: const Text('会话加载失败，点击重试')));
        }
        if (loaded.isEmpty && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final live = widget.realtimeStore?.conversations ?? const {};
        final merged = <String, ChatConversation>{
          for (final item in loaded) item.id: item,
        };
        for (final entry in live.entries) {
          if (merged.containsKey(entry.key)) merged[entry.key] = entry.value;
        }
        // 先物化筛选结果，避免 ListView.builder 在大量会话下反复对
        // lazy Iterable 调用 elementAt 造成 O(n²) 遍历。
        final ordered = orderConversations(merged.values);
        final matchingTopicParents = ordered
            .where((item) =>
                item.type == 'topic' &&
                matchesConversationFilter(item, _filter) &&
                matchesConversationQuery(item, _query))
            .map((item) => item.topic?.parentConversationId)
            .whereType<String>()
            .toSet();
        final filtered = ordered.where((item) {
          if (!matchesConversationFilter(item, _filter)) return false;
          if (matchesConversationQuery(item, _query)) return true;
          return item.type != 'topic' && matchingTopicParents.contains(item.id);
        });
        final rows = buildConversationRows(filtered);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: rows.isEmpty ? 2 : rows.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _conversationFilters(context);
                }
                if (rows.isEmpty) {
                  final colors = Theme.of(context).colorScheme;
                  return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.forum_outlined,
                            color: colors.outline, size: 36),
                        const SizedBox(height: 10),
                        Text('没有匹配的会话',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ])));
                }
                final row = rows.elementAt(i - 1);
                final c = row.conversation;
                final mentionUnread = c.lastMentionedSeq > c.lastReadSeq;
                final choiceUnread = c.lastChoiceSeq > c.lastReadSeq;
                final hasUnread = c.unread > 0 || mentionUnread || choiceUnread;
                final titleStyle = TextStyle(
                    fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500);
                final subtitleStyle =
                    TextStyle(fontWeight: hasUnread ? FontWeight.w600 : null);
                final messageTime = _conversationTime(c);
                final previewContacts = <String, Contact>{
                  // 会话列表不应为了预览提及而拉取整本组织通讯录。服务端
                  // 会话已经带有成员资料，实时缓存则补充最近更新的昵称/头像。
                  for (final contact in widget.realtimeStore?.contacts.values ??
                      const <Contact>[])
                    contact.id: contact,
                  for (final member in c.members) member.id: member,
                }.values;
                final preview = formatMentionText(
                    c.announcement.isNotEmpty
                        ? '公告：${c.announcement}'
                        : c.preview,
                    previewContacts.map((contact) => (
                          id: contact.id,
                          name: contact.displayName,
                        )));
                final statusIcons = <Widget>[
                  if (c.pinned)
                    const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.push_pin,
                            semanticLabel: '已置顶', size: 16)),
                  if (c.muted)
                    const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.notifications_off,
                            semanticLabel: '消息免打扰', size: 16)),
                ];
                final title = row.nested
                    ? Row(children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.subdirectory_arrow_right,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                        Expanded(
                            child: Text(c.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle)),
                        ...statusIcons,
                      ])
                    : statusIcons.isEmpty
                        ? Text(c.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle)
                        : Row(children: [
                            Expanded(
                                child: Text(c.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle)),
                            ...statusIcons,
                          ]);
                return ListTile(
                    key: ValueKey('conversation-row-${c.id}'),
                    minVerticalPadding: 10,
                    contentPadding: EdgeInsets.only(
                        left: row.nested ? 30 : 12,
                        right: 12,
                        top: 2,
                        bottom: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    selected: c.id == widget.selectedId,
                    selectedTileColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    leading: ConversationAvatar(
                        repository: widget.repository,
                        cacheScope: widget.cacheScope,
                        serverUrl: widget.serverUrl,
                        conversation: c,
                        radius: 23),
                    title: title,
                    subtitle: Text(preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (messageTime != null)
                        Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(messageTime,
                                style: Theme.of(context).textTheme.labelSmall)),
                      if (mentionUnread)
                        const Icon(Icons.alternate_email,
                            size: 17, semanticLabel: '有人提及你'),
                      if (choiceUnread)
                        const Icon(Icons.checklist,
                            size: 17, semanticLabel: '有待响应的选择题'),
                      if (c.unread > 0) Badge(label: Text('${c.unread}')),
                    ]),
                    onTap: () async {
                      widget.onSelect(c.id);
                      if (hasUnread && c.lastMessageSeq > c.lastReadSeq) {
                        try {
                          final result = await widget.repository
                              .markConversationRead(c.id, c.lastMessageSeq);
                          widget.realtimeStore?.markConversationRead(result);
                          if (mounted) setState(_reload);
                        } catch (_) {
                          // 打开会话不应被已读接口失败阻断。
                        }
                      }
                    },
                    onLongPress: row.nested
                        ? null
                        : () => _showConversationActions(context, c));
              }),
        );
      });

  Future<void> _refresh() async {
    final future = _loadConversations();
    setState(() {
      _future = future;
    });
    await future;
  }

  Widget _conversationFilters(BuildContext context) => Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '搜索会话',
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () => setState(() => _query = ''),
                            icon: const Icon(Icons.clear))),
                onChanged: (value) => setState(() => _query = value)),
          ),
          const SizedBox(width: 4),
          IconButton(
              tooltip: '全部标为已读',
              onPressed: _markingAllRead ? null : _markAllRead,
              icon: _markingAllRead
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.done_all_outlined)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
              scrollDirection: Axis.horizontal,
              children: ConversationFilter.values
                  .map((filter) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                            label: Text(conversationFilterLabel(filter)),
                            selected: _filter == filter,
                            onSelected: (_) =>
                                setState(() => _filter = filter)),
                      ))
                  .toList()),
        )
      ]);

  Future<void> _markAllRead() async {
    if (_markingAllRead) return;
    final live = widget.realtimeStore?.conversations ?? const {};
    final all = <String, ChatConversation>{
      for (final item in _loadedConversations) item.id: item,
      ...live,
    }.values;
    final unread = all
        .where((conversation) =>
            conversationUnreadCount(conversation) > 0 &&
            conversationReadTargetSequence(conversation) >
                conversation.lastReadSeq)
        .toList(growable: false);
    if (unread.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前没有未读会话')));
      }
      return;
    }
    setState(() => _markingAllRead = true);
    var failed = 0;
    for (final conversation in unread) {
      try {
        final targetSequence = conversationReadTargetSequence(conversation);
        final result = await widget.repository
            .markConversationRead(conversation.id, targetSequence);
        widget.realtimeStore?.markConversationRead(result);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _markingAllRead = false;
      _reload();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed == 0
            ? '已将 ${unread.length} 个会话标为已读'
            : '已处理 ${unread.length - failed} 个会话，$failed 个失败')));
  }

  String? _conversationTime(ChatConversation conversation) {
    final value = conversation.lastMessageAt.isNotEmpty
        ? conversation.lastMessageAt
        : conversation.createdAt;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final time = '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
    if (sameDay) return time;
    return '${twoDigits(local.month)}-${twoDigits(local.day)}';
  }

  Future<void> _showConversationActions(
      BuildContext context, ChatConversation conversation) async {
    final isGroup = conversation.type == 'group';
    Contact? currentMember;
    if (isGroup) {
      for (final member in conversation.members) {
        if (member.type == 'user' && member.id == _currentUserId) {
          currentMember = member;
          break;
        }
      }
    }
    final role = currentMember?.role;
    final canManage = role == 'owner' || role == 'admin';
    final isOwner = role == 'owner';
    final removableMembers = conversation.members
        .where((member) =>
            member.role != 'owner' &&
            !(member.type == 'user' && member.id == _currentUserId))
        .toList();
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(conversation.pinned ? '取消置顶' : '置顶会话'),
                  onTap: () => Navigator.pop(
                      context, conversation.pinned ? 'unpin' : 'pin')),
              ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: Text(conversation.muted ? '取消免打扰' : '消息免打扰'),
                  onTap: () => Navigator.pop(
                      context, conversation.muted ? 'unmute' : 'mute')),
              ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('从列表移除'),
                  onTap: () => Navigator.pop(context, 'dismiss')),
              if (isGroup) ...[
                if (canManage)
                  ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('修改群名称'),
                      onTap: () => Navigator.pop(context, 'rename')),
                if (canManage)
                  ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('修改群公告'),
                      onTap: () => Navigator.pop(context, 'announcement')),
                if (isOwner)
                  ListTile(
                      leading: const Icon(Icons.public_outlined),
                      title: Text(conversation.isPublic ? '设为私有群' : '设为公开群'),
                      onTap: () => Navigator.pop(context, 'visibility')),
                if (canManage)
                  ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('修改群头像'),
                      onTap: () => Navigator.pop(context, 'avatar')),
                if (currentMember != null)
                  ListTile(
                      leading: const Icon(Icons.person_add_outlined),
                      title: const Text('添加群成员'),
                      onTap: () => Navigator.pop(context, 'members')),
                if (canManage && removableMembers.isNotEmpty)
                  ListTile(
                      leading: const Icon(Icons.person_remove_outlined),
                      title: const Text('移除群成员'),
                      onTap: () => Navigator.pop(context, 'remove_member')),
                if (currentMember != null)
                  ListTile(
                      leading: Icon(isOwner
                          ? Icons.delete_forever_outlined
                          : Icons.logout_outlined),
                      title: Text(isOwner ? '解散群聊' : '退出群聊'),
                      onTap: () => Navigator.pop(
                          context, isOwner ? 'dissolve' : 'leave')),
              ],
            ])));
    if (!context.mounted || action == null) return;
    if (action == 'pin' || action == 'unpin') {
      await widget.repository
          .setConversationPinned(conversation.id, action == 'pin');
    } else if (action == 'mute' || action == 'unmute') {
      await widget.repository
          .setConversationMuted(conversation.id, action == 'mute');
    } else if (action == 'dismiss') {
      await widget.repository.dismissConversation(conversation.id);
    } else if (action == 'rename') {
      final controller = TextEditingController(text: conversation.title);
      final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('修改群名称'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('保存'))
                ],
              ));
      controller.dispose();
      if (name != null && name.isNotEmpty && context.mounted) {
        await widget.repository.renameGroupConversation(conversation.id, name);
      }
    } else if (action == 'announcement') {
      final controller = TextEditingController(text: conversation.announcement);
      final announcement = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('修改群公告'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 200,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: '留空可清除群公告')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('保存'))
                ],
              ));
      controller.dispose();
      if (announcement != null && context.mounted) {
        await widget.repository
            .updateGroupAnnouncement(conversation.id, announcement.trim());
      }
    } else if (action == 'visibility') {
      await widget.repository
          .setGroupVisibility(conversation.id, !conversation.isPublic);
    } else if (action == 'avatar') {
      final result =
          await FilePicker.pickFiles(type: FileType.image, withData: true);
      if (result == null || !context.mounted) return;
      final file = result.files.single;
      final rawBytes = file.bytes;
      if (rawBytes == null) return;
      final processed = const AvatarProcessor().process(rawBytes);
      await widget.repository.uploadConversationAvatar(
          conversation.id,
          AttachmentUpload(
              path: file.path ?? '',
              name: 'group-avatar.webp',
              mimeType: 'image/webp',
              bytes: processed));
    } else if (action == 'members') {
      final contacts = await widget.repository.contacts();
      if (!context.mounted) return;
      final existingIds =
          conversation.members.map((member) => member.id).toSet();
      final available = contacts
          .where((contact) =>
              contact.type == 'user' && !existingIds.contains(contact.id))
          .toList(growable: false);
      final selected = <String>{};
      final members = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('添加群成员'),
            content: SizedBox(
                width: 360,
                height: 320,
                child: ListView(
                    children: available
                        .map((contact) => CheckboxListTile(
                              value: selected.contains(contact.id),
                              title: Text(contact.displayName),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  selected.add(contact.id);
                                } else {
                                  selected.remove(contact.id);
                                }
                              }),
                            ))
                        .toList())),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, selected.toList()),
                  child: const Text('添加')),
            ],
          ),
        ),
      );
      if (members != null && members.isNotEmpty && context.mounted) {
        await widget.repository
            .addConversationMembers(conversation.id, memberIds: members);
      }
    } else if (action == 'remove_member') {
      final member = await showDialog<Contact>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
                title: const Text('选择要移除的成员'),
                children: removableMembers
                    .map((item) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(dialogContext, item),
                        child: Row(children: [
                          Expanded(child: Text(item.displayName)),
                          if (item.role != 'member')
                            Chip(
                                label:
                                    Text(item.role == 'owner' ? '群主' : '管理员'),
                                visualDensity: VisualDensity.compact)
                        ])))
                    .toList(),
              ));
      if (member != null && context.mounted) {
        await widget.repository.removeConversationMember(
            conversation.id, member.id,
            memberType: member.type);
      }
    } else if (action == 'leave' || action == 'dissolve') {
      final leaving = action == 'leave';
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(leaving ? '退出群聊' : '解散群聊'),
                content: Text(leaving
                    ? '退出后将无法继续查看和发送该群聊消息。'
                    : '解散后所有成员都无法继续查看和发送该群聊消息。此操作不可恢复。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(leaving ? '退出' : '解散')),
                ],
              ));
      if (confirmed == true && context.mounted) {
        if (leaving) {
          await widget.repository.leaveGroupConversation(conversation.id);
        } else {
          await widget.repository.dissolveGroupConversation(conversation.id);
        }
        if (context.mounted) widget.onSelect('');
      }
    }
    if (mounted) setState(_reload);
  }
}
