import 'package:flutter/material.dart';

import '../../data/contact_directory_realtime_sync.dart';
import '../../data/realtime_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/user_facing_error.dart';

class FriendManagementDialog extends StatefulWidget {
  const FriendManagementDialog(
      {required this.repository,
      required this.friends,
      this.realtimeStore,
      super.key});

  final MagicChatRepository repository;
  final List<Contact> friends;
  final RealtimeStore? realtimeStore;

  @override
  State<FriendManagementDialog> createState() => _FriendManagementDialogState();
}

class _FriendManagementDialogState extends State<FriendManagementDialog> {
  final _queryController = TextEditingController();
  late Future<_FriendManagementData> _dataFuture;
  late List<Contact> _friends;
  late final ContactDirectoryRefreshScheduler _realtimeRefreshScheduler;
  int _observedFriendDataRevision = 0;
  _FriendManagementData? _realtimeData;
  List<Contact> _searchResults = const [];
  bool _searching = false;
  String _updatingKey = '';

  @override
  void initState() {
    super.initState();
    _friends = List.of(widget.friends);
    _dataFuture = _loadData();
    _observedFriendDataRevision = widget.realtimeStore?.friendDataRevision ?? 0;
    _realtimeRefreshScheduler =
        ContactDirectoryRefreshScheduler(_refreshFromRealtime);
    widget.realtimeStore?.addListener(_onRealtimeChanged);
  }

  @override
  void didUpdateWidget(covariant FriendManagementDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeStore != widget.realtimeStore) {
      oldWidget.realtimeStore?.removeListener(_onRealtimeChanged);
      _observedFriendDataRevision =
          widget.realtimeStore?.friendDataRevision ?? 0;
      widget.realtimeStore?.addListener(_onRealtimeChanged);
    }
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _realtimeRefreshScheduler.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onRealtimeChanged() {
    final store = widget.realtimeStore;
    if (!mounted ||
        store == null ||
        store.friendDataRevision == _observedFriendDataRevision) {
      return;
    }
    _observedFriendDataRevision = store.friendDataRevision;
    final intent = store.lastFriendDataRefreshIntent;
    if (intent != null) {
      _realtimeRefreshScheduler.request(intent);
    }
  }

  Future<void> _refreshFromRealtime(FriendDataRefreshIntent intent) async {
    final results = await Future.wait([
      _loadData(),
      if (intent == FriendDataRefreshIntent.directory)
        widget.repository.contactDirectory(),
    ]);
    if (!mounted) {
      return;
    }
    final data = results[0] as _FriendManagementData;
    if (intent == FriendDataRefreshIntent.directory) {
      final directory = results[1] as ContactDirectory;
      if (!directory.supportsFriendManagement) {
        Navigator.pop(context);
        return;
      }
      _friends = directory.contacts
          .where((contact) => contact.type == 'user')
          .toList(growable: false);
    }
    setState(() => _realtimeData = data);
  }

  Future<_FriendManagementData> _loadData() async {
    final requests = await Future.wait([
      widget.repository.friendRequests(),
      widget.repository.friendRequests(direction: 'outgoing'),
    ]);
    final incoming = requests[0];
    final outgoing = requests[1];
    final userIds = <String>{
      ...incoming.map((request) => request.userId),
      ...outgoing.map((request) => request.userId),
    };
    final users = await widget.repository.resolveUsers(userIds.toList());
    return _FriendManagementData(
        incoming: incoming,
        outgoing: outgoing,
        users: {for (final user in users) user.id: user});
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final results = await widget.repository.searchUsers(query);
      if (mounted) setState(() => _searchResults = results);
    } catch (error) {
      if (mounted) _showMessage('查找用户失败：${userFacingError(error)}');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _run(
      String key, Future<void> Function() action, String success) async {
    if (_updatingKey.isNotEmpty) return;
    setState(() => _updatingKey = key);
    try {
      await action();
      if (!mounted) return;
      _showMessage(success);
      setState(() {
        _realtimeData = null;
        _dataFuture = _loadData();
      });
    } catch (error) {
      if (mounted) _showMessage('好友操作失败：${userFacingError(error)}');
    } finally {
      if (mounted) setState(() => _updatingKey = '');
    }
  }

  Future<void> _deleteFriend(Contact friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友“${friend.displayName}”吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run('delete:${friend.id}',
        () => widget.repository.deleteFriend(friend.id), '已删除好友');
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text('新朋友', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('friend-search-field'),
                controller: _queryController,
                enabled: !_searching,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: '完整邮箱、手机号或用户 ID',
                  prefixIcon: const Icon(Icons.person_search_outlined),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          tooltip: '查找',
                          onPressed: _search,
                          icon: const Icon(Icons.search)),
                ),
              ),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 12),
                FutureBuilder<_FriendManagementData>(
                    future: _dataFuture,
                    builder: (context, snapshot) => Column(
                        children: _searchResults
                            .map((user) => _searchResultTile(
                                user, _realtimeData ?? snapshot.data))
                            .toList())),
              ],
              if (_friends.isNotEmpty) ...[
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('我的好友',
                        style: Theme.of(context).textTheme.titleMedium)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final friend = _friends[index];
                      return _FriendTile(
                        user: friend,
                        subtitle: friend.email.isEmpty ? '未提供邮箱' : friend.email,
                        trailing: TextButton(
                          key: ValueKey('delete-friend-${friend.id}'),
                          onPressed: _updatingKey.isEmpty
                              ? () => _deleteFriend(friend)
                              : null,
                          child: const Text('删除'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('好友申请',
                      style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<_FriendManagementData>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    final data = _realtimeData ?? snapshot.data;
                    if (snapshot.hasError && data == null) {
                      return Center(
                          child: TextButton.icon(
                              onPressed: () => setState(() {
                                    _realtimeData = null;
                                    _dataFuture = _loadData();
                                  }),
                              icon: const Icon(Icons.refresh),
                              label: const Text('加载失败，点击重试')));
                    }
                    if (data == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final requests = [
                      ...data.incoming
                          .map((request) => _FriendRequestEntry(request, true)),
                      ...data.outgoing.map(
                          (request) => _FriendRequestEntry(request, false)),
                    ];
                    if (requests.isEmpty) {
                      return const _EmptyFriendRequests();
                    }
                    return ListView.separated(
                        shrinkWrap: true,
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final entry = requests[index];
                          return _requestTile(
                              entry, data.users[entry.request.userId]);
                        });
                  },
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _searchResultTile(Contact user, _FriendManagementData? data) {
    final friendIds = _friends.map((friend) => friend.id).toSet();
    final pendingIds = <String>{
      ...?data?.incoming
          .where((request) => request.status == 'pending')
          .map((request) => request.userId),
      ...?data?.outgoing
          .where((request) => request.status == 'pending')
          .map((request) => request.userId),
    };
    final isFriend = friendIds.contains(user.id);
    final isPending = pendingIds.contains(user.id);
    final disabled = isFriend || isPending || _updatingKey.isNotEmpty;
    return _FriendTile(
      user: user,
      subtitle: user.email.isEmpty ? '未提供邮箱' : user.email,
      trailing: FilledButton.tonalIcon(
          onPressed: disabled
              ? null
              : () => _run(
                  'add:${user.id}',
                  () => widget.repository.createFriendRequest(user.id),
                  '好友申请已发送'),
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: Text(isFriend
              ? '已是好友'
              : isPending
                  ? '申请处理中'
                  : '添加好友')),
    );
  }

  Widget _requestTile(_FriendRequestEntry entry, Contact? user) {
    final request = entry.request;
    final pending = request.status == 'pending';
    Widget trailing;
    if (!pending) {
      trailing = Text(_requestStatus(request.status));
    } else if (entry.incoming) {
      trailing = Wrap(spacing: 4, children: [
        TextButton(
            onPressed: _updatingKey.isEmpty
                ? () => _run(
                    request.id,
                    () => widget.repository.acceptFriendRequest(request.id),
                    '已添加好友')
                : null,
            child: const Text('接受')),
        TextButton(
            onPressed: _updatingKey.isEmpty
                ? () => _run(
                    request.id,
                    () => widget.repository.rejectFriendRequest(request.id),
                    '已拒绝好友申请')
                : null,
            child: const Text('拒绝')),
      ]);
    } else {
      trailing = TextButton(
          onPressed: _updatingKey.isEmpty
              ? () => _run(
                  request.id,
                  () => widget.repository.cancelFriendRequest(request.id),
                  '好友申请已取消')
              : null,
          child: const Text('取消申请'));
    }
    return _FriendTile(
        key: ValueKey('friend-request-${request.id}'),
        // 好友资料暂时不可用时也不要把内部用户 ID 直接展示给用户。
        user: user ?? Contact(id: request.userId, name: '成员'),
        subtitle: entry.incoming ? '请求添加你为好友' : '你发出了好友申请',
        trailing: trailing);
  }

  String _requestStatus(String status) => switch (status) {
        'accepted' => '已通过',
        'rejected' => '已拒绝',
        'canceled' => '已取消',
        _ => '等待处理',
      };
}

class _FriendManagementData {
  const _FriendManagementData(
      {required this.incoming, required this.outgoing, required this.users});

  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;
  final Map<String, Contact> users;
}

class _FriendRequestEntry {
  const _FriendRequestEntry(this.request, this.incoming);
  final FriendRequest request;
  final bool incoming;
}

class _FriendTile extends StatelessWidget {
  const _FriendTile(
      {required this.user,
      required this.subtitle,
      required this.trailing,
      super.key});

  final Contact user;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: ListTile(
          leading: CircleAvatar(
              child: Text(user.displayName.isEmpty
                  ? '?'
                  : user.displayName.substring(0, 1))),
          title: Text(user.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing,
        ),
      );
}

class _EmptyFriendRequests extends StatelessWidget {
  const _EmptyFriendRequests();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline, size: 36),
            SizedBox(height: 8),
            Text('暂无好友申请'),
          ]),
        ),
      );
}
