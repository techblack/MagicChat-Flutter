import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/avatar_processor.dart';
import '../../data/chat_appearance_preferences.dart';
import '../../data/message_cache_store.dart';
import '../../data/realtime_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/cached_avatar.dart';

class ConversationDetailsPage extends StatefulWidget {
  const ConversationDetailsPage({
    required this.repository,
    required this.conversationId,
    this.initialConversation,
    this.serverUrl,
    this.cacheScope,
    this.realtimeStore,
    this.onOpenConversation,
    this.onConversationRemoved,
    this.chatAppearance = const ChatAppearance(),
    this.conversationAppearance,
    this.onConversationAppearanceChanged,
    super.key,
  });

  final MagicChatRepository repository;
  final String conversationId;
  final ChatConversation? initialConversation;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final RealtimeStore? realtimeStore;
  final ValueChanged<String>? onOpenConversation;
  final VoidCallback? onConversationRemoved;
  final ChatAppearance chatAppearance;
  final ChatConversationAppearance? conversationAppearance;
  final Future<void> Function(
          String conversationId, ChatConversationAppearance appearance)?
      onConversationAppearanceChanged;

  @override
  State<ConversationDetailsPage> createState() =>
      _ConversationDetailsPageState();
}

class _ConversationDetailsPageState extends State<ConversationDetailsPage> {
  late Future<_ConversationDetailsData> _future = _load();
  bool _busy = false;

  Future<_ConversationDetailsData> _load() async {
    final results = await Future.wait([
      widget.repository.conversations(),
      widget.repository.currentUser(),
    ]);
    final conversations = results[0] as List<ChatConversation>;
    final currentUser = results[1] as CurrentUser;
    ChatConversation? conversation =
        widget.realtimeStore?.conversations[widget.conversationId] ??
            widget.initialConversation;
    for (final item in conversations) {
      if (item.id == widget.conversationId) {
        conversation = item;
        break;
      }
    }
    if (conversation == null) {
      throw StateError('会话不存在或已不可用');
    }
    final contacts = <String, Contact>{
      for (final contact
          in widget.realtimeStore?.contacts.values ?? const <Contact>[])
        contact.id: contact,
      for (final member in conversation.members) member.id: member,
    }.values.toList(growable: false);
    TopicDetail? topicDetail;
    if (conversation.type == 'topic') {
      topicDetail = await widget.repository.topicDetail(conversation.id);
      conversation = topicDetail.conversation;
    }
    var availableProjects = const <Project>[];
    if (conversation.type == 'group') {
      try {
        availableProjects = await widget.repository.projects();
      } catch (_) {
        // 项目服务不可用时仍可查看和管理其他聊天详情。
      }
    }
    final hydrated = _hydrateConversation(conversation, contacts);
    widget.realtimeStore?.replaceConversation(hydrated);
    return _ConversationDetailsData(
        conversation: hydrated,
        currentUser: currentUser,
        contacts: contacts,
        availableProjects: availableProjects,
        topicDetail: topicDetail);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _run(Future<void> Function() action,
      {String? successMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      final future = _load();
      setState(() {
        _future = future;
      });
      await future;
      if (successMessage != null && mounted) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => FutureBuilder<_ConversationDetailsData>(
        future: _future,
        builder: (context, snapshot) {
          final conversation =
              snapshot.data?.conversation ?? widget.initialConversation;
          return Scaffold(
            appBar: AppBar(
              title: Text(_pageTitle(conversation)),
              actions: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
            body: snapshot.hasError
                ? Center(
                    child: TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('会话详情加载失败，点击重试')))
                : !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : _details(snapshot.data!),
          );
        },
      );

  Widget _details(_ConversationDetailsData data) {
    final conversation = data.conversation;
    final currentMember = _currentMember(conversation, data.currentUser.id);
    final isOwner = currentMember?.role == 'owner';
    final canManage = isOwner || currentMember?.role == 'admin';
    final canAddMembers = conversation.type == 'group' && currentMember != null;
    final visibleMembers = _visibleMembers(conversation, data.currentUser.id);
    final removable = conversation.members
        .where((member) =>
            member.role != 'owner' && !_sameId(member.id, data.currentUser.id))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        if (conversation.type != 'topic')
          Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 14,
                  children: [
                    ...visibleMembers.map((member) => _MemberTile(
                          member: member,
                          repository: widget.repository,
                          serverUrl: widget.serverUrl,
                          cacheScope: widget.cacheScope,
                          onTap: () => _showMember(member),
                        )),
                    if (conversation.type == 'direct' || canAddMembers)
                      _ActionMemberTile(
                          icon: Icons.add,
                          label: '添加',
                          onTap: conversation.type == 'direct'
                              ? () => _createGroup(data)
                              : () => _addMembers(data)),
                    if (canManage && removable.isNotEmpty)
                      _ActionMemberTile(
                          icon: Icons.remove,
                          label: '移除',
                          onTap: () => _removeMember(data, removable)),
                  ],
                ),
              ),
            ),
          ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(children: [
                if (conversation.type == 'group') ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      ListTile(
                        enabled: canManage && !_busy,
                        title: const Text('群聊名称'),
                        subtitle: Text(conversation.displayTitle),
                        trailing:
                            canManage ? const Icon(Icons.chevron_right) : null,
                        onTap: canManage ? () => _editName(conversation) : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        enabled: canManage && !_busy,
                        title: const Text('群公告'),
                        subtitle: Text(conversation.announcement.trim().isEmpty
                            ? '未设置'
                            : conversation.announcement.trim()),
                        trailing:
                            canManage ? const Icon(Icons.chevron_right) : null,
                        onTap: canManage
                            ? () => _editAnnouncement(conversation)
                            : null,
                      ),
                      if (canManage) ...[
                        const Divider(height: 1, indent: 16),
                        ListTile(
                          enabled: !_busy,
                          leading: const Icon(Icons.image_outlined),
                          title: const Text('群头像'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _pickAvatar(conversation),
                        ),
                      ],
                      if (isOwner) ...[
                        const Divider(height: 1, indent: 16),
                        SwitchListTile(
                          secondary: const Icon(Icons.public_outlined),
                          title: const Text('公开群聊'),
                          subtitle: Text(conversation.isPublic
                              ? '所有用户可在通讯录中发现并加入'
                              : '仅受邀成员可访问'),
                          value: conversation.isPublic,
                          onChanged: _busy
                              ? null
                              : (value) => _run(() => widget.repository
                                  .setGroupVisibility(conversation.id, value)),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _conversationProjectsCard(
                      data, conversation, canManage && !_busy),
                ],
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_off_outlined),
                      title: const Text('消息免打扰'),
                      value: conversation.muted,
                      onChanged: _busy
                          ? null
                          : (value) => _run(() async {
                                await widget.repository.setConversationMuted(
                                    conversation.id, value);
                              }),
                    ),
                    const Divider(height: 1, indent: 16),
                    SwitchListTile(
                      secondary: const Icon(Icons.push_pin_outlined),
                      title: const Text('置顶对话'),
                      value: conversation.pinned,
                      onChanged: _busy
                          ? null
                          : (value) => _run(() async {
                                await widget.repository.setConversationPinned(
                                    conversation.id, value);
                              }),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.wallpaper_outlined),
                    title: const Text('聊天外观'),
                    subtitle: Text(_appearanceSummary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        _busy ? null : () => _editAppearance(conversation.id),
                  ),
                ),
                if (conversation.type == 'topic' &&
                    data.topicDetail?.canArchive == true &&
                    conversation.topic?.archived != true) ...[
                  const SizedBox(height: 14),
                  _DangerAction(
                    icon: Icons.archive_outlined,
                    label: '关闭话题',
                    onTap:
                        _busy ? null : () => _confirmTopicArchive(conversation),
                  ),
                ],
                if (conversation.type == 'group' && currentMember != null) ...[
                  const SizedBox(height: 14),
                  _DangerAction(
                    icon: isOwner
                        ? Icons.delete_forever_outlined
                        : Icons.logout_outlined,
                    label: isOwner ? '解散群聊' : '退出群聊',
                    onTap: _busy
                        ? null
                        : () => _confirmGroupExit(conversation, isOwner),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ],
    );
  }

  String get _appearanceSummary {
    final appearance = _effectiveAppearance;
    return '${appearance.background.label}背景 · ${appearance.bubble.label}气泡';
  }

  ChatConversationAppearance get _effectiveAppearance =>
      widget.conversationAppearance ??
      ChatConversationAppearance(
          background: widget.chatAppearance.background,
          bubble: widget.chatAppearance.bubble);

  Future<void> _editAppearance(String conversationId) async {
    var background = _effectiveAppearance.background;
    var bubble = _effectiveAppearance.bubble;
    final result = await showDialog<ChatConversationAppearance>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('聊天外观'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<ChatBackground>(
              value: background,
              decoration: const InputDecoration(labelText: '聊天背景'),
              items: ChatBackground.values
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => background = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ChatBubbleSkin>(
              value: bubble,
              decoration: const InputDecoration(labelText: '聊天气泡'),
              items: ChatBubbleSkin.values
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => bubble = value);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    dialogContext,
                    ChatConversationAppearance(
                        background: background, bubble: bubble)),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await widget.onConversationAppearanceChanged?.call(conversationId, result);
    if (mounted) setState(() {});
  }

  Widget _conversationProjectsCard(_ConversationDetailsData data,
      ChatConversation conversation, bool canManage) {
    final linked = conversation.projects;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.work_outline),
          title: Text('关联项目（${linked.length}）'),
          subtitle: Text(linked.isEmpty ? '暂无关联项目' : '群成员可使用关联项目的协作内容'),
          trailing: canManage
              ? IconButton(
                  tooltip: '关联项目',
                  onPressed: () => _showProjectPicker(data, conversation),
                  icon: const Icon(Icons.add_circle_outline))
              : null,
        ),
        if (linked.isNotEmpty)
          ...linked.expand((project) => [
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(project.name),
                  subtitle: project.description.trim().isEmpty
                      ? null
                      : Text(project.description.trim(),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: canManage
                      ? IconButton(
                          tooltip: '解除关联',
                          onPressed: () =>
                              _confirmUnbindProject(conversation, project),
                          icon: const Icon(Icons.link_off_outlined))
                      : null,
                ),
              ]),
      ]),
    );
  }

  Future<void> _showProjectPicker(
      _ConversationDetailsData data, ChatConversation conversation) async {
    final linkedIds =
        conversation.projects.map((project) => project.id).toSet();
    final candidates = data.availableProjects
        .where(
            (project) => !project.isPersonal && !linkedIds.contains(project.id))
        .toList(growable: false);
    if (candidates.isEmpty) {
      _showMessage('暂无可关联的项目');
      return;
    }
    var keyword = '';
    String? selectedId;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final visible = candidates.where((project) {
            final query = keyword.trim().toLowerCase();
            return query.isEmpty ||
                project.name.toLowerCase().contains(query) ||
                project.description.toLowerCase().contains(query);
          }).toList(growable: false);
          return AlertDialog(
            title: const Text('关联项目'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search), hintText: '搜索项目'),
                    onChanged: (value) =>
                        setDialogState(() => keyword = value)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: visible.isEmpty
                      ? const Center(child: Text('没有匹配的项目'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final project = visible[index];
                            final selected = selectedId == project.id;
                            return ListTile(
                              leading: Icon(selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked),
                              title: Text(project.name),
                              subtitle: project.description.trim().isEmpty
                                  ? null
                                  : Text(project.description.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                              selected: selected,
                              onTap: () =>
                                  setDialogState(() => selectedId = project.id),
                            );
                          }),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: selectedId == null
                      ? null
                      : () => Navigator.pop(dialogContext, selectedId),
                  child: const Text('关联')),
            ],
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    await _run(
        () => widget.repository
            .bindConversationProject(conversation.id, selected),
        successMessage: '项目已关联');
  }

  Future<void> _confirmUnbindProject(
      ChatConversation conversation, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解除项目关联？'),
        content: Text('确定解除群聊与“${project.name}”的关联吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('解除关联')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
        () => widget.repository
            .unbindConversationProject(conversation.id, project.id),
        successMessage: '已解除项目关联');
  }

  String _pageTitle(ChatConversation? conversation) {
    if (conversation?.type == 'group') {
      return '聊天信息 (${conversation!.effectiveMemberCount})';
    }
    return conversation?.type == 'topic' ? '话题详情' : '聊天详情';
  }

  Contact? _currentMember(ChatConversation conversation, String currentUserId) {
    for (final member in conversation.members) {
      if (member.type == 'user' && _sameId(member.id, currentUserId)) {
        return member;
      }
    }
    return null;
  }

  List<Contact> _visibleMembers(
      ChatConversation conversation, String currentUserId) {
    if (conversation.type == 'group') return conversation.members;
    if (conversation.type == 'direct') {
      return conversation.members
          .where((member) =>
              member.type == 'user' && !_sameId(member.id, currentUserId))
          .toList(growable: false);
    }
    return conversation.members
        .where((member) => member.type == 'app')
        .toList(growable: false);
  }

  Future<void> _showMember(Contact member) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _memberAvatar(member, 34),
            const SizedBox(height: 10),
            Text(member.displayName,
                style: Theme.of(context).textTheme.titleLarge),
            if (member.email.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(member.email.trim()),
            ],
            if (member.phone.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(member.phone.trim()),
            ],
            if (member.role != 'member') ...[
              const SizedBox(height: 10),
              Chip(label: Text(member.role == 'owner' ? '群主' : '管理员')),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _memberAvatar(Contact member, double radius) => CachedAvatar(
        repository: widget.repository,
        cacheScope: widget.cacheScope,
        avatarUri: _assetUri(member.avatar),
        name: member.displayName,
        radius: radius,
      );

  Uri? _assetUri(String value) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;
    if (uri.hasScheme) return uri;
    return Uri.tryParse(widget.serverUrl ?? '')?.resolveUri(uri);
  }

  Future<void> _createGroup(_ConversationDetailsData data) async {
    final initial = _visibleMembers(data.conversation, data.currentUser.id)
        .where((member) => member.type == 'user')
        .map((member) => member.id)
        .toSet();
    final members =
        await _selectMembers(data, title: '选择联系人', initiallySelected: initial);
    if (members == null || members.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await widget.repository
          .createGroupConversation('新建群聊', memberIds: members);
      if (mounted) {
        widget.onOpenConversation?.call(created.id);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) _showMessage('创建群聊失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMembers(_ConversationDetailsData data) async {
    final existing = data.conversation.members
        .where((member) => member.type == 'user')
        .map((member) => member.id)
        .toSet();
    final members =
        await _selectMembers(data, title: '添加群成员', excluded: existing);
    if (members == null || members.isEmpty || !mounted) return;
    await _run(() => widget.repository
        .addConversationMembers(data.conversation.id, memberIds: members));
  }

  Future<List<String>?> _selectMembers(_ConversationDetailsData data,
      {required String title,
      Set<String> initiallySelected = const {},
      Set<String> excluded = const {}}) async {
    final availableDirectory = <String, Contact>{
      // 只有用户明确打开“添加成员”时才读取完整通讯录；详情首屏只依赖
      // 当前会话成员，避免 2000 人组织打开详情时产生额外请求。
      for (final contact in await widget.repository.contacts())
        if (contact.type == 'user') contact.id: contact,
      for (final contact in data.contacts)
        if (contact.type == 'user') contact.id: contact,
      for (final member in data.conversation.members)
        if (member.type == 'user') member.id: member,
    };
    final contacts = availableDirectory.values
        .where((contact) =>
            !_sameId(contact.id, data.currentUser.id) &&
            !excluded.any((id) => _sameId(id, contact.id)))
        .toList(growable: false)
      ..sort((left, right) => left.displayName
          .toLowerCase()
          .compareTo(right.displayName.toLowerCase()));
    final selected = {...initiallySelected};
    var query = '';
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = contacts
              .where((contact) =>
                  query.isEmpty ||
                  contact.displayName.toLowerCase().contains(query))
              .toList(growable: false);
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(children: [
                TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: '搜索联系人'),
                  onChanged: (value) =>
                      setDialogState(() => query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('没有可选择的联系人'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final contact = visible[index];
                            return CheckboxListTile(
                              key: ValueKey(contact.id),
                              value: selected.contains(contact.id),
                              title: Text(contact.displayName),
                              subtitle: contact.email.trim().isEmpty
                                  ? null
                                  : Text(contact.email.trim()),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  selected.add(contact.id);
                                } else {
                                  selected.remove(contact.id);
                                }
                              }),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, selected.toList()),
                  child: const Text('完成')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _removeMember(
      _ConversationDetailsData data, List<Contact> members) async {
    final member = await showDialog<Contact>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择要移除的成员'),
        children: members
            .map((member) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, member),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(member.displayName),
                    trailing: member.role == 'admin'
                        ? const Chip(
                            label: Text('管理员'),
                            visualDensity: VisualDensity.compact)
                        : null,
                  ),
                ))
            .toList(growable: false),
      ),
    );
    if (member == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认移除成员？'),
        content: Text('移除“${member.displayName}”后，该成员将无法继续访问此群聊。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => widget.repository.removeConversationMember(
        data.conversation.id, member.id,
        memberType: member.type));
  }

  Future<void> _editName(ChatConversation conversation) async {
    final value = await _textDialog(
        title: '修改群名称',
        initialValue: conversation.displayTitle,
        maxLength: 120);
    if (value == null || value.trim().isEmpty || !mounted) return;
    await _run(() => widget.repository
        .renameGroupConversation(conversation.id, value.trim()));
  }

  Future<void> _editAnnouncement(ChatConversation conversation) async {
    final value = await _textDialog(
        title: '修改群公告',
        initialValue: conversation.announcement,
        maxLength: 200,
        maxLines: 5,
        hintText: '留空可清除群公告');
    if (value == null || !mounted) return;
    await _run(() => widget.repository
        .updateGroupAnnouncement(conversation.id, value.trim()));
  }

  Future<String?> _textDialog(
          {required String title,
          required String initialValue,
          required int maxLength,
          int maxLines = 1,
          String? hintText}) =>
      showDialog<String>(
        context: context,
        builder: (context) => _ConversationTextDialog(
            title: title,
            initialValue: initialValue,
            maxLength: maxLength,
            maxLines: maxLines,
            hintText: hintText),
      );

  Future<void> _pickAvatar(ChatConversation conversation) async {
    final result =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.single;
    if (file?.bytes == null || !mounted) return;
    try {
      final bytes = const AvatarProcessor().process(file!.bytes!);
      await _run(() => widget.repository.uploadConversationAvatar(
          conversation.id,
          AttachmentUpload(
              path: file.path ?? '',
              name: 'group-avatar.webp',
              mimeType: 'image/webp',
              bytes: bytes)));
    } catch (error) {
      if (mounted) _showMessage('群头像更新失败：$error');
    }
  }

  Future<void> _confirmGroupExit(
      ChatConversation conversation, bool dissolve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dissolve ? '确认解散群聊？' : '确认退出群聊？'),
        content: Text(dissolve ? '解散后，所有成员将无法继续访问该群聊。' : '退出后，你将无法继续接收该群聊的消息。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: Text(dissolve ? '确认解散' : '确认退出')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (dissolve) {
        await widget.repository.dissolveGroupConversation(conversation.id);
      } else {
        await widget.repository.leaveGroupConversation(conversation.id);
      }
      widget.realtimeStore?.removeConversation(conversation.id);
      widget.onConversationRemoved?.call();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _showMessage('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmTopicArchive(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭话题？'),
        content: const Text('关闭后不能继续发送消息或回应。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('关闭话题')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() async {
        await widget.repository.archiveTopic(conversation.id);
      });
    }
  }

  bool _sameId(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();
}

class _ConversationDetailsData {
  const _ConversationDetailsData({
    required this.conversation,
    required this.currentUser,
    required this.contacts,
    this.availableProjects = const [],
    this.topicDetail,
  });

  final ChatConversation conversation;
  final CurrentUser currentUser;
  final List<Contact> contacts;
  final List<Project> availableProjects;
  final TopicDetail? topicDetail;
}

ChatConversation _hydrateConversation(
    ChatConversation conversation, List<Contact> contacts) {
  final contactsById = {for (final contact in contacts) contact.id: contact};
  final members = conversation.members.map((member) {
    final contact = contactsById[member.id];
    if (contact == null) return member;
    return contact.copyWith(
        name: member.name.trim().isEmpty || member.name.trim() == member.id
            ? null
            : member.name,
        nickname: member.nickname.trim().isEmpty ||
                member.nickname.trim() == member.id
            ? null
            : member.nickname,
        avatar: member.avatar.trim().isEmpty ? null : member.avatar,
        role: member.role,
        type: member.type);
  }).toList(growable: false);
  return ChatConversation(
    id: conversation.id,
    title: conversation.title,
    preview: conversation.preview,
    announcement: conversation.announcement,
    isPublic: conversation.isPublic,
    avatar: conversation.avatar,
    createdAt: conversation.createdAt,
    unread: conversation.unread,
    pinned: conversation.pinned,
    muted: conversation.muted,
    lastMessageAt: conversation.lastMessageAt,
    lastMessageSeq: conversation.lastMessageSeq,
    lastReadSeq: conversation.lastReadSeq,
    lastMentionedSeq: conversation.lastMentionedSeq,
    lastChoiceSeq: conversation.lastChoiceSeq,
    type: conversation.type,
    memberCount: conversation.memberCount,
    members: members,
    projects: conversation.projects,
    canSend: conversation.canSend,
    topic: conversation.topic,
  );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.repository,
    required this.serverUrl,
    required this.cacheScope,
    required this.onTap,
  });

  final Contact member;
  final MagicChatRepository repository;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = Uri.tryParse(member.avatar.trim());
    final uri = avatar == null || member.avatar.trim().isEmpty
        ? null
        : avatar.hasScheme
            ? avatar
            : Uri.tryParse(serverUrl ?? '')?.resolveUri(avatar);
    return SizedBox(
      width: 64,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            CachedAvatar(
                repository: repository,
                cacheScope: cacheScope,
                avatarUri: uri,
                name: member.displayName,
                radius: 22),
            const SizedBox(height: 5),
            Text(member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _ActionMemberTile extends StatelessWidget {
  const _ActionMemberTile(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(icon,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 5),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}

class _DangerAction extends StatelessWidget {
  const _DangerAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: onTap != null,
          leading: Icon(icon, color: Theme.of(context).colorScheme.error),
          title: Text(label,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: onTap,
        ),
      );
}

class _ConversationTextDialog extends StatefulWidget {
  const _ConversationTextDialog({
    required this.title,
    required this.initialValue,
    required this.maxLength,
    required this.maxLines,
    this.hintText,
  });

  final String title;
  final String initialValue;
  final int maxLength;
  final int maxLines;
  final String? hintText;

  @override
  State<_ConversationTextDialog> createState() =>
      _ConversationTextDialogState();
}

class _ConversationTextDialogState extends State<_ConversationTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: widget.maxLength,
            maxLines: widget.maxLines,
            decoration: InputDecoration(hintText: widget.hintText)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('保存')),
        ],
      );
}
