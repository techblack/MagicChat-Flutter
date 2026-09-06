import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/realtime_store.dart';
import '../../data/realtime.dart';
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
      this.realtimeSession,
      this.realtimeStore,
      this.serverUrl,
      this.cacheScope,
      this.initialContactId,
      this.onInitialContactOpened,
      this.onOpenConversation,
      super.key});

  final MagicChatRepository repository;
  final RealtimeSession? realtimeSession;
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
  final _selectedContactIds = <String>{};
  ContactDirectory? _sectionSource;
  List<ContactDirectorySection> _cachedSections = const [];
  Timer? _fallbackPollTimer;
  bool _fallbackPollInFlight = false;

  @override
  void initState() {
    super.initState();
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    if (widget.realtimeSession != null) {
      _fallbackPollTimer = Timer.periodic(
          const Duration(minutes: 1), (_) => unawaited(_pollFallback()));
    }
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
    // 联系人资料缓存不应阻塞首屏。组织通讯录可能包含数千人，等待
    // SharedPreferences 序列化会让网络请求完成后仍卡住页面布局。
    unawaited(_writeContactCache(directory.contacts));
    return directory;
  }

  Future<void> _writeContactCache(Iterable<Contact> contacts) async {
    try {
      await _contactCacheStore.write(widget.cacheScope, contacts);
    } catch (_) {
      // 缓存失败不影响通讯录展示。
    }
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _searchDebounce?.cancel();
    _indexLabelTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pollFallback() async {
    final session = widget.realtimeSession;
    if (!mounted ||
        session == null ||
        session.ready ||
        _fallbackPollInFlight ||
        _searchController.text.trim().isNotEmpty) return;
    _fallbackPollInFlight = true;
    try {
      await _refresh();
    } catch (_) {
      // 下一周期继续尝试，缓存和当前目录保持可用。
    } finally {
      _fallbackPollInFlight = false;
    }
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
            if (_selectedContactIds.isNotEmpty) _buildSelectionBar(),
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

  Widget _buildSelectionBar() {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: IconButton(
            tooltip: '取消选择',
            onPressed: () => setState(_selectedContactIds.clear),
            icon: const Icon(Icons.close)),
        title: Text('已选择 ${_selectedContactIds.length} 位联系人'),
        trailing: FilledButton.icon(
          onPressed: () => _createGroupFromSelection(),
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('组建群聊'),
        ),
      ),
    );
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
    // realtimeStore 的在线状态变化会触发本页重绘。分组和拼音排序只依赖
    // 服务端目录快照，复用它可避免每次状态事件都扫描/排序数千个联系人。
    if (!identical(_sectionSource, directory)) {
      _sectionSource = directory;
      _cachedSections = buildContactSections(contacts);
    }
    final sections = _cachedSections;
    final userCount = sections.fold<int>(
        0, (count, section) => count + section.contacts.length);
    var myApps = 0;
    var allApps = 0;
    var joinedGroups = 0;
    var publicGroups = 0;
    final normalizedUserId = _currentUserId.trim().toLowerCase();
    for (final contact in contacts) {
      if (contact.type == 'app') {
        allApps++;
        if (normalizedUserId.isNotEmpty &&
            contact.creatorUserId?.trim().toLowerCase() == normalizedUserId) {
          myApps++;
        }
      } else if (contact.type == 'group') {
        if (contact.joined) joinedGroups++;
        if (contact.visibility == 'public') publicGroups++;
      }
    }
    final entries = <ContactDirectoryHomeEntry>[
      if (directory.supportsFriendManagement)
        const ContactDirectoryHomeEntry(
            category: ContactDirectoryCategory.newFriends, count: 0),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.myApps, count: myApps),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.allApps, count: allApps),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.joinedGroups, count: joinedGroups),
      ContactDirectoryHomeEntry(
          category: ContactDirectoryCategory.publicGroups, count: publicGroups),
    ];
    final rows = <_ContactDirectoryRow>[
      const _ContactDirectoryRow.header(),
      const _ContactDirectoryRow.spacer(),
    ];
    if (sections.isEmpty) {
      rows.add(const _ContactDirectoryRow.empty());
    }
    for (final section in sections) {
      rows.add(_ContactDirectoryRow.section(section.label));
      rows.addAll(section.contacts
          .map((contact) => _ContactDirectoryRow.contact(contact)));
    }
    if (userCount > 0) {
      rows.add(_ContactDirectoryRow.footer(userCount));
    }
    return Stack(children: [
      RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return switch (row.kind) {
              _ContactDirectoryRowKind.header => ContactDirectoryHomeHeader(
                  entries: entries,
                  onPressed: (category) =>
                      _openCategory(category, directory, contacts)),
              _ContactDirectoryRowKind.spacer => const SizedBox(height: 8),
              _ContactDirectoryRowKind.empty => const SizedBox(
                  height: 180, child: Center(child: Text('暂无联系人'))),
              _ContactDirectoryRowKind.section => SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(row.label!,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ),
                ),
              _ContactDirectoryRowKind.contact => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _contactTile(_liveContact(row.contact!)),
                ),
              _ContactDirectoryRowKind.footer => Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('共 ${row.count} 位联系人',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
            };
          },
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

  Widget _contactTile(Contact contact) {
    final selectable = contact.type == 'user';
    final selected = _selectedContactIds.contains(contact.id);
    return ContactDirectoryTile(
        repository: widget.repository,
        contact: contact,
        serverUrl: widget.serverUrl,
        cacheScope: widget.cacheScope,
        selected: selected,
        onLongPress: selectable ? () => _toggleContact(contact) : null,
        onTap: () {
          if (_selectedContactIds.isNotEmpty && selectable) {
            _toggleContact(contact);
          } else {
            _openContactDetails(contact);
          }
        });
  }

  void _toggleContact(Contact contact) {
    if (contact.type != 'user') return;
    setState(() {
      if (!_selectedContactIds.remove(contact.id)) {
        _selectedContactIds.add(contact.id);
      }
    });
  }

  Future<void> _createGroupFromSelection() async {
    final memberIds = _selectedContactIds.toList(growable: false);
    if (memberIds.isEmpty) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _GroupNameDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final conversation = await widget.repository
          .createGroupConversation(name.trim(), memberIds: memberIds);
      if (!mounted) return;
      setState(_selectedContactIds.clear);
      widget.onOpenConversation?.call(conversation.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建群聊失败：$error')));
      }
    }
  }

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

enum _ContactDirectoryRowKind {
  header,
  spacer,
  empty,
  section,
  contact,
  footer
}

class _ContactDirectoryRow {
  const _ContactDirectoryRow._(this.kind,
      {this.label, this.contact, this.count});
  const _ContactDirectoryRow.header() : this._(_ContactDirectoryRowKind.header);
  const _ContactDirectoryRow.spacer() : this._(_ContactDirectoryRowKind.spacer);
  const _ContactDirectoryRow.empty() : this._(_ContactDirectoryRowKind.empty);
  const _ContactDirectoryRow.section(String value)
      : this._(_ContactDirectoryRowKind.section, label: value);
  const _ContactDirectoryRow.contact(Contact value)
      : this._(_ContactDirectoryRowKind.contact, contact: value);
  const _ContactDirectoryRow.footer(int value)
      : this._(_ContactDirectoryRowKind.footer, count: value);

  final _ContactDirectoryRowKind kind;
  final String? label;
  final Contact? contact;
  final int? count;
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog();

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('组建群聊'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '群聊名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, value.text.trim()),
                  child: const Text('创建'))),
        ],
      );
}
