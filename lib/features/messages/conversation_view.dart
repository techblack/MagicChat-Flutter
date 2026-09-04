part of '../../main.dart';

class ConversationView extends StatefulWidget {
  const ConversationView(
      {required this.repository,
      this.realtimeStore,
      this.cacheScope,
      required this.conversationId,
      this.focusMessageId,
      this.focusMessageSequence,
      this.onOpenConversation,
      this.onOpenInternalLink,
      this.onMessageFocused,
      super.key});
  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final MessageCacheScope? cacheScope;
  final String? conversationId;
  final String? focusMessageId;
  final int? focusMessageSequence;
  final ValueChanged<String>? onOpenConversation;
  final ValueChanged<String>? onOpenInternalLink;
  final VoidCallback? onMessageFocused;
  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  static const _maxSelectedMessages = 50;
  static const _maxForwardTargets = 20;
  static const _forwardableMessageTypes = {
    'text',
    'markdown',
    'link',
    'card',
    'chart',
    'file',
    'image',
    'voice',
    'forward_bundle',
  };

  final _controller = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _voiceRecorder = VoiceRecorder();
  Future<List<ChatMessage>>? _messagesFuture;
  MessagePage? _messagePage;
  final _messageCacheStore = MessageCacheStore();
  bool _sendingMessage = false;
  bool _sendingFile = false;
  bool _recording = false;
  Future<List<Contact>>? _contactsFuture;
  final _olderMessages = <ChatMessage>[];
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;
  int? _lastOlderBeforeSeq;
  int _lastReadSequence = 0;
  bool _readInFlight = false;
  int? _pendingReadSequence;
  Timer? _readRetryTimer;
  String? _positioningConversationId;
  String? _positionedConversationId;
  int _positionGeneration = 0;
  bool _initialPositionPending = true;
  bool _userScrolledDuringInitialPosition = false;
  final _selectedMessageIds = <String>{};
  List<ChatMessage> _visibleMessages = const [];
  final _contactCacheStore = ContactCacheStore();
  MessageReply? _replyTo;
  ChatConversation? _conversation;
  TopicDetail? _topicDetail;
  bool _canSend = true;
  final _messageKeys = <String, GlobalKey>{};
  int _pendingNewMessageCount = 0;
  final _seenRealtimeMessageIds = <String>{};
  String? _focusedMessageId;
  String? _highlightedMessageId;
  bool _historyMode = false;
  Timer? _highlightTimer;

  bool get _topicArchived =>
      _conversation?.topic?.archived == true ||
      (_conversation == null &&
          _topicDetail?.conversation.topic?.archived == true);

  bool _conversationCanSend(String conversationId) {
    if (widget.conversationId != conversationId || _topicArchived) return false;
    final current = widget.realtimeStore?.conversations[conversationId];
    return _canSend &&
        current?.canSend != false &&
        current?.topic?.archived != true;
  }

  bool _topicIsOpen(String conversationId) {
    if (widget.conversationId != conversationId) return false;
    return !_topicArchived &&
        widget.realtimeStore?.conversations[conversationId]?.topic?.archived !=
            true;
  }

  bool get _isTopicConversation =>
      _conversation?.type == 'topic' ||
      _topicDetail?.conversation.type == 'topic';

  /// 返回当前消息实际所属的会话类型。
  ///
  /// 话题消息本身的类型是 `topic`，需要沿用其父会话类型来决定头像
  /// 点击行为（群聊进入私聊，私聊显示资料面板）。
  String? get _conversationKind {
    final conversation = _conversation ??
        (widget.conversationId == null
            ? null
            : widget.realtimeStore?.conversations[widget.conversationId]);
    if (conversation == null) return null;
    if (conversation.type != 'topic') return conversation.type;
    return conversation.topic?.parentConversationType ??
        _topicDetail?.conversation.topic?.parentConversationType;
  }

  bool get _isGroupConversation => _conversationKind == 'group';

  bool _canForwardOrSelect(ChatMessage message) =>
      _forwardableMessageTypes.contains(message.contentType);

  bool _hasMessageActions(ChatMessage message) =>
      message.contentType != 'revoked' &&
      message.contentType != 'unsupported' &&
      message.contentType != 'system_event';

  @override
  void initState() {
    super.initState();
    _historyMode = widget.focusMessageId != null;
    _messagesFuture = _loadMessages();
    _contactsFuture = _loadConversationContacts();
    _seenRealtimeMessageIds.addAll(_realtimeConversationMessages());
    _scrollController.addListener(_onScroll);
    _controller.addListener(_persistDraft);
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    _readRetryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final id = widget.conversationId;
      if (id != null && !_historyMode) _requestLatestRead(id);
    });
    unawaited(_restoreDraft());
  }

  Iterable<String> _realtimeConversationMessages() {
    final id = widget.conversationId;
    if (id == null) return const <String>[];
    return widget.realtimeStore?.messages.values
            .where((message) => message.conversationId == id)
            .map((message) => message.id) ??
        const <String>[];
  }

  String? get _draftKey => widget.conversationId == null
      ? null
      : 'magicchat.conversation.${widget.conversationId}.draft';

  Future<void> _restoreDraft() async {
    final key = _draftKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(key);
    if (draft != null && mounted && _controller.text.isEmpty) {
      _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length));
    }
  }

  void _persistDraft() {
    final key = _draftKey;
    if (key == null) return;
    unawaited(SharedPreferences.getInstance().then((prefs) async {
      final draft = _controller.text;
      if (draft.trim().isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, draft);
      }
    }));
  }

  Future<List<Contact>> _loadConversationContacts() async {
    final cached = await _contactCacheStore.read(widget.cacheScope);
    if (cached.isNotEmpty) {
      unawaited(_refreshConversationContacts());
      return cached;
    }
    return _fetchConversationContacts();
  }

  Future<void> _refreshConversationContacts() async {
    final conversationId = widget.conversationId;
    try {
      final fresh = await _fetchConversationContacts();
      if (!mounted ||
          conversationId == null ||
          widget.conversationId != conversationId) {
        return;
      }
      final keepBottom =
          _positionedConversationId == conversationId && _isAtBottom();
      final offset = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;
      setState(() => _contactsFuture = Future.value(fresh));
      if (keepBottom) {
        _correctLatestPosition(conversationId,
            force: true, expectedOffset: offset);
      }
    } catch (_) {
      // 保留本地资料，网络刷新失败不影响消息显示。
    }
  }

  Future<List<Contact>> _fetchConversationContacts() async {
    final results = await Future.wait([
      widget.repository.contacts(),
      widget.repository.conversations(),
    ]);
    final contacts = <String, Contact>{
      for (final contact in results[0] as List<Contact>) contact.id: contact,
    };
    final id = widget.conversationId;
    if (id != null) {
      ChatConversation? selected;
      for (final conversation in results[1] as List<ChatConversation>) {
        if (conversation.id == id) {
          selected = conversation;
          for (final member in conversation.members) {
            final previous = contacts[member.id];
            contacts[member.id] = previous == null
                ? member
                : previous.copyWith(
                    name: member.name.trim().isNotEmpty ? member.name : null,
                    nickname: member.nickname.trim().isNotEmpty
                        ? member.nickname
                        : null,
                    avatar:
                        member.avatar.trim().isNotEmpty ? member.avatar : null,
                    email: member.email.trim().isNotEmpty ? member.email : null,
                    phone: member.phone.trim().isNotEmpty ? member.phone : null,
                    role: member.role,
                    type: member.type);
          }
          break;
        }
      }
      if (selected != null) {
        _applyConversation(selected);
      }
      if (selected == null || selected.type == 'topic') {
        unawaited(_loadTopicDetail(id));
      }
    }
    final memberUserIds = contacts.values
        .where((contact) => contact.type == 'user')
        .map((contact) => contact.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (memberUserIds.isNotEmpty) {
      try {
        final resolved = await widget.repository.resolveUsers(memberUserIds);
        for (final user in resolved) {
          final previous = contacts[user.id];
          contacts[user.id] = previous == null
              ? user
              : previous.copyWith(
                  name: user.name.isNotEmpty ? user.name : null,
                  nickname: user.nickname.isNotEmpty ? user.nickname : null,
                  avatar: user.avatar.isNotEmpty ? user.avatar : null,
                  email: user.email.isNotEmpty ? user.email : null,
                  phone: user.phone.isNotEmpty ? user.phone : null,
                  online: user.online);
        }
      } catch (_) {
        // 成员资料补全失败时仍保留消息接口返回的 ID/名称。
      }
    }
    await _contactCacheStore.write(widget.cacheScope, contacts.values);
    return contacts.values.toList();
  }

  void _applyConversation(ChatConversation conversation) {
    if (!mounted || widget.conversationId != conversation.id) return;
    widget.realtimeStore?.conversations[conversation.id] = conversation;
    setState(() {
      _conversation = conversation;
      _canSend = conversation.canSend;
    });
  }

  Future<void> _loadTopicDetail(String id) async {
    try {
      final detail = await widget.repository.topicDetail(id);
      if (!mounted || widget.conversationId != id) return;
      widget.realtimeStore?.conversations[id] = detail.conversation;
      setState(() {
        _topicDetail = detail;
        _conversation = detail.conversation;
        _canSend = detail.conversation.canSend;
      });
    } catch (_) {
      // 普通会话没有话题详情，忽略该请求；消息本身仍可正常加载。
    }
  }

  ChatMessage? _messageFromCache(Object? value) {
    if (value is! Map<String, dynamic> || value['id'] is! String) return null;
    final reactions = value['reactions'];
    final choice = value['choice'];
    final reply = value['reply_to'];
    final rawTopic = value['topic'];
    final authorId =
        value['author_id'] is String ? value['author_id'] as String : null;
    final cachedAuthor = '${value['author'] ?? ''}'.trim();
    return ChatMessage(
      id: value['id'] as String,
      author: cachedAuthor.isEmpty || cachedAuthor == '用户'
          ? authorId ?? '成员'
          : cachedAuthor,
      authorId: authorId,
      conversationId: value['conversation_id'] as String?,
      sequence: (value['sequence'] as num?)?.toInt(),
      contentType: '${value['content_type'] ?? 'text'}',
      rawBody: value['raw_body'] is Map
          ? Map<String, dynamic>.from(value['raw_body'] as Map)
          : const {},
      text: '${value['text'] ?? ''}',
      editableText: value['editable_text'] is String
          ? value['editable_text'] as String
          : null,
      mine: value['mine'] == true,
      choice: parseMessageChoiceState(choice),
      replyTo: reply is Map<String, dynamic> && reply['id'] is String
          ? MessageReply(
              id: reply['id'] as String,
              author: '${reply['author'] ?? '成员'}',
              authorId: reply['author_id'] is String
                  ? reply['author_id'] as String
                  : null,
              text: '${reply['text'] ?? '[消息]'}')
          : null,
      topic: rawTopic is Map<String, dynamic>
          ? MessageTopic.fromJson(rawTopic)
          : null,
      reactions: reactions is List
          ? reactions
              .whereType<Map<String, dynamic>>()
              .map((item) => MessageReaction(
                  text: '${item['text'] ?? ''}',
                  count: (item['count'] as num?)?.toInt() ?? 0,
                  reactedByMe: item['reacted_by_me'] == true,
                  users: item['users'] is List
                      ? (item['users'] as List)
                          .whereType<Map<String, dynamic>>()
                          .where((user) =>
                              user['id'] is String &&
                              (user['id'] as String).trim().isNotEmpty)
                          .map((user) => MessageReactionUser(
                              id: user['id'] as String,
                              name: user['name'] is String
                                  ? user['name'] as String
                                  : ''))
                          .toList(growable: false)
                      : const []))
              .toList()
          : const [],
    );
  }

  Future<void> _cacheMessages(String id, List<ChatMessage> messages) async {
    final scope = widget.cacheScope;
    if (scope == null) return;
    await _messageCacheStore.write(
        scope,
        id,
        messages
            .map((message) => {
                  'id': message.id,
                  'author': message.author,
                  'author_id': message.authorId,
                  'conversation_id': message.conversationId,
                  'sequence': message.sequence,
                  'content_type': message.contentType,
                  'raw_body': message.rawBody,
                  'text': message.text,
                  if (message.editableText != null)
                    'editable_text': message.editableText,
                  'mine': message.mine,
                  if (message.choice != null)
                    'choice': {
                      'my_option_ids': message.choice!.myOptionIds,
                      'response_count': message.choice!.responseCount,
                      'options': message.choice!.options
                          .map((option) => {
                                'id': option.id,
                                'response_count': option.responseCount,
                              })
                          .toList(),
                    },
                  'reply_to': message.replyTo == null
                      ? null
                      : {
                          'id': message.replyTo!.id,
                          'author': message.replyTo!.author,
                          'author_id': message.replyTo!.authorId,
                          'text': message.replyTo!.text,
                        },
                  if (message.topic != null) 'topic': message.topic!.toJson(),
                  'reactions': message.reactions
                      .map((reaction) => {
                            'text': reaction.text,
                            'count': reaction.count,
                            'reacted_by_me': reaction.reactedByMe,
                            'users': reaction.users
                                .map((user) => {
                                      'id': user.id,
                                      if (user.name.isNotEmpty)
                                        'name': user.name,
                                    })
                                .toList(),
                          })
                      .toList(),
                })
            .toList());
  }

  Future<List<ChatMessage>> _readCachedMessages(String id) async {
    final scope = widget.cacheScope;
    if (scope == null) return const [];
    final records = await _messageCacheStore.read(scope, id);
    return records.map(_messageFromCache).whereType<ChatMessage>().toList();
  }

  Future<List<ChatMessage>> _loadMessages() async {
    final id = widget.conversationId;
    if (id == null) return const [];
    final targetSequence = _historyMode ? widget.focusMessageSequence : null;
    if (targetSequence != null) {
      final history = await widget.repository
          .messages(id, beforeSeq: targetSequence + 26, limit: 50);
      _messagePage = history is MessagePage ? history : null;
      _hasMoreOlder = _messagePage?.hasMoreBefore ?? true;
      _lastOlderBeforeSeq = null;
      unawaited(_refreshMessageSnapshots(id, history));
      return history;
    }
    final cached = await _readCachedMessages(id);
    if (cached.isNotEmpty) unawaited(_refreshMessages(id));
    if (cached.isNotEmpty) return cached;
    final fresh = await widget.repository.messages(id);
    _messagePage = fresh is MessagePage ? fresh : null;
    _hasMoreOlder = _messagePage?.hasMoreBefore ?? true;
    _lastOlderBeforeSeq = null;
    unawaited(_cacheMessages(id, fresh));
    // 消息接口返回的 choice/reaction 可能来自旧缓存或断线前的视图；
    // 快照查询是尽力而为的后台修正，失败时不影响消息首屏加载。
    unawaited(_refreshMessageSnapshots(id, fresh));
    return fresh;
  }

  Future<void> _refreshMessages(String id) async {
    final keepBottom = _positionedConversationId == id && _isAtBottom();
    final offset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final fresh = await widget.repository.messages(id);
    _messagePage = fresh is MessagePage ? fresh : null;
    _hasMoreOlder = _messagePage?.hasMoreBefore ?? true;
    _lastOlderBeforeSeq = null;
    final merged = <String, ChatMessage>{
      for (final message in await _readCachedMessages(id)) message.id: message,
      for (final message in fresh) message.id: message,
    }.values.toList()
      ..sort((a, b) => (a.sequence ?? 0).compareTo(b.sequence ?? 0));
    await _cacheMessages(id, merged);
    if (!mounted || widget.conversationId != id) return;
    setState(() {
      _messagesFuture = Future.value(merged);
    });
    if (keepBottom) {
      _correctLatestPosition(id, force: true, expectedOffset: offset);
    }
    unawaited(_refreshMessageSnapshots(id, merged));
  }

  Future<List<ChatMessage>> _applyMessageSnapshots(
      String conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return messages;
    final choiceIds = messages
        .where((message) => message.contentType == 'choice')
        .map((message) => message.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final reactionIds = messages
        .map((message) => message.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    Future<List<T>> queryChunks<T>(
        List<String> ids, Future<List<T>> Function(List<String>) query) async {
      if (ids.isEmpty) return <T>[];
      final chunks = <List<String>>[];
      for (var index = 0; index < ids.length; index += 100) {
        chunks.add(ids.sublist(index, min(index + 100, ids.length)));
      }
      final results = await Future.wait(chunks.map((chunk) async {
        try {
          return await query(chunk);
        } catch (_) {
          // 快照接口不可用时保留消息接口已有状态。
          return <T>[];
        }
      }));
      return results.expand((items) => items).toList(growable: false);
    }

    final snapshots = await Future.wait([
      queryChunks<MessageChoiceSnapshot>(choiceIds,
          (ids) => widget.repository.listChoiceSnapshots(conversationId, ids)),
      queryChunks<MessageReactionSnapshot>(
          reactionIds,
          (ids) =>
              widget.repository.listReactionSnapshots(conversationId, ids)),
    ]);
    final choices = <String, MessageChoiceSnapshot>{
      for (final snapshot in snapshots[0] as List<MessageChoiceSnapshot>)
        snapshot.messageId: snapshot,
    };
    final reactions = <String, MessageReactionSnapshot>{
      for (final snapshot in snapshots[1] as List<MessageReactionSnapshot>)
        snapshot.messageId: snapshot,
    };
    return messages.map((message) {
      final choice = choices[message.id];
      final reaction = reactions[message.id];
      if (choice == null && reaction == null) return message;
      return ChatMessage(
        id: message.id,
        text: message.text,
        author: message.author,
        authorId: message.authorId,
        conversationId: message.conversationId,
        sequence: message.sequence,
        contentType: message.contentType,
        rawBody: message.rawBody,
        mine: message.mine,
        editableText: message.editableText,
        choice: choice == null
            ? message.choice
            : choice.status == 'active'
                ? choice.choice
                : null,
        replyTo: message.replyTo,
        topic: message.topic,
        reactions: reaction?.reactions ?? message.reactions,
      );
    }).toList(growable: false);
  }

  Future<void> _refreshMessageSnapshots(
      String conversationId, List<ChatMessage> messages) async {
    final keepBottom =
        _positionedConversationId == conversationId && _isAtBottom();
    final offset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final updated = await _applyMessageSnapshots(conversationId, messages);
    if (!mounted || widget.conversationId != conversationId) return;
    await _cacheMessages(conversationId, updated);
    if (!mounted || widget.conversationId != conversationId) return;
    setState(() {
      _messagesFuture = Future.value(updated);
    });
    if (keepBottom) {
      _correctLatestPosition(conversationId,
          force: true, expectedOffset: offset);
    }
  }

  void _onRealtimeChanged() {
    final id = widget.conversationId;
    final current = id == null ? null : widget.realtimeStore?.conversations[id];
    if (!mounted) return;
    final incomingIds = _realtimeConversationMessages()
        .where((messageId) => !_seenRealtimeMessageIds.contains(messageId))
        .toList(growable: false);
    _seenRealtimeMessageIds.addAll(incomingIds);
    final shouldShowNewMessages = incomingIds.isNotEmpty &&
        (_historyMode || (_positionedConversationId == id && !_isAtBottom()));
    if (current == null && !shouldShowNewMessages) return;
    final canSend = current == null
        ? _canSend
        : current.canSend && current.topic?.archived != true;
    final cancelRecording = current != null && _recording && !canSend;
    setState(() {
      if (current != null) {
        _conversation = current;
        _canSend = current.canSend;
      }
      if (shouldShowNewMessages) {
        _pendingNewMessageCount += incomingIds.length;
      }
      if (!canSend) _replyTo = null;
    });
    if (cancelRecording) unawaited(_cancelRecording());
  }

  void _requestLatestRead(String conversationId, [List<ChatMessage>? source]) {
    final messages = source ?? _visibleMessages;
    final latest = messages
        .where((message) => message.sequence != null)
        .fold<int>(0, (value, message) => max(value, message.sequence!));
    if (latest <= 0 || latest <= _lastReadSequence) return;
    final atBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <
            48;
    if (!atBottom) return;
    _pendingReadSequence = max(_pendingReadSequence ?? 0, latest);
    if (_readInFlight) return;
    unawaited(_flushRead(conversationId));
  }

  Future<void> _flushRead(String conversationId) async {
    final pending = _pendingReadSequence;
    if (pending == null || pending <= _lastReadSequence || _readInFlight)
      return;
    _readInFlight = true;
    try {
      final result =
          await widget.repository.markConversationRead(conversationId, pending);
      if (!mounted || widget.conversationId != conversationId) return;
      _lastReadSequence = max(_lastReadSequence, result.lastReadSeq);
      if (_pendingReadSequence != null &&
          _pendingReadSequence! <= _lastReadSequence) {
        _pendingReadSequence = null;
      }
      widget.realtimeStore?.markConversationRead(result);
    } catch (_) {
      // 定时器或下一次滚动会重试失败的已读请求。
    } finally {
      _readInFlight = false;
      final next = _pendingReadSequence;
      if (mounted && next != null && next > _lastReadSequence) {
        unawaited(_flushRead(conversationId));
      }
    }
  }

  Future<void> _onScroll() async {
    final id = widget.conversationId;
    if (id != null && !_historyMode) _requestLatestRead(id);
    if (_loadingOlder ||
        !_hasMoreOlder ||
        !_scrollController.hasClients ||
        _scrollController.position.pixels > 24) return;
    if (id == null || !mounted) return;
    final snapshot = await _messagesFuture;
    if (snapshot == null || snapshot.isEmpty) return;
    final first = [..._olderMessages, ...snapshot]
        .where((message) => message.sequence != null)
        .fold<ChatMessage?>(
            null,
            (current, message) =>
                current == null || message.sequence! < current.sequence!
                    ? message
                    : current);
    if (first?.sequence == null ||
        first!.sequence! <= 1 ||
        _lastOlderBeforeSeq == first.sequence) return;
    _lastOlderBeforeSeq = first.sequence;
    final anchorOffset = _scrollController.position.pixels;
    final anchorMaxExtent = _scrollController.position.maxScrollExtent;
    setState(() => _loadingOlder = true);
    try {
      final olderPage = await widget.repository
          .messages(id, beforeSeq: first.sequence, limit: 50);
      final older = olderPage.toList(growable: false);
      if (mounted) {
        final existing =
            {..._olderMessages, ...snapshot}.map((item) => item.id).toSet();
        final added =
            older.where((item) => !existing.contains(item.id)).toList();
        if (olderPage is MessagePage) {
          _messagePage = olderPage;
          _hasMoreOlder = olderPage.hasMoreBefore && added.isNotEmpty;
        } else if (added.isEmpty) {
          _hasMoreOlder = false;
        }
        _olderMessages.insertAll(0, added);
        unawaited(_cacheMessages(id, [..._olderMessages, ...snapshot]));
        setState(() {});
        if (added.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                widget.conversationId != id ||
                !_scrollController.hasClients) return;
            final currentOffset = _scrollController.position.pixels;
            if ((currentOffset - anchorOffset).abs() > 24) return;
            final delta =
                _scrollController.position.maxScrollExtent - anchorMaxExtent;
            final target = (anchorOffset + delta)
                .clamp(0.0, _scrollController.position.maxScrollExtent);
            _scrollController.jumpTo(target.toDouble());
          });
        }
        if (added.isNotEmpty)
          unawaited(_refreshOlderMessageSnapshots(id, added));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _scheduleLatestPosition(
      String conversationId, List<ChatMessage> messages) {
    if (_historyMode ||
        !_initialPositionPending ||
        _positionedConversationId == conversationId ||
        _positioningConversationId == conversationId) return;
    if (messages.isEmpty) return;
    _positioningConversationId = conversationId;
    final generation = _positionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.conversationId != conversationId ||
          generation != _positionGeneration) return;
      _positioningConversationId = null;
      _initialPositionPending = false;
      _positionedConversationId = conversationId;
      if (!_userScrolledDuringInitialPosition && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      _requestLatestRead(conversationId, messages);
    });
  }

  bool _isAtBottom() =>
      !_scrollController.hasClients ||
      _scrollController.position.maxScrollExtent -
              _scrollController.position.pixels <
          48;

  void _correctLatestPosition(String conversationId,
      {bool force = false, double? expectedOffset}) {
    final generation = _positionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.conversationId != conversationId ||
          generation != _positionGeneration) return;
      final unchanged = expectedOffset == null ||
          (_scrollController.hasClients &&
              (_scrollController.position.pixels - expectedOffset).abs() < 4);
      if (_scrollController.hasClients &&
          unchanged &&
          (force || _isAtBottom())) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _refreshOlderMessageSnapshots(
      String conversationId, List<ChatMessage> messages) async {
    final updated = await _applyMessageSnapshots(conversationId, messages);
    if (!mounted || widget.conversationId != conversationId) return;
    final byId = {for (final message in updated) message.id: message};
    var changed = false;
    setState(() {
      for (var index = 0; index < _olderMessages.length; index++) {
        final replacement = byId[_olderMessages[index].id];
        if (replacement != null) {
          _olderMessages[index] = replacement;
          changed = true;
        }
      }
    });
    if (!changed) return;
    final cached = await _readCachedMessages(conversationId);
    if (cached.isEmpty) return;
    final cachedById = {for (final message in updated) message.id: message};
    await _cacheMessages(conversationId,
        cached.map((message) => cachedById[message.id] ?? message).toList());
  }

  GlobalKey _messageKey(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  void _scheduleFocusMessage(
      String conversationId, List<ChatMessage> messages) {
    final targetId = widget.focusMessageId;
    if (targetId == null || targetId.isEmpty || _focusedMessageId == targetId) {
      return;
    }
    if (!messages.any((message) => message.id == targetId)) return;
    _focusedMessageId = targetId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.conversationId != conversationId) return;
      final targetContext = _messageKeys[targetId]?.currentContext;
      if (targetContext == null) return;
      setState(() => _highlightedMessageId = targetId);
      await Scrollable.ensureVisible(targetContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: .35);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _highlightedMessageId == targetId) {
          setState(() => _highlightedMessageId = null);
        }
      });
    });
  }

  Future<void> _jumpToLatest(String conversationId) async {
    if (conversationId.isEmpty) return;
    _historyMode = false;
    _highlightTimer?.cancel();
    _olderMessages.clear();
    _messageKeys.clear();
    _focusedMessageId = null;
    _highlightedMessageId = null;
    _positioningConversationId = null;
    _positionedConversationId = null;
    _positionGeneration++;
    _initialPositionPending = true;
    _userScrolledDuringInitialPosition = false;
    setState(() {
      _pendingNewMessageCount = 0;
      _messagesFuture = _loadMessages();
    });
    widget.onMessageFocused?.call();
  }

  @override
  void didUpdateWidget(covariant ConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeStore != widget.realtimeStore) {
      oldWidget.realtimeStore?.removeListener(_onRealtimeChanged);
      widget.realtimeStore?.addListener(_onRealtimeChanged);
    }
    if (oldWidget.conversationId != widget.conversationId) {
      _highlightTimer?.cancel();
      if (_recording) unawaited(_cancelRecording());
      _olderMessages.clear();
      _hasMoreOlder = true;
      _lastOlderBeforeSeq = null;
      _lastReadSequence = 0;
      _pendingReadSequence = null;
      _positioningConversationId = null;
      _positionedConversationId = null;
      _positionGeneration++;
      _initialPositionPending = true;
      _userScrolledDuringInitialPosition = false;
      _pendingNewMessageCount = 0;
      _focusedMessageId = null;
      _highlightedMessageId = null;
      _historyMode = widget.focusMessageId != null;
      _messageKeys.clear();
      _seenRealtimeMessageIds
        ..clear()
        ..addAll(_realtimeConversationMessages());
      _replyTo = null;
      _conversation = null;
      _topicDetail = null;
      _messagePage = null;
      _canSend = true;
      _messagesFuture = _loadMessages();
      _contactsFuture = _loadConversationContacts();
      _controller.clear();
      unawaited(_restoreDraft());
    }
    if (oldWidget.cacheScope != widget.cacheScope) {
      _olderMessages.clear();
      _hasMoreOlder = true;
      _lastOlderBeforeSeq = null;
      _messagePage = null;
      _messagesFuture = _loadMessages();
      _positioningConversationId = null;
      _positionedConversationId = null;
      _positionGeneration++;
      _initialPositionPending = true;
      _userScrolledDuringInitialPosition = false;
      _pendingNewMessageCount = 0;
      _focusedMessageId = null;
      _highlightedMessageId = null;
      _messageKeys.clear();
      _seenRealtimeMessageIds
        ..clear()
        ..addAll(_realtimeConversationMessages());
      _contactsFuture = _loadConversationContacts();
    }
    if (oldWidget.conversationId == widget.conversationId &&
        oldWidget.focusMessageId != widget.focusMessageId) {
      _highlightTimer?.cancel();
      _focusedMessageId = null;
      _highlightedMessageId = null;
      if (widget.focusMessageId != null) {
        _historyMode = true;
        _olderMessages.clear();
        _messageKeys.clear();
        _positionGeneration++;
        _initialPositionPending = true;
        _messagesFuture = _loadMessages();
      } else if (_historyMode) {
        unawaited(_jumpToLatest(widget.conversationId ?? ''));
      }
    }
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _readRetryTimer?.cancel();
    _highlightTimer?.cancel();
    _persistDraft();
    _controller.removeListener(_persistDraft);
    _controller.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice(String conversationId) async {
    if (!_conversationCanSend(conversationId)) return;
    if (_recording) {
      try {
        final path = await _voiceRecorder.stop();
        final durationMs = _voiceRecorder.lastDurationMs;
        if (mounted) setState(() => _recording = false);
        if (path == null) return;
        if (!mounted || !_conversationCanSend(conversationId)) return;
        await widget.repository.sendVoice(
            conversationId,
            AttachmentUpload(
                path: path, name: 'voice.m4a', mimeType: 'audio/mp4'),
            durationMs: durationMs,
            replyToMessageId: _replyTo?.id);
        if (mounted) {
          setState(() {
            _replyTo = null;
            _messagesFuture = _loadMessages();
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() => _recording = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('发送语音失败：$error')));
        }
      }
      return;
    }
    try {
      await _voiceRecorder.start();
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法开始录音：$error')));
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording && !_voiceRecorder.isRecording) return;
    await _voiceRecorder.stop();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _openMemberConversation(Contact contact) async {
    try {
      final conversation =
          await widget.repository.createDirectConversation(contact.id);
      if (mounted) widget.onOpenConversation?.call(conversation.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开私聊：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = widget.conversationId;
    if (conversationId == null) return const _ConversationEmptyState();
    final canSend = _conversationCanSend(conversationId);
    return Column(
      children: [
        if (_topicDetail != null) TopicSourceBanner(detail: _topicDetail!),
        if (_selectedMessageIds.isNotEmpty)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(children: [
              IconButton(
                  tooltip: '取消多选',
                  onPressed: () => setState(_selectedMessageIds.clear),
                  icon: const Icon(Icons.close)),
              Expanded(child: Text('已选择 ${_selectedMessageIds.length} 条消息')),
              IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: _copySelected),
              IconButton(
                  tooltip: '转发所选',
                  icon: const Icon(Icons.forward_outlined),
                  onPressed: () => _showForwardDialog(
                      conversationId,
                      _visibleMessages
                          .where((message) =>
                              _selectedMessageIds.contains(message.id) &&
                              _canForwardOrSelect(message))
                          .map((message) => message.id)
                          .toList())),
              IconButton(
                  tooltip: '撤回所选',
                  icon: const Icon(Icons.undo),
                  onPressed: !_topicIsOpen(conversationId)
                      ? null
                      : () => _revokeSelected(conversationId)),
            ]),
          ),
        Expanded(
          child: Stack(
            children: [
              FutureBuilder<List<ChatMessage>>(
                future: _messagesFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ConversationLoadError(
                        onRetry: () => setState(() {
                              _messagesFuture = _loadMessages();
                            }));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final historyIds = <String>{
                    for (final message in _olderMessages) message.id,
                    for (final message in snapshot.data!) message.id,
                  };
                  final realtimeMessages = widget.realtimeStore?.messages.values
                      .where((message) =>
                          message.id.isNotEmpty &&
                          message.conversationId == conversationId &&
                          (!_historyMode || historyIds.contains(message.id)))
                      .toList();
                  final messages =
                      realtimeMessages == null || realtimeMessages.isEmpty
                          ? snapshot.data!
                          : [...snapshot.data!, ...realtimeMessages];
                  final byId = <String, ChatMessage>{};
                  for (final message in [..._olderMessages, ...messages]) {
                    byId[message.id] = message;
                  }
                  final allMessages = byId.values.toList()
                    ..sort((left, right) {
                      final leftSeq = left.sequence;
                      final rightSeq = right.sequence;
                      if (leftSeq == null && rightSeq == null) return 0;
                      if (leftSeq == null) return 1;
                      if (rightSeq == null) return -1;
                      return leftSeq.compareTo(rightSeq);
                    });
                  _visibleMessages = allMessages;
                  _scheduleLatestPosition(conversationId, allMessages);
                  _scheduleFocusMessage(conversationId, allMessages);
                  if (allMessages.isEmpty) {
                    return const _ConversationEmptyState();
                  }
                  return NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (_initialPositionPending &&
                          notification.direction != ScrollDirection.idle) {
                        _userScrolledDuringInitialPosition = true;
                      }
                      return false;
                    },
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                      children: allMessages
                          .map((message) => Align(
                                key: _messageKey(message.id),
                                alignment: message.contentType == 'system_event'
                                    ? Alignment.center
                                    : message.mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                child: GestureDetector(
                                  onTap: _selectedMessageIds.isEmpty ||
                                          !_canForwardOrSelect(message)
                                      ? null
                                      : () => setState(() {
                                            if (!_selectedMessageIds
                                                .remove(message.id)) {
                                              if (_selectedMessageIds.length >=
                                                  _maxSelectedMessages) return;
                                              _selectedMessageIds
                                                  .add(message.id);
                                            }
                                          }),
                                  onLongPress: () {
                                    if (_selectedMessageIds.isNotEmpty) {
                                      if (!_canForwardOrSelect(message)) return;
                                      if (_selectedMessageIds.length >=
                                          _maxSelectedMessages) return;
                                      setState(() =>
                                          _selectedMessageIds.add(message.id));
                                    } else if (_hasMessageActions(message)) {
                                      _showMessageActions(
                                          conversationId, message);
                                    }
                                  },
                                  child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      padding: _highlightedMessageId == message.id
                                          ? const EdgeInsets.all(2)
                                          : EdgeInsets.zero,
                                      decoration: _highlightedMessageId == message.id
                                          ? BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: .65),
                                              borderRadius:
                                                  BorderRadius.circular(18))
                                          : null,
                                      child: _MessageBubble(
                                          message: message,
                                          repository: widget.repository,
                                          conversationId: conversationId,
                                          canReact:
                                              _topicIsOpen(conversationId),
                                          canRespond: canSend,
                                          onOpenTopic:
                                              widget.onOpenConversation,
                                          onOpenInternalLink:
                                              widget.onOpenInternalLink,
                                          onForwardMessage: (id) => _showForwardDialog(
                                              conversationId, [id]),
                                          contactsFuture: _contactsFuture,
                                          isGroupConversation:
                                              _isGroupConversation,
                                          onOpenMemberConversation:
                                              _openMemberConversation,
                                          onReeditMessage: _reeditMessage,
                                          cacheScope: widget.cacheScope)),
                                ),
                              ))
                          .toList(),
                    ),
                  );
                },
              ),
              if (_historyMode || _pendingNewMessageCount > 0)
                Positioned(
                    right: 16,
                    bottom: 12,
                    child: Semantics(
                      button: true,
                      label: '回到最新消息',
                      child: FilledButton.icon(
                          onPressed: () => _jumpToLatest(conversationId),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: Text(_historyMode
                              ? _pendingNewMessageCount > 0
                                  ? '返回最新 · $_pendingNewMessageCount 条新消息'
                                  : '返回最新消息'
                              : '新消息 $_pendingNewMessageCount')),
                    )),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyTo != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.reply, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              '回复 ${_replyTo!.author}：${_replyTo!.text}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          tooltip: '取消回复',
                          onPressed: () => setState(() => _replyTo = null),
                          icon: const Icon(Icons.close, size: 18)),
                    ]),
                  ),
                // 输入框单独占一行，操作按钮放到下一行，窄屏不会再被挤压。
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _controller,
                          focusNode: _composerFocusNode,
                          readOnly: !canSend,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                              hintText: canSend ? '输入消息…' : '话题已关闭',
                              isDense: true))),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: _sendingMessage
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(46, 46),
                        shape: const CircleBorder()),
                    tooltip: '发送',
                    onPressed: !canSend || _sendingMessage || _sendingFile
                        ? null
                        : () => _sendMessage(conversationId),
                  ),
                ]),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 0, runSpacing: 0, children: [
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      tooltip: '选择表情',
                      onPressed: canSend ? _showEmojiPicker : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_outlined),
                      tooltip: '历史附件',
                      onPressed: _sendingFile
                          ? null
                          : () => showHistoryAttachmentsDialog(
                                context,
                                repository: widget.repository,
                                conversationId: conversationId,
                              ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forum_outlined),
                      tooltip: '话题列表',
                      onPressed: widget.onOpenConversation == null
                          ? null
                          : () => showConversationTopicsDialog(
                                context,
                                repository: widget.repository,
                                conversationId: conversationId,
                                onOpenTopic: widget.onOpenConversation,
                              ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.alternate_email),
                      tooltip: '提及成员',
                      onPressed: !canSend || _sendingFile ? null : _pickMention,
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      tooltip: '发送文件',
                      onPressed: !canSend || _sendingFile
                          ? null
                          : () => _pickAndSendFile(conversationId),
                    ),
                    IconButton(
                      icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                      tooltip: _recording ? '停止并发送语音' : '录制语音',
                      color: _recording
                          ? Theme.of(context).colorScheme.error
                          : null,
                      onPressed: !canSend || _sendingFile
                          ? null
                          : () => _toggleVoice(conversationId),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copySelected() async {
    final text = _visibleMessages
        .where((message) => _selectedMessageIds.contains(message.id))
        .map((message) => message.text)
        .join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制')));
    }
  }

  Future<void> _showEmojiPicker() async {
    const emojis = [
      '😀',
      '😂',
      '🙂',
      '😍',
      '🤔',
      '😢',
      '😡',
      '👍',
      '👎',
      '👏',
      '🙏',
      '🎉',
      '❤️',
      '🔥',
      '✅',
      '⭐',
      '🚀',
      '💡',
    ];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 6,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: emojis
              .map((value) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, value),
                    child: Center(
                        child:
                            Text(value, style: const TextStyle(fontSize: 28))),
                  ))
              .toList(),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    final value = _controller.value;
    final text = value.text;
    final start = value.selection.isValid ? value.selection.start : text.length;
    final end = value.selection.isValid ? value.selection.end : start;
    final next = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + emoji.length));
  }

  Future<void> _revokeSelected(String conversationId) async {
    if (!_topicIsOpen(conversationId)) return;
    final selected = _visibleMessages
        .where((message) =>
            _selectedMessageIds.contains(message.id) &&
            message.mine &&
            message.contentType != 'revoked')
        .toList();
    for (final message in selected) {
      await widget.repository.revokeMessage(conversationId, message.id);
    }
    if (mounted) setState(_selectedMessageIds.clear);
  }

  void _reeditMessage(ChatMessage message) {
    final text = message.editableText;
    if (text == null || text.isEmpty) return;
    _controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    _composerFocusNode.requestFocus();
  }

  Future<void> _pickMention() async {
    final contacts = await (_contactsFuture ??= widget.repository.contacts());
    if (!mounted) return;
    final selected = await showModalBottomSheet<Contact>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: const Text('所有人'),
                    onTap: () => Navigator.pop(
                        context, const Contact(id: 'all', name: '所有人')),
                  ),
                  ...contacts.map((contact) => ListTile(
                        leading: CircleAvatar(
                            child: Text(contact.name.isEmpty
                                ? '?'
                                : contact.name.substring(0, 1))),
                        title: Text(contact.name),
                        subtitle: Text(contact.online ? '在线' : '离线'),
                        onTap: () => Navigator.pop(context, contact),
                      )),
                ],
              ),
            ));
    if (selected == null || !mounted) return;
    final token = selected.id == 'all'
        ? '{(@user/all)}'
        : '{(@${selected.type}/${selected.id})}';
    final value = _controller.value;
    final text = value.text;
    final start = value.selection.isValid ? value.selection.start : text.length;
    final end = value.selection.isValid ? value.selection.end : start;
    final next = text.replaceRange(start, end, '$token ');
    _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + token.length + 1));
  }

  Future<void> _pickAndSendFile(String conversationId) async {
    final result = await FilePicker.pickFiles(withData: false);
    if (!mounted || result == null || result.files.single.path == null) {
      if (mounted && result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前平台无法读取所选文件')));
      }
      return;
    }
    final file = result.files.single;
    if (file.size > 200 * 1024 * 1024) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文件不能超过 200MiB')));
      return;
    }
    setState(() => _sendingFile = true);
    try {
      final upload = AttachmentUpload(
          path: file.path!,
          name: file.name,
          mimeType: _mimeType(file.extension));
      if (upload.mimeType.startsWith('image/')) {
        await widget.repository
            .sendImage(conversationId, upload, replyToMessageId: _replyTo?.id);
      } else {
        await widget.repository
            .sendFile(conversationId, upload, replyToMessageId: _replyTo?.id);
      }
      if (mounted) {
        setState(() {
          _replyTo = null;
          _messagesFuture = _loadMessages();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送附件失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<void> _sendMessage(String conversationId) async {
    if (_sendingMessage || _sendingFile) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyTo?.id;
    setState(() => _sendingMessage = true);
    try {
      await widget.repository
          .sendMessage(conversationId, text, replyToMessageId: replyTo);
      if (_controller.text.trim() == text) {
        _controller.clear();
        if (mounted && _replyTo?.id == replyTo) {
          setState(() => _replyTo = null);
        }
        final key = _draftKey;
        if (key != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(key);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送消息失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  String _mimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'mp4':
        return 'video/mp4';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _confirmRevoke(
      String conversationId, ChatMessage message) async {
    if (!_topicIsOpen(conversationId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确定撤回这条消息吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('撤回')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.repository.revokeMessage(conversationId, message.id);
    if (mounted) setState(() {});
  }

  Future<void> _showMessageActions(
      String conversationId, ChatMessage message) async {
    if (!_hasMessageActions(message)) return;
    final topicArchived = _topicArchived;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          if (!topicArchived) ...[
            const ListTile(title: Text('表情回应')),
            Wrap(
              children: ['👍', '❤️', '😂', '🎉', '🤔', '👏']
                  .map((emoji) => IconButton(
                        icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                        tooltip: emoji,
                        onPressed: () =>
                            Navigator.pop(context, 'reaction:$emoji'),
                      ))
                  .toList(),
            ),
          ],
          if (!topicArchived && message.mine)
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('撤回消息'),
              onTap: () => Navigator.pop(context, 'revoke'),
            ),
          if (!topicArchived && !_isTopicConversation && message.topic == null)
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('回复'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
          if (_canForwardOrSelect(message))
            ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('多选'),
                onTap: () => Navigator.pop(context, 'select')),
          if (!topicArchived)
            ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('创建话题'),
                onTap: () => Navigator.pop(context, 'topic')),
          if (_canForwardOrSelect(message))
            ListTile(
                leading: const Icon(Icons.forward_outlined),
                title: const Text('转发消息'),
                onTap: () => Navigator.pop(context, 'forward')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'select') {
      if (mounted) setState(() => _selectedMessageIds.add(message.id));
    } else if (action == 'reply' && _topicIsOpen(conversationId)) {
      if (mounted) {
        setState(() => _replyTo = MessageReply(
            id: message.id,
            author: message.author,
            authorId: message.authorId,
            text: message.text));
      }
    } else if (action == 'revoke' && _topicIsOpen(conversationId)) {
      await _confirmRevoke(conversationId, message);
    } else if (action == 'topic' &&
        !_isTopicConversation &&
        message.topic == null &&
        _topicIsOpen(conversationId)) {
      try {
        final topic =
            await widget.repository.createTopic(conversationId, message.id);
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text('话题已创建或已打开')));
          widget.onOpenConversation?.call(topic.id);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text('创建话题失败：$error')));
        }
      }
    } else if (action == 'forward') {
      await _showForwardDialog(conversationId, [message.id]);
    } else if (action.startsWith('reaction:') && _topicIsOpen(conversationId)) {
      await widget.repository.setReaction(conversationId, message.id,
          text: action.substring('reaction:'.length), reacted: true);
    }
  }

  Future<void> _showForwardDialog(
      String sourceConversationId, List<String> messageIds) async {
    final ids = messageIds.toSet().toList();
    if (ids.isEmpty || !mounted) return;
    final conversations = await widget.repository.conversations();
    if (!mounted) return;
    final targets = conversations
        .where((conversation) => conversation.topic?.archived != true)
        .toList(growable: false);
    final selected = <String>{};
    final sent = <String>{};
    final failed = <String, String>{};
    var keyword = '';
    var mode = ForwardMode.separate;
    var submitting = false;
    final clientForwardId = newForwardClientId();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final normalized = keyword.trim().toLowerCase();
          final visible = normalized.isEmpty
              ? targets
              : targets
                  .where((conversation) =>
                      conversation.title.toLowerCase().contains(normalized))
                  .toList(growable: false);
          Future<void> submit() async {
            if (submitting || selected.isEmpty) return;
            setDialogState(() => submitting = true);
            try {
              final result = await widget.repository.forwardMessages(
                  sourceConversationId,
                  ForwardMessagesRequest(
                      clientForwardId: clientForwardId,
                      messageIds: ids,
                      mode: mode,
                      targetConversationIds: selected.toList()));
              final nextFailed = <String, String>{};
              for (final target in result.results) {
                if (target.sent) {
                  sent.add(target.conversationId);
                } else {
                  nextFailed[target.conversationId] =
                      target.error?.message ?? '转发失败';
                }
              }
              failed
                ..clear()
                ..addAll(nextFailed);
              selected
                ..clear()
                ..addAll(nextFailed.keys);
              if (result.failedCount == 0) {
                if (mounted) {
                  setState(_selectedMessageIds.clear);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已转发到 ${result.sentCount} 个会话')));
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } else {
                setDialogState(() {});
                if (mounted && result.sentCount > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '已转发到 ${result.sentCount} 个会话，${result.failedCount} 个失败')));
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('转发失败，请检查目标会话权限')));
                }
              }
            } catch (error) {
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('转发消息失败：$error')));
              }
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => submitting = false);
              }
            }
          }

          return PopScope(
            canPop: !submitting,
            child: AlertDialog(
              title: Text(ids.length > 1 ? '转发 ${ids.length} 条消息' : '转发消息'),
              content: SizedBox(
                width: 440,
                height: 460,
                child: Column(children: [
                  TextField(
                      enabled: !submitting,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search), labelText: '搜索会话'),
                      onChanged: (value) =>
                          setDialogState(() => keyword = value)),
                  if (ids.length > 1) ...[
                    const SizedBox(height: 10),
                    SegmentedButton<ForwardMode>(
                      segments: const [
                        ButtonSegment(
                            value: ForwardMode.separate, label: Text('逐条转发')),
                        ButtonSegment(
                            value: ForwardMode.merged, label: Text('合并转发')),
                      ],
                      selected: {mode},
                      onSelectionChanged: submitting
                          ? null
                          : (values) =>
                              setDialogState(() => mode = values.first),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('没有匹配的会话'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final conversation = visible[index];
                              final id = conversation.id;
                              final isSent = sent.contains(id);
                              final error = failed[id];
                              final label = conversation.type == 'group'
                                  ? '群聊'
                                  : conversation.type == 'app'
                                      ? '应用'
                                      : conversation.type == 'topic'
                                          ? '话题'
                                          : '私聊';
                              return CheckboxListTile(
                                value: isSent || selected.contains(id),
                                enabled: !submitting && !isSent,
                                title: Text(conversation.title),
                                subtitle: Text(
                                  error ?? (isSent ? '已转发' : label),
                                  style: error == null
                                      ? null
                                      : TextStyle(
                                          color: Theme.of(dialogContext)
                                              .colorScheme
                                              .error),
                                ),
                                secondary: CircleAvatar(
                                    child: Text(conversation.title.isEmpty
                                        ? '?'
                                        : conversation.title.substring(0, 1))),
                                onChanged: (checked) => setDialogState(() {
                                  if (checked == true) {
                                    if (selected.length >= _maxForwardTargets) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('最多选择 20 个目标会话')));
                                      return;
                                    }
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                  failed.remove(id);
                                }),
                              );
                            },
                          ),
                  ),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('已选择 ${selected.length} 个会话',
                          style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
              actions: [
                TextButton(
                    onPressed:
                        submitting ? null : () => Navigator.pop(dialogContext),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: submitting || selected.isEmpty ? null : submit,
                    child: Text(submitting ? '转发中…' : '转发')),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConversationEmptyState extends StatelessWidget {
  const _ConversationEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 42, color: colors.primary),
            const SizedBox(height: 12),
            Text('暂无消息',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 4),
            Text('发送第一条消息，开始这段对话',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    )),
          ],
        ),
      ),
    );
  }
}

class _ConversationLoadError extends StatelessWidget {
  const _ConversationLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: colors.outline),
          const SizedBox(height: 10),
          Text('消息加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试')),
        ]),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message,
      required this.repository,
      required this.conversationId,
      this.canReact = true,
      this.canRespond = true,
      this.onOpenTopic,
      this.onOpenInternalLink,
      this.onForwardMessage,
      this.contactsFuture,
      this.isGroupConversation = false,
      this.onOpenMemberConversation,
      this.onReeditMessage,
      this.cacheScope});
  final ChatMessage message;
  final MagicChatRepository repository;
  final String conversationId;
  final bool canReact;
  final bool canRespond;
  final ValueChanged<String>? onOpenTopic;
  final ValueChanged<String>? onOpenInternalLink;
  final Future<void> Function(String messageId)? onForwardMessage;
  final Future<List<Contact>>? contactsFuture;
  final bool isGroupConversation;
  final Future<void> Function(Contact contact)? onOpenMemberConversation;
  final ValueChanged<ChatMessage>? onReeditMessage;
  final MessageCacheScope? cacheScope;

  Future<void> _showImageViewer(BuildContext context, Uri? uri,
      {Uint8List? bytes}) async {
    final fileId = message.rawBody['file_id'];
    final name = message.rawBody['name'];
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: .25,
                maxScale: 6,
                boundaryMargin: const EdgeInsets.all(80),
                child: Center(
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : uri == null
                          ? const Text('图片加载失败',
                              style: TextStyle(color: Colors.white))
                          : Image.network(uri.toString(),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Text('图片加载失败',
                                  style: TextStyle(color: Colors.white))),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              right: 4,
              child: Row(children: [
                IconButton(
                    tooltip: '关闭',
                    color: Colors.white,
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close)),
                const Spacer(),
                if (fileId is String && fileId.isNotEmpty)
                  IconButton(
                    tooltip: '保存图片',
                    color: Colors.white,
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _saveImage(
                        context,
                        fileId,
                        name is String && name.trim().isNotEmpty
                            ? name.trim()
                            : 'image-${message.id}.jpg',
                        bytes: bytes),
                  ),
                if (onForwardMessage != null)
                  IconButton(
                    tooltip: '转发图片',
                    color: Colors.white,
                    icon: const Icon(Icons.forward_outlined),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await onForwardMessage!(message.id);
                    },
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveImage(BuildContext context, String fileId, String fileName,
      {Uint8List? bytes}) async {
    try {
      final key = _attachmentCacheKey(fileId);
      if (bytes == null) {
        try {
          bytes = await LocalAssetCache().read(key);
        } catch (_) {
          bytes = null;
        }
      }
      bytes ??= await repository.downloadAttachment(fileId);
      if (bytes == null || bytes.isEmpty) throw Exception('图片内容为空');
      try {
        await LocalAssetCache().write(key, bytes);
      } catch (_) {
        // 保存到用户选择的位置不依赖本地缓存目录可写。
      }
      final path = await FilePicker.saveFile(
          dialogTitle: '保存图片', fileName: fileName, bytes: bytes);
      if (context.mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片已保存')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存图片失败：$error')));
      }
    }
  }

  String _attachmentCacheKey(String fileId) {
    final scope = cacheScope;
    final owner = scope == null ? '' : '${scope.serverUrl}|${scope.userId}|';
    return 'attachment|$owner$fileId';
  }

  Future<void> _cacheAttachment(String fileId, Uri uri) async {
    final cache = LocalAssetCache();
    final key = _attachmentCacheKey(fileId);
    try {
      if (await cache.read(key) != null) return;
    } catch (_) {
      // 缓存不可读时继续从服务器获取附件。
    }
    Uint8List? bytes;
    try {
      bytes = await repository.downloadResource(uri);
    } catch (_) {
      bytes = null;
    }
    bytes ??= await repository.downloadAttachment(fileId);
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await cache.write(key, bytes);
      } catch (_) {
        // 外部打开仍可使用临时 URL。
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.contentType == 'system_event') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final mine = message.mine;
    final revoked = message.contentType == 'revoked';
    final hasVoicePlayer = !revoked &&
        message.contentType == 'voice' &&
        message.rawBody['file_id'] is String;
    final prefix = switch (message.contentType) {
      'image' => Icons.image_outlined,
      'file' => Icons.attach_file,
      'voice' => Icons.mic_none,
      'choice' => Icons.checklist,
      'object' => Icons.view_agenda_outlined,
      'chart' => Icons.bar_chart,
      'forward_bundle' => Icons.forum_outlined,
      _ => null,
    };
    final options = message.rawBody['options'];
    final bodyTitle = message.rawBody['title'];
    final bodyDescription = message.rawBody['description'];
    final bodyUrl = message.rawBody['url'];
    final linkTitle = bodyTitle is String ? bodyTitle.trim() : '';
    final linkDescription = bodyDescription is String
        ? bodyDescription.trim()
        : message.contentType == 'link' && bodyUrl is String
            ? bodyUrl.trim()
            : '';
    final linkUrl = bodyUrl is String ? bodyUrl.trim() : '';
    return Container(
      margin: EdgeInsets.only(
          left: mine ? 56 : 12, right: mine ? 12 : 56, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!revoked && message.replyTo != null)
          _replyPreview(context, message.replyTo!, mine, colors),
        if (!mine)
          FutureBuilder<List<Contact>>(
              future: contactsFuture,
              builder: (context, snapshot) {
                final contact = _findContact(snapshot.data);
                final contactName = snapshot.hasData
                    ? _contactName(contact) ?? _nonIdAuthor
                    : '';
                final avatarContact = contact ??
                    (message.authorId == null
                        ? null
                        : Contact(
                            id: message.authorId!,
                            name: _nonIdAuthor,
                          ));
                final canOpenProfile = snapshot.hasData &&
                    avatarContact != null &&
                    (avatarContact.type == 'user' || contact == null);
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                    button: canOpenProfile,
                    label: canOpenProfile
                        ? '${avatarContact.displayName}的头像'
                        : null,
                    child: InkWell(
                      key: ValueKey('message-avatar-${message.id}'),
                      customBorder: const CircleBorder(),
                      onTap: !canOpenProfile
                          ? null
                          : () {
                              if (isGroupConversation &&
                                  onOpenMemberConversation != null) {
                                unawaited(
                                    onOpenMemberConversation!(avatarContact));
                              } else {
                                _showContactPanel(context, avatarContact);
                              }
                            },
                      child: _avatar(context, contact ?? avatarContact,
                          snapshot.hasData ? _nonIdAuthor : ''),
                    ),
                  ),
                  if (contactName.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(contactName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600)),
                  ],
                ]);
              }),
        if (!hasVoicePlayer)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (prefix != null) Icon(prefix, size: 18),
            if (prefix != null) const SizedBox(width: 6),
            Flexible(
                child: revoked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(message.text,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontStyle: FontStyle.italic)),
                            if (message.mine && message.editableText != null)
                              TextButton.icon(
                                  onPressed: onReeditMessage == null
                                      ? null
                                      : () => onReeditMessage!(message),
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('重新编辑'),
                                  style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero)),
                          ])
                    : message.contentType == 'unsupported'
                        ? Text('暂不支持查看该消息',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant))
                        : message.contentType == 'markdown'
                            ? MarkdownBody(
                                data: message.text,
                                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                    p: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color:
                                                mine ? colors.onPrimary : null),
                                    a: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: mine
                                                ? colors.onPrimary
                                                : colors.primary,
                                            decoration:
                                                TextDecoration.underline)),
                                onTapLink: (text, href, title) {
                                  final uri = parseMarkdownLink(href);
                                  if (uri != null) {
                                    unawaited(launchUrl(uri,
                                        mode: LaunchMode.externalApplication));
                                  }
                                })
                            : message.contentType == 'link' ||
                                    message.contentType == 'card'
                                ? MessageLinkCard(
                                    title: linkTitle.isNotEmpty
                                        ? linkTitle
                                        : message.contentType == 'link' &&
                                                linkUrl.isNotEmpty
                                            ? linkUrl
                                            : message.contentType == 'card'
                                                ? '卡片'
                                                : '链接',
                                    description: linkDescription,
                                    url: linkUrl,
                                    icon: message.contentType == 'card'
                                        ? Icons.open_in_new
                                        : Icons.link_outlined,
                                    textColor: mine
                                        ? colors.onPrimary
                                        : colors.onSurface,
                                    accentColor: mine
                                        ? colors.onPrimary
                                        : colors.primary,
                                    backgroundColor: mine
                                        ? colors.onPrimary.withValues(alpha: .1)
                                        : colors.surfaceContainerLow,
                                    allowInternalPath:
                                        message.contentType == 'card',
                                    semanticLabel:
                                        '${message.contentType == 'card' ? '卡片' : '链接'}：${linkTitle.isNotEmpty ? linkTitle : linkUrl}',
                                    onOpen: (uri) {
                                      unawaited(launchUrl(uri,
                                          mode:
                                              LaunchMode.externalApplication));
                                    },
                                    onOpenInternal: onOpenInternalLink,
                                  )
                                : message.contentType == 'forward_bundle'
                                    ? _ForwardBundlePreview(
                                        body: message.rawBody,
                                        summary: message.text,
                                        textColor: mine ? colors.onPrimary : null)
                                    : FutureBuilder<List<Contact>>(
                                        future: contactsFuture,
                                        builder: (context, snapshot) {
                                          final contacts = snapshot.data ??
                                              const <Contact>[];
                                          return Text(
                                              formatMentionText(
                                                  message.text,
                                                  contacts.map((c) => (
                                                        id: c.id,
                                                        name: c.displayName
                                                      ))),
                                              style: TextStyle(
                                                  color: mine
                                                      ? colors.onPrimary
                                                      : null));
                                        })),
          ]),
        if (hasVoicePlayer)
          VoiceMessagePlayer(
            fileId: message.rawBody['file_id'] as String,
            durationMs: parseVoiceDuration(message.rawBody['duration_ms']),
            transcript: message.rawBody['transcript'] is String
                ? message.rawBody['transcript'] as String
                : '',
            foregroundColor: mine ? colors.onPrimary : colors.onSurface,
            resolveUrl: repository.attachmentUrl,
          ),
        if (!revoked &&
            (message.contentType == 'image' || message.contentType == 'file') &&
            message.rawBody['file_id'] is String)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.contentType == 'image')
                _CachedConversationImage(
                  repository: repository,
                  cacheScope: cacheScope,
                  fileId: message.rawBody['file_id'] as String,
                  onTap: (data) =>
                      _showImageViewer(context, data?.uri, bytes: data?.bytes),
                )
              else
                FutureBuilder<Uri?>(
                  future: repository
                      .attachmentUrl(message.rawBody['file_id'] as String),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('附件暂时无法加载'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: SizedBox(
                              height: 40,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)));
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(height: 40);
                    }
                    final uri = snapshot.data;
                    if (uri == null) {
                      return const SizedBox(height: 40);
                    }
                    final name = message.rawBody['name'];
                    final size = message.rawBody['size_bytes'];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name is String && name.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(name.trim(),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        TextButton.icon(
                            onPressed: () async {
                              try {
                                await _cacheAttachment(
                                    message.rawBody['file_id'] as String, uri);
                                if (!context.mounted) return;
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('附件加载失败：$error')));
                                }
                              }
                            },
                            icon: const Icon(Icons.download_outlined),
                            label: Text(size is num
                                ? '打开附件 · ${_formatAttachmentSize(size)}'
                                : '打开附件')),
                      ],
                    );
                  },
                ),
              if (message.contentType == 'image' &&
                  message.rawBody['caption'] is String &&
                  (message.rawBody['caption'] as String).trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: message.rawBody['caption_type'] == 'markdown'
                      ? MarkdownBody(
                          data: (message.rawBody['caption'] as String).trim(),
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(Theme.of(context)),
                          onTapLink: (text, href, title) {
                            final uri = parseMarkdownLink(href);
                            if (uri != null) {
                              unawaited(launchUrl(uri,
                                  mode: LaunchMode.externalApplication));
                            }
                          })
                      : FutureBuilder<List<Contact>>(
                          future: contactsFuture,
                          builder: (context, snapshot) => Text(
                              formatMentionText(
                                  (message.rawBody['caption'] as String).trim(),
                                  (snapshot.data ?? const <Contact>[]).map(
                                      (contact) => (
                                            id: contact.id,
                                            name: contact.displayName
                                          ))),
                              style: TextStyle(
                                  color: mine ? colors.onPrimary : null))),
                ),
            ],
          ),
        if (!revoked && message.contentType == 'choice')
          _ChoiceOptions(
              options: _choiceOptions(options),
              selection: message.rawBody['selection'] == 'multiple'
                  ? 'multiple'
                  : 'single',
              choice: message.choice,
              canRespond: canRespond,
              onSubmit: (optionIds) => repository.submitChoice(
                  conversationId, message.id, optionIds)),
        if (!revoked && message.contentType == 'chart')
          ChartPreview(body: message.rawBody),
        if (!revoked &&
            (message.contentType == 'object' || message.contentType == 'chart'))
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(message.contentType == 'chart' ? '查看图表数据' : '查看对象详情'),
              children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                        const JsonEncoder.withIndent('  ')
                            .convert(message.rawBody),
                        style: Theme.of(context).textTheme.bodySmall))
              ]),
        if (!revoked && message.topic != null)
          TopicReplyPreview(
              topic: message.topic!,
              contactsFuture: contactsFuture,
              onOpen: onOpenTopic),
        if (!revoked && message.reactions.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: message.reactions
                      .map((reaction) => GestureDetector(
                          onLongPress: () =>
                              _showReactionUsers(context, reaction),
                          child: ActionChip(
                              label: Text('${reaction.text} ${reaction.count}'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: reaction.reactedByMe
                                  ? colors.primaryContainer
                                  : null,
                              onPressed: canReact
                                  ? () => repository.setReaction(
                                      conversationId, message.id,
                                      text: reaction.text,
                                      reacted: !reaction.reactedByMe)
                                  : null)))
                      .toList()))
      ]),
    );
  }

  Contact? _findContact(List<Contact>? contacts) {
    final id = message.authorId;
    if (id == null || contacts == null) return null;
    for (final contact in contacts) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  String? _contactName(Contact? contact) {
    if (contact == null) return null;
    final name = contact.displayName.trim();
    if (name.isEmpty || name == contact.id.trim()) return null;
    return name;
  }

  Widget _replyPreview(
      BuildContext context, MessageReply reply, bool mine, ColorScheme colors) {
    Widget content(Contact? contact) {
      final fallback = reply.author.trim();
      final author = _contactName(contact) ??
          (fallback == reply.authorId || fallback == '用户' || fallback == '成员'
              ? ''
              : fallback);
      final prefix = author.isEmpty ? '回复' : '回复 $author';
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: mine
              ? colors.onPrimary.withValues(alpha: .16)
              : colors.primary.withValues(alpha: .08),
          border: Border(left: BorderSide(color: colors.primary, width: 3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('$prefix：${reply.text}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: mine ? colors.onPrimary : colors.onSurfaceVariant)),
      );
    }

    final future = contactsFuture;
    if (future == null) return content(null);
    return FutureBuilder<List<Contact>>(
        future: future,
        builder: (context, snapshot) => content(_findContact(snapshot.data)));
  }

  String get _nonIdAuthor {
    final author = message.author.trim();
    return message.authorId != null &&
            (author == message.authorId || author == '用户' || author == '成员')
        ? ''
        : author;
  }

  Widget _avatar(BuildContext context, Contact? contact, String fallback) {
    final serverUrl = repository is HttpMagicChatRepository
        ? (repository as HttpMagicChatRepository).baseUri.toString()
        : null;
    final uri =
        contact == null ? null : _resolveAssetUri(serverUrl, contact.avatar);
    final label = (_contactName(contact) ?? fallback).trim();
    return CachedAvatar(
        repository: repository,
        cacheScope: cacheScope,
        avatarUri: uri,
        name: label,
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer);
  }

  Future<void> _showContactPanel(BuildContext context, Contact contact) async {
    final name = _contactName(contact) ?? contact.displayName;
    final fields = <({String label, String value})>[
      if (contact.name.trim().isNotEmpty && contact.name.trim() != name)
        (label: '姓名', value: contact.name.trim()),
      if (contact.nickname.trim().isNotEmpty && contact.nickname.trim() != name)
        (label: '昵称', value: contact.nickname.trim()),
      if (contact.email.trim().isNotEmpty)
        (label: '邮箱', value: contact.email.trim()),
      if (contact.phone.trim().isNotEmpty)
        (label: '手机', value: contact.phone.trim()),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _avatar(context, contact, name),
              const SizedBox(height: 10),
              Text(name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              if (contact.id.trim().isNotEmpty && contact.id.trim() != name)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(contact.id,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 16),
                ...fields.map((field) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(
                            width: 48,
                            child: Text(field.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant))),
                        const SizedBox(width: 12),
                        Expanded(child: Text(field.value)),
                      ]),
                    )),
              ],
              const SizedBox(height: 12),
              Text(contact.online ? '在线' : '离线',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: contact.online
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReactionUsers(
      BuildContext context, MessageReaction reaction) async {
    try {
      final users = await repository
          .listReactionUsers(conversationId, message.id, text: reaction.text);
      if (!context.mounted) return;
      final contacts =
          contactsFuture == null ? const <Contact>[] : await contactsFuture!;
      if (!context.mounted) return;
      final names = {
        for (final contact in contacts) contact.id: contact.displayName
      };
      await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
                child: users.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('暂无参与者')))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                              child: Text('${reaction.text} 参与者',
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                          ...users.map((user) {
                            final name = user.name.isNotEmpty
                                ? user.name
                                : names[user.id]?.isNotEmpty == true
                                    ? names[user.id]!
                                    : user.id;
                            return ListTile(
                                leading: CircleAvatar(
                                    child: Text(name.isEmpty
                                        ? '?'
                                        : name.substring(0, 1))),
                                title: Text(name));
                          }),
                        ],
                      ),
              ));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载表情参与者失败：$error')));
      }
    }
  }
}

class _CachedConversationImage extends StatefulWidget {
  const _CachedConversationImage({
    required this.repository,
    required this.cacheScope,
    required this.fileId,
    required this.onTap,
  });

  final MagicChatRepository repository;
  final MessageCacheScope? cacheScope;
  final String fileId;
  final ValueChanged<_CachedImageData?> onTap;

  @override
  State<_CachedConversationImage> createState() =>
      _CachedConversationImageState();
}

class _CachedConversationImageState extends State<_CachedConversationImage> {
  final _cache = LocalAssetCache();
  Future<_CachedImageData?>? _future;

  String get _cacheKey {
    final scope = widget.cacheScope;
    final owner = scope == null ? '' : '${scope.serverUrl}|${scope.userId}|';
    return 'attachment|$owner${widget.fileId}';
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _CachedConversationImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId ||
        oldWidget.cacheScope != widget.cacheScope) {
      _future = _load();
    }
  }

  Future<_CachedImageData?> _load() async {
    Uint8List? cached;
    try {
      cached = await _cache.read(_cacheKey);
    } catch (_) {
      cached = null;
    }
    if (cached != null) return _CachedImageData(bytes: cached);
    Uri? uri;
    try {
      uri = await widget.repository.attachmentUrl(widget.fileId);
    } catch (_) {
      uri = null;
    }
    Uint8List? bytes;
    if (uri != null) {
      try {
        bytes = await widget.repository.downloadResource(uri);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null) {
      try {
        bytes = await widget.repository.downloadAttachment(widget.fileId);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await _cache.write(_cacheKey, bytes);
      } catch (_) {
        // 图片已经在内存中，缓存目录不可写不阻断当前消息显示。
      }
    }
    return _CachedImageData(bytes: bytes, uri: uri);
  }

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 100;
    final width = available.clamp(180.0, 320.0).toDouble();
    return FutureBuilder<_CachedImageData?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final bytes = data?.bytes;
        final child = snapshot.connectionState == ConnectionState.waiting
            ? const CircularProgressIndicator(strokeWidth: 2)
            : data == null || bytes == null
                ? GestureDetector(
                    onTap: () => widget.onTap(null),
                    child: data?.uri == null
                        ? const Text('图片暂时无法加载')
                        : Image.network(data!.uri.toString(),
                            width: width,
                            height: 240,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('图片暂时无法加载')))
                : GestureDetector(
                    onTap: () => widget.onTap(data),
                    child: Image.memory(bytes,
                        width: width,
                        height: 240,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('图片暂时无法加载')),
                  );
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: width,
            height: 240,
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _CachedImageData {
  const _CachedImageData({required this.bytes, this.uri});

  final Uint8List? bytes;
  final Uri? uri;
}
