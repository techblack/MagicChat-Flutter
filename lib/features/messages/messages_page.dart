part of '../../main.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage(
      {required this.repository,
      this.serverUrl,
      this.realtimeStore,
      this.cacheScope,
      required this.selectedId,
      required this.onSelect,
      this.onOpenConversation,
      this.onBack,
      this.onSearch,
      this.onOpenInternalLink,
      this.focusMessageId,
      this.focusMessageSequence,
      this.onMessageFocused,
      this.onUnreadChanged,
      super.key});
  final MagicChatRepository repository;
  final String? serverUrl;
  final RealtimeStore? realtimeStore;
  final MessageCacheScope? cacheScope;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpenConversation;
  final VoidCallback? onBack;
  final VoidCallback? onSearch;
  final ValueChanged<String>? onOpenInternalLink;
  final String? focusMessageId;
  final int? focusMessageSequence;
  final VoidCallback? onMessageFocused;
  final ValueChanged<int>? onUnreadChanged;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final split = constraints.maxWidth >= 700;
        final conversationList = Stack(children: [
          Positioned.fill(
              child: _ConversationList(
                  repository: repository,
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
                  onPressed: () => _createGroup(context),
                  tooltip: '新建群聊',
                  child: const Icon(Icons.group_add))),
        ]);
        final conversationView = ConversationView(
          repository: repository,
          realtimeStore: realtimeStore,
          cacheScope: cacheScope,
          conversationId: selectedId,
          focusMessageId: focusMessageId,
          focusMessageSequence: focusMessageSequence,
          onOpenConversation: onOpenConversation ?? onSelect,
          onOpenInternalLink: onOpenInternalLink,
          onMessageFocused: onMessageFocused,
        );
        if (!split) {
          return IndexedStack(
            index: selectedId == null ? 0 : 1,
            children: [
              conversationList,
              if (selectedId == null)
                const SizedBox.shrink()
              else
                Column(children: [
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: SizedBox(
                      height: 52,
                      child: Row(children: [
                        IconButton(
                          tooltip: '返回会话列表',
                          onPressed: onBack ?? () => onSelect(''),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Text('聊天',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (onSearch != null)
                          IconButton(
                            tooltip: '搜索',
                            onPressed: onSearch,
                            icon: const Icon(Icons.search),
                          ),
                      ]),
                    ),
                  ),
                  Expanded(child: conversationView),
                ]),
            ],
          );
        }
        return Row(children: [
          SizedBox(width: 300, child: conversationList),
          Expanded(child: conversationView),
        ]);
      });

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：$error')));
    }
  }

  Future<List<String>?> _selectMembers(BuildContext context) async {
    final contacts = await repository.contacts();
    if (!context.mounted) return null;
    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final list = contacts
              .map((contact) => CheckboxListTile(
                    value: selected.contains(contact.id),
                    title: Text(contact.name),
                    onChanged: (checked) => setDialogState(() {
                      if (checked == true) {
                        selected.add(contact.id);
                      } else {
                        selected.remove(contact.id);
                      }
                    }),
                  ))
              .toList();
          return AlertDialog(
            title: const Text('选择群成员'),
            content: SizedBox(
                width: 360,
                height: 320,
                child: list.isEmpty
                    ? const Center(child: Text('暂无联系人'))
                    : ListView(children: list)),
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

class _ConversationList extends StatefulWidget {
  const _ConversationList(
      {required this.repository,
      this.serverUrl,
      this.cacheScope,
      this.realtimeStore,
      required this.selectedId,
      required this.onSelect,
      this.onUnreadChanged});
  final MagicChatRepository repository;
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
  String? _currentUserId;
  ConversationFilter _filter = ConversationFilter.all;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _currentUserId = widget.realtimeStore?.currentUserId;
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    unawaited(_loadCurrentUser());
    _reload();
  }

  Future<void> _loadCurrentUser() async {
    if (_currentUserId != null) return;
    try {
      final user = await widget.repository.currentUser();
      if (mounted) setState(() => _currentUserId = user.id);
    } catch (_) {
      // 会话列表仍可展示；服务端会再次校验群操作权限。
    }
  }

  void _onRealtimeChanged() {
    if (!mounted) return;
    setState(() {
      _currentUserId = widget.realtimeStore?.currentUserId ?? _currentUserId;
      _reload();
    });
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    super.dispose();
  }

  void _reload() => _future = _loadConversations();

  Future<List<ChatConversation>> _loadConversations() async {
    final conversations = await widget.repository.conversations();
    if (mounted) {
      widget.onUnreadChanged?.call(totalConversationUnread(conversations));
    }
    return conversations;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ChatConversation>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: TextButton.icon(
                  onPressed: () => setState(_reload),
                  icon: const Icon(Icons.refresh),
                  label: const Text('会话加载失败，点击重试')));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final conversations = orderConversations(snapshot.data!).where((item) =>
            matchesConversationFilter(item, _filter) &&
            matchesConversationQuery(item, _query));
        return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: conversations.isEmpty ? 2 : conversations.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (context, i) {
              if (i == 0) {
                return _conversationFilters(context);
              }
              if (conversations.isEmpty) {
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
              final c = conversations.elementAt(i - 1);
              final mentionUnread = c.lastMentionedSeq > c.lastReadSeq;
              final choiceUnread = c.lastChoiceSeq > c.lastReadSeq;
              final hasUnread = c.unread > 0 || mentionUnread || choiceUnread;
              final titleStyle = TextStyle(
                  fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500);
              final subtitleStyle =
                  TextStyle(fontWeight: hasUnread ? FontWeight.w600 : null);
              final statusIcons = <Widget>[
                if (c.pinned)
                  const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child:
                          Icon(Icons.push_pin, semanticLabel: '已置顶', size: 16)),
                if (c.muted)
                  const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.notifications_off,
                          semanticLabel: '消息免打扰', size: 16)),
              ];
              return ListTile(
                  minVerticalPadding: 10,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  selected: c.id == widget.selectedId,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  leading: CachedAvatar(
                      repository: widget.repository,
                      cacheScope: widget.cacheScope,
                      avatarUri: _resolveAssetUri(widget.serverUrl, c.avatar),
                      name: c.title,
                      radius: 23),
                  title: statusIcons.isEmpty
                      ? Text(c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle)
                      : Row(children: [
                          Expanded(
                              child: Text(c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle)),
                          ...statusIcons,
                        ]),
                  subtitle: Text(
                      c.announcement.isNotEmpty
                          ? '公告：${c.announcement}'
                          : c.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle),
                  trailing: !hasUnread
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
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
                  onLongPress: () => _showConversationActions(context, c));
            });
      });

  Widget _conversationFilters(BuildContext context) => Column(children: [
        TextField(
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
                if (currentMember != null)
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
      final controller = TextEditingController();
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
                    children: contacts
                        .map((contact) => CheckboxListTile(
                              value: selected.contains(contact.id),
                              title: Text(contact.name),
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
                          Expanded(child: Text(item.name)),
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
