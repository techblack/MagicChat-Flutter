import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/realtime_store.dart';
import '../../data/repository.dart';
import '../../data/contact_cache_store.dart';
import '../../data/message_cache_store.dart';
import '../../domain/models.dart';
import 'contact_alphabet_index.dart';
import 'contact_category_page.dart';
import 'contact_directory_home_header.dart';
import 'contact_directory_model.dart';
import 'contact_directory_tile.dart';
import 'entity_details_page.dart';
import 'friend_management_dialog.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage(
      {required this.repository,
      this.realtimeStore,
      this.serverUrl,
      this.cacheScope,
      this.initialContactId,
      this.onInitialContactOpened,
      this.onOpenConversation,
      super.key});

  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final String? initialContactId;
  final VoidCallback? onInitialContactOpened;
  final ValueChanged<String>? onOpenConversation;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _contactCacheStore = ContactCacheStore();
  Future<ContactDirectory>? _directoryFuture;
  String? _openedInitialContactId;
  String _currentUserId = '';
  String? _activeIndexLabel;
  Timer? _searchDebounce;
  Timer? _indexLabelTimer;

  @override
  void initState() {
    super.initState();
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    _currentUserId = widget.realtimeStore?.currentUserId ?? '';
    unawaited(_primeCachedContacts());
    if (_currentUserId.isEmpty) unawaited(_loadCurrentUser());
    _load();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await widget.repository.currentUser();
      if (mounted) setState(() => _currentUserId = user.id);
    } catch (_) {
      // 通讯录仍可展示；仅“我的应用”分类暂时为空。
    }
  }

  Future<void> _primeCachedContacts() async {
    final cached = await _contactCacheStore.read(widget.cacheScope);
    if (!mounted) return;
    for (final contact in cached) {
      widget.realtimeStore?.contacts[contact.id] = contact;
    }
  }

  void _onRealtimeChanged() {
    if (!mounted) return;
    final currentUserId = widget.realtimeStore?.currentUserId;
    setState(() {
      if (currentUserId?.isNotEmpty == true) _currentUserId = currentUserId!;
    });
  }

  void _load({bool cancelPendingSearch = true}) {
    if (!mounted) return;
    if (cancelPendingSearch) _searchDebounce?.cancel();
    setState(() {
      _directoryFuture = _loadDirectory();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (mounted) setState(() {});
    _scrollToTop();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchDebounce = null;
      _load(cancelPendingSearch: false);
    });
  }

  Future<void> _refresh() async {
    _searchDebounce?.cancel();
    final future = _loadDirectory();
    setState(() {
      _directoryFuture = future;
    });
    await future;
  }

  void _openInitialContact(ContactDirectory directory) {
    final id = widget.initialContactId;
    if (id == null || id.isEmpty || id == _openedInitialContactId) return;
    Contact? contact;
    for (final item in directory.contacts) {
      if (item.id == id) {
        contact = item;
        break;
      }
    }
    if (contact == null) return;
    final target = contact;
    _openedInitialContactId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_openContactDetails(target).whenComplete(() {
          widget.onInitialContactOpened?.call();
        }));
      }
    });
  }

  @override
  void didUpdateWidget(covariant ContactsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialContactId == null) _openedInitialContactId = null;
    if (oldWidget.initialContactId != widget.initialContactId &&
        _directoryFuture != null) {
      unawaited(_directoryFuture!.then(_openInitialContact));
    }
  }

  Future<ContactDirectory> _loadDirectory() async {
    final directory = await widget.repository
        .contactDirectory(keyword: _searchController.text.trim());
    await _contactCacheStore.write(widget.cacheScope, directory.contacts);
    return directory;
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _searchDebounce?.cancel();
    _indexLabelTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ContactDirectory>(
        future: _directoryFuture,
        builder: (context, snapshot) {
          final directory = snapshot.data;
          if (directory != null) _openInitialContact(directory);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: '搜索联系人、应用或群组',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _searchController.clear();
                            _scrollToTop();
                            _load();
                          },
                          icon: const Icon(Icons.clear)),
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
    final directory = snapshot.data!;
    final contacts = directory.contacts;
    final keyword = _searchController.text.trim();
    if (keyword.isNotEmpty) return _buildSearchResults(contacts);
    return _buildHomeDirectory(directory, contacts);
  }

  Widget _buildSearchResults(List<Contact> contacts) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: contacts.isEmpty ? 1 : contacts.length,
        itemBuilder: (context, index) {
          if (contacts.isEmpty) {
            return const SizedBox(
                height: 220, child: Center(child: Text('未找到匹配的联系人')));
          }
          final raw = contacts[index];
          final contact = _liveContact(raw);
          return _contactTile(contact);
        },
      ),
    );
  }

  Widget _buildHomeDirectory(
      ContactDirectory directory, List<Contact> contacts) {
    final sections = buildContactSections(contacts.map(_liveContact));
    final users = sections.expand((section) => section.contacts).toList();
    final entries = <ContactDirectoryHomeEntry>[
      if (directory.supportsFriendManagement)
        const ContactDirectoryHomeEntry(
            category: ContactDirectoryCategory.newFriends, count: 0),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.myApps,
          count: contactsForCategory(
                  ContactDirectoryCategory.myApps, contacts, _currentUserId)
              .length),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.allApps,
          count: contactsForCategory(
                  ContactDirectoryCategory.allApps, contacts, _currentUserId)
              .length),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.joinedGroups,
          count: contactsForCategory(ContactDirectoryCategory.joinedGroups,
                  contacts, _currentUserId)
              .length),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.publicGroups,
          count: contactsForCategory(ContactDirectoryCategory.publicGroups,
                  contacts, _currentUserId)
              .length),
    ];
    return Stack(children: [
      RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            ContactDirectoryHomeHeader(
                entries: entries,
                onPressed: (category) =>
                    _openCategory(category, directory, contacts)),
            const SizedBox(height: 8),
            if (sections.isEmpty)
              const SizedBox(height: 180, child: Center(child: Text('暂无联系人')))
            else
              for (final section in sections) ...[
                SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(section.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ),
                ),
                for (final contact in section.contacts)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _contactTile(contact),
                  ),
              ],
            if (users.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text('共 ${users.length} 位联系人',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
      if (sections.isNotEmpty)
        Positioned(
          top: 12,
          right: 0,
          bottom: 12,
          width: 26,
          child: ContactAlphabetIndex(
              onSelected: (label) =>
                  _scrollToSection(label, sections, entries.length)),
        ),
      if (_activeIndexLabel != null)
        Center(
          child: IgnorePointer(
            child: Container(
              key: const ValueKey('contact-index-indicator'),
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .inverseSurface
                      .withValues(alpha: .88),
                  borderRadius: BorderRadius.circular(16)),
              child: Text(_activeIndexLabel!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
    ]);
  }

  Contact _liveContact(Contact contact) {
    final value = widget.realtimeStore?.contacts[contact.id] ?? contact;
    widget.realtimeStore?.contacts[value.id] = value;
    return value;
  }

  Widget _contactTile(Contact contact) => ContactDirectoryTile(
        repository: widget.repository,
        contact: contact,
        serverUrl: widget.serverUrl,
        cacheScope: widget.cacheScope,
        onTap: () => _openContactDetails(contact),
      );

  void _scrollToSection(
      String label, List<ContactDirectorySection> sections, int categoryCount) {
    final requested = contactIndexLabels.indexOf(label);
    final target = sections.where((section) {
          return contactIndexLabels.indexOf(section.label) >= requested;
        }).firstOrNull ??
        sections.last;
    var targetOffset =
        20.0 + categoryCount * 64 + (categoryCount > 0 ? categoryCount - 1 : 0);
    for (final section in sections) {
      if (section.label == target.label) break;
      targetOffset += 32 + section.contacts.length * 64;
    }
    if (_scrollController.hasClients) {
      final offset = targetOffset
          .clamp(0.0, _scrollController.position.maxScrollExtent)
          .toDouble();
      _scrollController.jumpTo(offset);
    }
    _indexLabelTimer?.cancel();
    setState(() => _activeIndexLabel = target.label);
    _indexLabelTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _activeIndexLabel = null);
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _openContactDetails(Contact contact) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => EntityDetailsPage(
            repository: widget.repository,
            contact: contact,
            serverUrl: widget.serverUrl,
            cacheScope: widget.cacheScope,
            onOpenConversation: widget.onOpenConversation,
          ),
        ),
      );

  Future<void> _openCategory(ContactDirectoryCategory category,
      ContactDirectory directory, List<Contact> contacts) async {
    if (category == ContactDirectoryCategory.newFriends) {
      await _showFriendManagement(directory);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactCategoryPage(
          repository: widget.repository,
          category: category,
          initialContacts: contacts,
          currentUserId: _currentUserId,
          serverUrl: widget.serverUrl,
          cacheScope: widget.cacheScope,
          onOpenConversation: widget.onOpenConversation,
        ),
      ),
    );
    if (mounted) _load();
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
