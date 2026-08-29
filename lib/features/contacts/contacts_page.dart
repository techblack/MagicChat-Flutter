import 'package:flutter/material.dart';

import '../../data/realtime_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import 'applications_page.dart';
import 'friend_management_dialog.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage(
      {required this.repository,
      this.realtimeStore,
      this.serverUrl,
      this.onOpenConversation,
      super.key});

  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final String? serverUrl;
  final ValueChanged<String>? onOpenConversation;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _searchController = TextEditingController();
  Future<ContactDirectory>? _directoryFuture;

  @override
  void initState() {
    super.initState();
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    _load();
  }

  void _onRealtimeChanged() {
    if (mounted) setState(() {});
  }

  void _load() {
    setState(() {
      _directoryFuture = widget.repository
          .contactDirectory(keyword: _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ContactDirectory>(
        future: _directoryFuture,
        builder: (context, snapshot) {
          final directory = snapshot.data;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: '搜索联系人、应用或群组',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (directory?.supportsFriendManagement == true)
                      IconButton(
                          key: const ValueKey('friend-management-button'),
                          tooltip: '新朋友',
                          onPressed: () => _showFriendManagement(directory!),
                          icon: const Icon(Icons.person_add_alt_1_outlined)),
                    IconButton(
                        key: const ValueKey('app-management-button'),
                        tooltip: '我的应用',
                        onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ApplicationsPage(
                                    repository: widget.repository,
                                    serverUrl: widget.serverUrl))),
                        icon: const Icon(Icons.smart_toy_outlined)),
                    IconButton(
                        tooltip: '刷新',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh)),
                  ]),
                ),
              ),
            ),
            Expanded(child: _buildDirectory(snapshot)),
          ]);
        },
      );

  Widget _buildDirectory(AsyncSnapshot<ContactDirectory> snapshot) {
    if (snapshot.hasError) {
      return Center(
          child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('通讯录加载失败，点击重试')));
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final contacts = snapshot.data!.contacts;
    if (contacts.isEmpty) {
      return const Center(child: Text('暂无联系人'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final raw = contacts[index];
        final contact = widget.realtimeStore?.contacts[raw.id] ?? raw;
        widget.realtimeStore?.contacts[contact.id] = contact;
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(
              radius: 22,
              backgroundColor: contact.type == 'app'
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Text(contact.displayName.isEmpty
                  ? '?'
                  : contact.displayName.substring(0, 1))),
          title: Text(contact.displayName),
          subtitle: Text(
              contact.type == 'group'
                  ? '${contact.memberCount} 人 · ${contact.joined ? '已加入' : contact.visibility == 'public' ? '公开群组' : '群组'}'
                  : contact.online
                      ? '在线'
                      : '离线',
              style: TextStyle(
                  color: contact.type == 'group'
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : contact.online
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant)),
          trailing: contact.type == 'group'
              ? Icon(contact.joined
                  ? Icons.check_circle_outline
                  : Icons.public_outlined)
              : Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: contact.online
                          ? Colors.green
                          : Theme.of(context).colorScheme.outlineVariant,
                      shape: BoxShape.circle)),
          onTap: () => _openConversation(contact),
        );
      },
    );
  }

  Future<void> _openConversation(Contact contact) async {
    try {
      final conversation = contact.type == 'app'
          ? await widget.repository.createAppConversation(contact.id)
          : contact.type == 'user'
              ? await widget.repository.createDirectConversation(contact.id)
              : contact.joined
                  ? ChatConversation(id: contact.id, title: contact.name)
                  : await widget.repository.joinGroupConversation(contact.id);
      if (mounted) widget.onOpenConversation?.call(conversation.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开会话：$error')));
      }
    }
  }

  Future<void> _showFriendManagement(ContactDirectory directory) async {
    await showDialog<void>(
        context: context,
        builder: (_) => FriendManagementDialog(
            repository: widget.repository,
            friends: directory.contacts
                .where((contact) => contact.type == 'user')
                .toList()));
    if (mounted) _load();
  }
}
