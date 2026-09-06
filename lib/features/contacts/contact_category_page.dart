import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import 'applications_page.dart';
import 'contact_directory_model.dart';
import 'contact_directory_tile.dart';
import 'entity_details_page.dart';
import '../shared/user_facing_error.dart';

class ContactCategoryPage extends StatefulWidget {
  const ContactCategoryPage({
    required this.repository,
    required this.category,
    required this.initialContacts,
    required this.currentUserId,
    this.serverUrl,
    this.cacheScope,
    this.onOpenConversation,
    super.key,
  });

  final MagicChatRepository repository;
  final ContactDirectoryCategory category;
  final List<Contact> initialContacts;
  final String currentUserId;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final ValueChanged<String>? onOpenConversation;

  @override
  State<ContactCategoryPage> createState() => _ContactCategoryPageState();
}

class _ContactCategoryPageState extends State<ContactCategoryPage> {
  late List<Contact> _contacts = widget.initialContacts;
  bool _refreshing = false;

  List<Contact> get _visible =>
      contactsForCategory(widget.category, _contacts, widget.currentUserId);

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final directory = await widget.repository.contactDirectory();
      if (mounted) setState(() => _contacts = directory.contacts);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('通讯录刷新失败：${userFacingError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _manageApps() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicationsPage(
          repository: widget.repository,
          serverUrl: widget.serverUrl,
          cacheScope: widget.cacheScope,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openDetails(Contact contact) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => EntityDetailsPage(
            repository: widget.repository,
            contact: contact,
            serverUrl: widget.serverUrl,
            cacheScope: widget.cacheScope,
            onOpenConversation: (id) {
              Navigator.pop(context);
              widget.onOpenConversation?.call(id);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final contacts = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.label),
        actions: [
          if (widget.category == ContactDirectoryCategory.myApps)
            IconButton(
                tooltip: '管理应用',
                onPressed: _manageApps,
                icon: const Icon(Icons.settings_outlined)),
          IconButton(
              tooltip: '刷新',
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: contacts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 320,
                    child: Center(child: Text('暂无${widget.category.label}')),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                itemCount: contacts.length + 1,
                itemBuilder: (context, index) => index == contacts.length
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text('共 ${contacts.length} 个',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      )
                    : ContactDirectoryTile(
                        repository: widget.repository,
                        contact: contacts[index],
                        serverUrl: widget.serverUrl,
                        cacheScope: widget.cacheScope,
                        onTap: () => _openDetails(contacts[index]),
                      ),
              ),
      ),
    );
  }
}
