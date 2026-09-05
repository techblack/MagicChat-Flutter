part of '../../main.dart';

String? formatMessageTime(String value, {DateTime? now}) {
  final parsed = DateTime.tryParse(value.trim());
  if (parsed == null) return null;
  final local = parsed.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final sameDay = local.year == current.year &&
      local.month == current.month &&
      local.day == current.day;
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final time = '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  if (sameDay) return time;
  final date = '${twoDigits(local.month)}-${twoDigits(local.day)}';
  return local.year == current.year
      ? '$date $time'
      : '${local.year}-$date $time';
}

enum _OptimisticMessageKind { text, image, file, voice }

enum _OptimisticMessageStatus { sending, failed }

class _OptimisticSendDescriptor {
  const _OptimisticSendDescriptor({
    required this.clientMessageId,
    required this.kind,
    this.text = '',
    this.upload,
    this.replyTo,
    this.durationMs = 0,
    this.sizeBytes,
  });

  final String clientMessageId;
  final _OptimisticMessageKind kind;
  final String text;
  final AttachmentUpload? upload;
  final MessageReply? replyTo;
  final int durationMs;
  final int? sizeBytes;

  ChatMessage toMessage(String conversationId, int sequence) {
    final contentType = kind.name;
    final localFileId = 'optimistic:$clientMessageId';
    final body = switch (kind) {
      _OptimisticMessageKind.text => <String, dynamic>{
          'type': 'text',
          'content': text
        },
      _OptimisticMessageKind.image => <String, dynamic>{
          'type': 'image',
          'file_id': localFileId,
          'name': upload?.name ?? '图片',
        },
      _OptimisticMessageKind.file => <String, dynamic>{
          'type': 'file',
          'file_id': localFileId,
          'name': upload?.name ?? '文件',
          if (sizeBytes != null) 'size_bytes': sizeBytes,
        },
      _OptimisticMessageKind.voice => <String, dynamic>{
          'type': 'voice',
          'file_id': localFileId,
          'duration_ms': durationMs,
          'transcript': text,
        },
    };
    return ChatMessage(
      id: localFileId,
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      sequence: sequence,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      contentType: contentType,
      rawBody: body,
      text: switch (kind) {
        _OptimisticMessageKind.text => text,
        _OptimisticMessageKind.image => '[图片]',
        _OptimisticMessageKind.file => '[文件] ${upload?.name ?? ''}'.trim(),
        _OptimisticMessageKind.voice => '[语音]',
      },
      author: '我',
      mine: true,
      replyTo: replyTo,
    );
  }
}

class _OptimisticMessage {
  _OptimisticMessage({
    required this.descriptor,
    required this.message,
  }) : status = _OptimisticMessageStatus.sending;

  final _OptimisticSendDescriptor descriptor;
  final ChatMessage message;
  _OptimisticMessageStatus status;
}

class ConversationView extends StatefulWidget {
  const ConversationView(
      {required this.repository,
      this.realtimeSession,
      this.realtimeStore,
      this.cacheScope,
      this.messageCacheStore,
      this.sendMessageShortcut = MessageSendShortcut.enter,
      this.enableFileDrop = true,
      required this.conversationId,
      this.focusMessageId,
      this.focusMessageSequence,
      this.onOpenConversation,
      this.onOpenInternalLink,
      this.onMessageFocused,
      super.key});
  final MagicChatRepository repository;
  final RealtimeSession? realtimeSession;
  final RealtimeStore? realtimeStore;
  final MessageCacheScope? cacheScope;
  final MessageCacheStore? messageCacheStore;
  final MessageSendShortcut sendMessageShortcut;
  final bool enableFileDrop;
  final String? conversationId;
  final String? focusMessageId;
  final int? focusMessageSequence;
  final ValueChanged<String>? onOpenConversation;
  final ValueChanged<String>? onOpenInternalLink;
  final VoidCallback? onMessageFocused;
  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView>
    with WidgetsBindingObserver {
  static const _maxSelectedMessages = 50;
  static const _maxForwardTargets = 20;
  static const _messageTapSlop = 18.0;
  static const _messageDoubleTapMax = Duration(milliseconds: 400);
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
  Future<List<ChatMessage>>? _messagesFuture;
  MessagePage? _messagePage;
  late final MessageCacheStore _messageCacheStore =
      widget.messageCacheStore ?? MessageCacheStore();
  late final bool _ownsMessageCacheStore = widget.messageCacheStore == null;
  bool _sendingFile = false;
  bool _draggingFile = false;
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
  final _preloadedImages = <String, _CachedImageData>{};
  final _preloadedAttachmentUrls = <String, Uri>{};
  final _replyTargetsById = <String, ChatMessage>{};
  final _optimisticMessages = <String, _OptimisticMessage>{};
  final _optimisticSendsInFlight = <String>{};
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
  String? _lastTappedMessageId;
  Duration? _lastMessageTapTime;
  Offset? _lastMessageTapPosition;
  Offset? _messagePointerDownPosition;
  bool _messagePointerMoved = false;
  Timer? _typingHeartbeat;
  bool _typingStatusInFlight = false;

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
  /// 话题消息本身的类型是 `topic`，需要沿用其父会话类型判断是否支持
  /// 一对一输入状态。
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

  bool get _supportsTypingStatus =>
      _conversationKind == 'direct' || _conversationKind == 'app';

  bool _canForwardOrSelect(ChatMessage message) =>
      _forwardableMessageTypes.contains(message.contentType);

  bool _hasMessageActions(ChatMessage message) =>
      message.contentType != 'revoked' &&
      message.contentType != 'unsupported' &&
      message.contentType != 'system_event';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final id = widget.conversationId;
    if (id != null) _conversation = widget.realtimeStore?.conversations[id];
    _historyMode = widget.focusMessageId != null;
    _messagesFuture = _loadMessages();
    _contactsFuture = _loadConversationContacts();
    _seenRealtimeMessageIds.addAll(_realtimeConversationMessages());
    _scrollController.addListener(_onScroll);
    _controller.addListener(_persistDraft);
    _composerFocusNode.addListener(_onComposerFocusChanged);
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
      setState(() {
        _contactsFuture = Future.value(fresh);
      });
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
    if (_composerFocusNode.hasFocus) _startTypingHeartbeat();
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
      clientMessageId: value['client_message_id'] is String
          ? value['client_message_id'] as String
          : null,
      author:
          cachedAuthor.isEmpty || cachedAuthor == '用户' ? '成员' : cachedAuthor,
      authorId: authorId,
      conversationId: value['conversation_id'] as String?,
      sequence: (value['sequence'] as num?)?.toInt(),
      createdAt:
          value['created_at'] is String ? value['created_at'] as String : '',
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
      replyTo:
          reply is Map<String, dynamic> ? _cachedReplyFromJson(reply) : null,
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

  MessageReply? _cachedReplyFromJson(Map<String, dynamic> value) {
    try {
      return MessageReply.fromJson(value);
    } on FormatException {
      return null;
    }
  }

  Future<void> _cacheMessages(String id, List<ChatMessage> messages) async {
    final scope = widget.cacheScope;
    if (scope == null) return;
    await _messageCacheStore.write(
        scope, id, messages.map(messageCacheRecord).toList(),
        conversationType: _messageCacheConversationType);
  }

  Future<List<ChatMessage>> _readCachedMessages(String id) async {
    final scope = widget.cacheScope;
    if (scope == null) return const [];
    final records = await _messageCacheStore.read(scope, id,
        conversationType: _messageCacheConversationType);
    return records.map(_messageFromCache).whereType<ChatMessage>().toList();
  }

  String get _messageCacheConversationType {
    final id = widget.conversationId;
    final type = (_conversation ??
            (id == null ? null : widget.realtimeStore?.conversations[id]))
        ?.type;
    return messageCacheConversationTypes.contains(type) ? type! : 'direct';
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
      await _preloadReplyTargets(id, history);
      await _preloadComplexMessages(id, history);
      unawaited(_refreshMessageSnapshots(id, history));
      return history;
    }
    final cached = await _readCachedMessages(id);
    if (cached.isNotEmpty) {
      await _preloadReplyTargets(id, cached);
      await _preloadComplexMessages(id, cached);
      unawaited(_refreshMessages(id));
      return cached;
    }
    final fresh = await widget.repository.messages(id);
    _messagePage = fresh is MessagePage ? fresh : null;
    _hasMoreOlder = _messagePage?.hasMoreBefore ?? true;
    _lastOlderBeforeSeq = null;
    await _preloadReplyTargets(id, fresh);
    await _preloadComplexMessages(id, fresh);
    try {
      await _cacheMessages(id, fresh);
    } catch (_) {
      // 首次缓存失败不阻断远程消息展示。
    }
    // 消息接口返回的 choice/reaction 可能来自旧缓存或断线前的视图；
    // 快照查询是尽力而为的后台修正，失败时不影响消息首屏加载。
    unawaited(_refreshMessageSnapshots(id, fresh));
    return fresh;
  }

  Future<void> _preloadReplyTargets(
      String conversationId, List<ChatMessage> messages) async {
    final known = <String, ChatMessage>{
      ..._replyTargetsById,
      for (final message in _olderMessages) message.id: message,
      for (final message in messages) message.id: message,
    };
    final unresolved = <String, int?>{};
    for (final message in messages) {
      final reply = message.replyTo;
      if (reply == null || known.containsKey(reply.id)) continue;
      final summary = reply.text.trim();
      final needsContent = summary.isEmpty ||
          summary == '[消息]' ||
          summary.toLowerCase() == reply.id.toLowerCase();
      if (needsContent) unresolved[reply.id] = reply.sequence;
    }
    if (unresolved.isEmpty) return;
    final targets = await Future.wait(unresolved.entries
        .where((entry) => entry.value != null)
        .map((entry) async {
      try {
        final values = await widget.repository
            .messages(conversationId, beforeSeq: entry.value! + 1, limit: 1)
            .timeout(const Duration(seconds: 5));
        return values.where((message) => message.id == entry.key).firstOrNull;
      } catch (_) {
        return null;
      }
    }));
    if (!mounted || widget.conversationId != conversationId) return;
    for (final target in targets.whereType<ChatMessage>()) {
      _replyTargetsById[target.id] = target;
      unresolved.remove(target.id);
    }

    // 某些旧服务端只返回引用 ID，不返回引用序号。引用通常指向当前页
    // 之前的消息，按已知最早序号向前翻页，最多补齐 8 页，避免为了一个
    // 引用无限读取历史；成功后首屏直接使用原消息正文。
    if (unresolved.isNotEmpty) {
      var before = [...known.values, ...targets.whereType<ChatMessage>()]
          .map((message) => message.sequence)
          .whereType<int>()
          .fold<int?>(
              null, (value, seq) => value == null || seq < value ? seq : value);
      for (var page = 0;
          page < 8 && unresolved.isNotEmpty && before != null && before > 1;
          page++) {
        try {
          final history = await widget.repository
              .messages(conversationId, beforeSeq: before, limit: 50)
              .timeout(const Duration(seconds: 5));
          if (history.isEmpty) break;
          for (final target in history) {
            if (unresolved.containsKey(target.id)) {
              unresolved.remove(target.id);
              _replyTargetsById[target.id] = target;
            }
          }
          final nextBefore = history
              .map((message) => message.sequence)
              .whereType<int>()
              .fold<int?>(null,
                  (value, seq) => value == null || seq < value ? seq : value);
          if (nextBefore == null || nextBefore >= before) break;
          before = nextBefore;
          if (history is MessagePage && !history.hasMoreBefore) break;
        } catch (_) {
          break;
        }
      }
    }
  }

  /// 在消息列表首次布局前准备会改变高度或需要网络资源的消息内容。
  /// 这样首屏不会先绘制占位控件，再因附件/图片完成加载而整体位移。
  Future<void> _preloadComplexMessages(
      String conversationId, List<ChatMessage> messages) async {
    final imageIds = <String>{};
    final attachmentIds = <String>{};
    for (final message in messages) {
      final fileId = message.rawBody['file_id'];
      if (fileId is! String || fileId.isEmpty) continue;
      if (message.contentType == 'image') {
        imageIds.add(fileId);
      } else if (message.contentType == 'file') {
        attachmentIds.add(fileId);
      }
    }
    if (imageIds.isEmpty && attachmentIds.isEmpty) return;

    await Future.wait([
      ...imageIds.map((fileId) async {
        final data = await _loadCachedConversationImage(
          repository: widget.repository,
          cacheScope: widget.cacheScope,
          fileId: fileId,
        ).timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (mounted &&
            widget.conversationId == conversationId &&
            data?.bytes != null) {
          _preloadedImages[fileId] = data!;
        }
      }),
      ...attachmentIds.map((fileId) async {
        try {
          final uri = await widget.repository
              .attachmentUrl(fileId)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          if (mounted &&
              widget.conversationId == conversationId &&
              uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https')) {
            _preloadedAttachmentUrls[fileId] = uri;
          }
        } catch (_) {
          // 预加载失败时保留原有消息，点击附件仍会再次尝试加载。
        }
      }),
    ]);
    if (!mounted || widget.conversationId != conversationId) return;
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
    await _preloadReplyTargets(id, merged);
    await _preloadComplexMessages(id, merged);
    try {
      await _cacheMessages(id, merged);
    } catch (_) {
      // 刷新结果仍应展示；缓存会在后续实时事件或刷新时重试。
    }
    if (!mounted || widget.conversationId != id) return;
    setState(() {
      _removeConfirmedOptimisticMessages(merged);
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
        clientMessageId: message.clientMessageId,
        text: message.text,
        author: message.author,
        authorId: message.authorId,
        conversationId: message.conversationId,
        sequence: message.sequence,
        createdAt: message.createdAt,
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
    try {
      await _cacheMessages(conversationId, updated);
    } catch (_) {
      // 快照修正即使无法持久化也应更新当前页面。
    }
    if (!mounted || widget.conversationId != conversationId) return;
    setState(() {
      _messagesFuture = Future.value(updated);
    });
    if (keepBottom) {
      _correctLatestPosition(conversationId,
          force: true, expectedOffset: offset);
    }
  }

  void _removeConfirmedOptimisticMessages(Iterable<ChatMessage> messages) {
    final confirmedIds = messages
        .map((message) => message.clientMessageId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    if (confirmedIds.isEmpty) return;
    _optimisticMessages.removeWhere(
        (clientMessageId, _) => confirmedIds.contains(clientMessageId));
  }

  bool _optimisticMessageIsConfirmed(String clientMessageId) {
    if (_visibleMessages
        .any((message) => message.clientMessageId == clientMessageId)) {
      return true;
    }
    return widget.realtimeStore?.messages.values
            .any((message) => message.clientMessageId == clientMessageId) ==
        true;
  }

  void _onRealtimeChanged() {
    final id = widget.conversationId;
    final current = id == null ? null : widget.realtimeStore?.conversations[id];
    if (!mounted) return;
    final realtimeMessages = id == null
        ? const <ChatMessage>[]
        : widget.realtimeStore?.messages.values
                .where((message) => message.conversationId == id)
                .toList(growable: false) ??
            const <ChatMessage>[];
    final confirmedOptimisticIds = realtimeMessages
        .map((message) => message.clientMessageId)
        .whereType<String>()
        .where(_optimisticMessages.containsKey)
        .toSet();
    final unseenIds = _realtimeConversationMessages()
        .where((messageId) => !_seenRealtimeMessageIds.contains(messageId))
        .toList(growable: false);
    _seenRealtimeMessageIds.addAll(unseenIds);
    final incomingIds = unseenIds
        .where((messageId) =>
            widget.realtimeStore?.messages[messageId]?.mine != true)
        .toList(growable: false);
    if (realtimeMessages.isNotEmpty) {
      // 实时事件也可能只有 reply_to_message_id；在下一帧绘制前尽力补齐
      // 引用原文，避免先短暂显示消息 ID/占位文本。
      unawaited(_preloadReplyTargets(id ?? '', realtimeMessages));
    }
    final shouldShowNewMessages = incomingIds.isNotEmpty &&
        (_historyMode || (_positionedConversationId == id && !_isAtBottom()));
    if (current == null &&
        !shouldShowNewMessages &&
        confirmedOptimisticIds.isEmpty) return;
    final canSend = current == null
        ? _canSend
        : current.canSend && current.topic?.archived != true;
    setState(() {
      _optimisticMessages.removeWhere((clientMessageId, _) =>
          confirmedOptimisticIds.contains(clientMessageId));
      if (current != null) {
        _conversation = current;
        _canSend = current.canSend;
      }
      if (shouldShowNewMessages) {
        _pendingNewMessageCount += incomingIds.length;
      }
      if (!canSend) _replyTo = null;
    });
    if (!canSend) _stopTypingHeartbeat();
  }

  void _onComposerFocusChanged() {
    if (_composerFocusNode.hasFocus) {
      _startTypingHeartbeat();
    } else {
      _stopTypingHeartbeat();
    }
  }

  void _startTypingHeartbeat() {
    _typingHeartbeat?.cancel();
    _typingHeartbeat = null;
    final conversationId = widget.conversationId;
    if (!_composerFocusNode.hasFocus ||
        conversationId == null ||
        widget.realtimeSession == null ||
        !_supportsTypingStatus ||
        !_conversationCanSend(conversationId)) {
      return;
    }
    unawaited(_sendTypingStatus());
    _typingHeartbeat = Timer.periodic(
        const Duration(seconds: 3), (_) => unawaited(_sendTypingStatus()));
  }

  void _stopTypingHeartbeat() {
    _typingHeartbeat?.cancel();
    _typingHeartbeat = null;
  }

  Future<void> _sendTypingStatus() async {
    final conversationId = widget.conversationId;
    final realtime = widget.realtimeSession;
    if (_typingStatusInFlight ||
        conversationId == null ||
        realtime == null ||
        !realtime.ready ||
        !_composerFocusNode.hasFocus ||
        !_supportsTypingStatus ||
        !_conversationCanSend(conversationId)) {
      return;
    }
    _typingStatusInFlight = true;
    try {
      await realtime.sendRequest('conversation.status', {
        'conversation_id': conversationId,
        'status': '正在输入',
      });
    } catch (_) {
      // 状态心跳失败不影响消息输入，下一个周期会自动重试。
    } finally {
      _typingStatusInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTypingHeartbeat();
    } else {
      _stopTypingHeartbeat();
    }
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
        await _preloadReplyTargets(id, added);
        await _preloadComplexMessages(id, added);
        if (!mounted || widget.conversationId != id) return;
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
      _stopTypingHeartbeat();
      _composerFocusNode.unfocus();
      _highlightTimer?.cancel();
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
      _preloadedImages.clear();
      _preloadedAttachmentUrls.clear();
      _replyTargetsById.clear();
      _optimisticMessages.clear();
      _optimisticSendsInFlight.clear();
      _seenRealtimeMessageIds
        ..clear()
        ..addAll(_realtimeConversationMessages());
      _replyTo = null;
      _draggingFile = false;
      _conversation = null;
      _topicDetail = null;
      _messagePage = null;
      _canSend = true;
      _messagesFuture = _loadMessages();
      _contactsFuture = _loadConversationContacts();
      _controller.clear();
      unawaited(_restoreDraft());
    }
    if (oldWidget.realtimeSession != widget.realtimeSession &&
        oldWidget.conversationId == widget.conversationId &&
        _composerFocusNode.hasFocus) {
      _startTypingHeartbeat();
    }
    if (oldWidget.enableFileDrop && !widget.enableFileDrop) {
      _draggingFile = false;
    }
    if (oldWidget.cacheScope != widget.cacheScope) {
      _olderMessages.clear();
      _hasMoreOlder = true;
      _lastOlderBeforeSeq = null;
      _messagePage = null;
      _preloadedImages.clear();
      _preloadedAttachmentUrls.clear();
      _replyTargetsById.clear();
      _optimisticMessages.clear();
      _optimisticSendsInFlight.clear();
      _draggingFile = false;
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
    WidgetsBinding.instance.removeObserver(this);
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _stopTypingHeartbeat();
    _readRetryTimer?.cancel();
    _highlightTimer?.cancel();
    _persistDraft();
    _controller.removeListener(_persistDraft);
    _composerFocusNode.removeListener(_onComposerFocusChanged);
    _controller.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    if (_ownsMessageCacheStore) unawaited(_messageCacheStore.close());
    super.dispose();
  }

  KeyEventResult _handleComposerKeyEvent(
      KeyEvent event, String conversationId) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final controlOrMeta = keyboard.isControlPressed || keyboard.isMetaPressed;
    final hasOtherModifier = keyboard.isShiftPressed || keyboard.isAltPressed;
    final shouldSend = switch (widget.sendMessageShortcut) {
      MessageSendShortcut.enter => !controlOrMeta && !hasOtherModifier,
      MessageSendShortcut.commandOrControlEnter =>
        controlOrMeta && !hasOtherModifier,
    };
    if (!shouldSend) return KeyEventResult.ignored;
    unawaited(_sendMessage(conversationId));
    return KeyEventResult.handled;
  }

  void _enqueueOptimisticMessage(
      String conversationId, _OptimisticSendDescriptor descriptor) {
    if (!mounted || widget.conversationId != conversationId) return;
    final newestSequence = [
      ..._visibleMessages.map((message) => message.sequence ?? 0),
      ..._optimisticMessages.values.map((item) => item.message.sequence ?? 0),
    ].fold<int>(0, max);
    final item = _OptimisticMessage(
      descriptor: descriptor,
      message: descriptor.toMessage(conversationId, newestSequence + 1),
    );
    setState(() {
      _optimisticMessages[descriptor.clientMessageId] = item;
      _replyTo = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.conversationId != conversationId ||
          !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
    unawaited(_performOptimisticSend(conversationId, descriptor));
  }

  Future<void> _performOptimisticSend(
      String conversationId, _OptimisticSendDescriptor descriptor) async {
    final clientMessageId = descriptor.clientMessageId;
    if (!_optimisticSendsInFlight.add(clientMessageId)) return;
    final current = _optimisticMessages[clientMessageId];
    if (current != null && current.status != _OptimisticMessageStatus.sending) {
      setState(() => current.status = _OptimisticMessageStatus.sending);
    }
    var sent = false;
    try {
      switch (descriptor.kind) {
        case _OptimisticMessageKind.text:
          await widget.repository.sendMessage(
            conversationId,
            descriptor.text,
            replyToMessageId: descriptor.replyTo?.id,
            clientMessageId: clientMessageId,
          );
          break;
        case _OptimisticMessageKind.image:
          await widget.repository.sendImage(
            conversationId,
            descriptor.upload!,
            replyToMessageId: descriptor.replyTo?.id,
            clientMessageId: clientMessageId,
          );
          break;
        case _OptimisticMessageKind.file:
          await widget.repository.sendFile(
            conversationId,
            descriptor.upload!,
            replyToMessageId: descriptor.replyTo?.id,
            clientMessageId: clientMessageId,
          );
          break;
        case _OptimisticMessageKind.voice:
          await widget.repository.sendVoice(
            conversationId,
            descriptor.upload!,
            transcript: descriptor.text,
            durationMs: descriptor.durationMs,
            replyToMessageId: descriptor.replyTo?.id,
            clientMessageId: clientMessageId,
          );
          break;
      }
      sent = true;
    } catch (_) {
      if (mounted &&
          widget.conversationId == conversationId &&
          !_optimisticMessageIsConfirmed(clientMessageId)) {
        final failed = _optimisticMessages[clientMessageId];
        if (failed != null) {
          setState(() => failed.status = _OptimisticMessageStatus.failed);
        }
      }
    } finally {
      _optimisticSendsInFlight.remove(clientMessageId);
    }
    if (!sent || !mounted || widget.conversationId != conversationId) return;
    try {
      await _refreshMessages(conversationId);
    } catch (_) {
      // 消息已经发送成功，刷新失败时继续等待实时事件按客户端消息 ID 确认。
    }
  }

  void _retryOptimisticMessage(String clientMessageId) {
    final conversationId = widget.conversationId;
    final item = _optimisticMessages[clientMessageId];
    if (conversationId == null || item == null) return;
    unawaited(_performOptimisticSend(conversationId, item.descriptor));
  }

  Future<void> _showVoiceComposer(String conversationId) async {
    if (!_conversationCanSend(conversationId)) return;
    _composerFocusNode.unfocus();
    final repository = widget.repository;
    VoiceTranscriberFactory? transcriberFactory;
    if (repository is HttpMagicChatRepository) {
      transcriberFactory = () => AsrRealtimeClient(
            serverUrl: repository.baseUri.toString(),
            sessionToken: repository.sessionToken,
            connector: connectWithAuthorization,
          );
    }
    final result = await showModalBottomSheet<VoiceComposerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          VoiceMessageComposerSheet(transcriberFactory: transcriberFactory),
    );
    if (!mounted || result == null || !_conversationCanSend(conversationId)) {
      return;
    }
    if (result.kind == VoiceComposerResultKind.text) {
      _enqueueOptimisticMessage(
        conversationId,
        _OptimisticSendDescriptor(
          clientMessageId: newMessageClientId(),
          kind: _OptimisticMessageKind.text,
          text: result.text,
          replyTo: _replyTo,
        ),
      );
      return;
    }
    final recording = result.recording!;
    _enqueueOptimisticMessage(
      conversationId,
      _OptimisticSendDescriptor(
        clientMessageId: newMessageClientId(),
        kind: _OptimisticMessageKind.voice,
        upload: AttachmentUpload(
          path: '',
          name: recording.name,
          mimeType: recording.mimeType,
          bytes: recording.bytes,
        ),
        text: result.text,
        durationMs: recording.durationMs,
        sizeBytes: recording.bytes.length,
        replyTo: _replyTo,
      ),
    );
  }

  bool _canReplyToMessage(String conversationId, ChatMessage message) =>
      _topicIsOpen(conversationId) &&
      !_isTopicConversation &&
      message.topic == null &&
      _hasMessageActions(message);

  void _replyToMessage(String conversationId, ChatMessage message) {
    if (!_canReplyToMessage(conversationId, message)) return;
    setState(() => _replyTo = MessageReply(
        id: message.id,
        author: message.author,
        authorId: message.authorId,
        text: message.text));
    _composerFocusNode.requestFocus();
  }

  String _messageDetailsText(ChatMessage message, List<Contact> contacts) {
    final labels = contacts.map((contact) => (
          id: contact.id,
          name: contact.displayName,
        ));
    if (message.contentType == 'image') {
      final caption = message.rawBody['caption'];
      return caption is String && caption.trim().isNotEmpty
          ? formatMentionText(caption.trim(), labels)
          : '图片消息';
    }
    if (message.contentType == 'object' || message.contentType == 'chart') {
      return const JsonEncoder.withIndent('  ').convert(message.rawBody);
    }
    return formatMentionText(message.text, labels);
  }

  Future<void> _showMessageDetails(ChatMessage message) async {
    List<Contact> contacts;
    try {
      contacts = await (_contactsFuture ?? Future.value(const <Contact>[]));
    } catch (_) {
      contacts = const [];
    }
    if (!mounted) return;
    final content = _messageDetailsText(message, contacts);
    final authorContact =
        contacts.where((contact) => contact.id == message.authorId).firstOrNull;
    final author = authorContact?.displayName ??
        (message.author == message.authorId ? '成员' : message.author);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('消息详情'),
            leading: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close)),
            actions: [
              IconButton(
                  tooltip: '复制全部',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                          const SnackBar(content: Text('消息已复制')));
                    }
                  },
                  icon: const Icon(Icons.copy_outlined)),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(author,
                    style: Theme.of(dialogContext).textTheme.titleMedium),
                if (formatMessageTime(message.createdAt) case final time?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 16),
                    child: Text(time,
                        style: Theme.of(dialogContext).textTheme.bodySmall),
                  )
                else
                  const SizedBox(height: 16),
                SelectableText(content,
                    key: const ValueKey('message-details-content')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onMessagePointerDown(PointerDownEvent event) {
    _messagePointerDownPosition = event.position;
    _messagePointerMoved = false;
  }

  void _onMessagePointerMove(PointerMoveEvent event) {
    final origin = _messagePointerDownPosition;
    if (origin != null &&
        (event.position - origin).distance > _messageTapSlop) {
      _messagePointerMoved = true;
    }
  }

  void _onMessagePointerUp(PointerUpEvent event, ChatMessage message) {
    if (_messagePointerMoved || _selectedMessageIds.isNotEmpty) {
      _lastTappedMessageId = null;
      _lastMessageTapTime = null;
      _lastMessageTapPosition = null;
      return;
    }
    final previous = _lastMessageTapTime;
    final previousPosition = _lastMessageTapPosition;
    final elapsed = previous == null ? null : event.timeStamp - previous;
    if (_lastTappedMessageId == message.id &&
        elapsed != null &&
        previousPosition != null &&
        (event.position - previousPosition).distance <= _messageTapSlop &&
        elapsed >= Duration.zero &&
        elapsed <= _messageDoubleTapMax) {
      _lastTappedMessageId = null;
      _lastMessageTapTime = null;
      _lastMessageTapPosition = null;
      unawaited(_showMessageDetails(message));
      return;
    }
    _lastTappedMessageId = message.id;
    _lastMessageTapTime = event.timeStamp;
    _lastMessageTapPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = widget.conversationId;
    if (conversationId == null) return const _ConversationEmptyState();
    final canSend = _conversationCanSend(conversationId);
    final activeConversation =
        _conversation ?? widget.realtimeStore?.conversations[conversationId];
    final announcement = activeConversation?.type == 'group'
        ? activeConversation!.announcement.trim()
        : '';
    final content = Column(
      children: [
        if (_topicDetail != null)
          TopicSourceBanner(
              detail: _topicDetail!, contactsFuture: _contactsFuture),
        if (announcement.isNotEmpty)
          ConversationAnnouncement(announcement: announcement),
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
                  final confirmedById = <String, ChatMessage>{};
                  for (final message in [..._olderMessages, ...messages]) {
                    confirmedById[message.id] = message;
                  }
                  final confirmedMessages = confirmedById.values.toList();
                  final confirmedClientIds = confirmedMessages
                      .map((message) => message.clientMessageId)
                      .whereType<String>()
                      .toSet();
                  final optimisticByMessageId = <String, _OptimisticMessage>{
                    for (final item in _optimisticMessages.values)
                      if (!confirmedClientIds
                          .contains(item.descriptor.clientMessageId))
                        item.message.id: item,
                  };
                  final allMessages = [
                    ...confirmedMessages,
                    ...optimisticByMessageId.values.map((item) => item.message),
                  ]..sort((left, right) {
                      final leftSeq = left.sequence;
                      final rightSeq = right.sequence;
                      if (leftSeq == null && rightSeq == null) return 0;
                      if (leftSeq == null) return 1;
                      if (rightSeq == null) return -1;
                      return leftSeq.compareTo(rightSeq);
                    });
                  _visibleMessages = confirmedMessages;
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
                      children: allMessages.map((message) {
                        final optimistic = optimisticByMessageId[message.id];
                        if (optimistic != null) {
                          return Align(
                            key: _messageKey(message.id),
                            alignment: Alignment.centerRight,
                            child: _OptimisticMessageBubble(
                              item: optimistic,
                              contactsFuture: _contactsFuture,
                              onRetry: () => _retryOptimisticMessage(
                                  optimistic.descriptor.clientMessageId),
                            ),
                          );
                        }
                        return Align(
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
                                        _selectedMessageIds.add(message.id);
                                      }
                                    }),
                            onLongPress: () {
                              if (_selectedMessageIds.isNotEmpty) {
                                if (!_canForwardOrSelect(message)) return;
                                if (_selectedMessageIds.length >=
                                    _maxSelectedMessages) return;
                                setState(
                                    () => _selectedMessageIds.add(message.id));
                              } else if (_hasMessageActions(message)) {
                                _showMessageActions(conversationId, message);
                              }
                            },
                            child: Listener(
                              onPointerDown: _onMessagePointerDown,
                              onPointerMove: _onMessagePointerMove,
                              onPointerUp: (event) =>
                                  _onMessagePointerUp(event, message),
                              child: Dismissible(
                                key: ValueKey('message-swipe-${message.id}'),
                                direction:
                                    _canReplyToMessage(conversationId, message)
                                        ? DismissDirection.endToStart
                                        : DismissDirection.none,
                                resizeDuration: null,
                                dismissThresholds: const {
                                  DismissDirection.endToStart: .25,
                                },
                                confirmDismiss: (_) async {
                                  _replyToMessage(conversationId, message);
                                  return false;
                                },
                                background: const SizedBox.shrink(),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 18),
                                  child: const Icon(Icons.reply),
                                ),
                                child: Container(
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
                                        replyTarget:
                                            confirmedById[message.replyTo?.id] ??
                                                _replyTargetsById[
                                                    message.replyTo?.id],
                                        repository: widget.repository,
                                        conversationId: conversationId,
                                        galleryMessages: confirmedMessages,
                                        galleryHasOlder: _hasMoreOlder,
                                        canReact: _topicIsOpen(conversationId),
                                        canRespond: canSend,
                                        onOpenTopic: widget.onOpenConversation,
                                        onOpenInternalLink:
                                            widget.onOpenInternalLink,
                                        onForwardMessage: (id) =>
                                            _showForwardDialog(
                                                conversationId, [id]),
                                        contactsFuture: _contactsFuture,
                                        onReeditMessage: _reeditMessage,
                                        cacheScope: widget.cacheScope,
                                        preloadedImages: _preloadedImages,
                                        preloadedAttachmentUrls:
                                            _preloadedAttachmentUrls)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: _loadingOlder
                        ? Semantics(
                            key: const ValueKey('older-messages-loading'),
                            label: '正在加载更早消息',
                            child: Material(
                              elevation: 1,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              shape: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('older-messages-idle')),
                  ),
                ),
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
          key: const ValueKey('message-composer-safe-area'),
          top: false,
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
                        child: FutureBuilder<List<Contact>>(
                          future: _contactsFuture,
                          builder: (context, snapshot) {
                            final contacts = snapshot.data ?? const <Contact>[];
                            final matched = contacts
                                .where((contact) =>
                                    contact.id == _replyTo!.authorId)
                                .firstOrNull;
                            final rawAuthor = _replyTo!.author.trim();
                            final author = matched?.displayName ??
                                (rawAuthor.isEmpty ||
                                        rawAuthor == _replyTo!.authorId ||
                                        rawAuthor == '用户' ||
                                        rawAuthor == '成员'
                                    ? '成员'
                                    : rawAuthor);
                            final text = formatMessageReferenceText(
                                _replyTo!.text,
                                contacts.map((contact) => (
                                      id: contact.id,
                                      name: contact.displayName,
                                    )),
                                messageId: _replyTo!.id);
                            return Text('回复 $author：$text',
                                maxLines: 1, overflow: TextOverflow.ellipsis);
                          },
                        ),
                      ),
                      IconButton(
                          tooltip: '取消回复',
                          onPressed: () => setState(() => _replyTo = null),
                          icon: const Icon(Icons.close, size: 18)),
                    ]),
                  ),
                // 输入框单独占一行，操作按钮放到下一行，窄屏不会再被挤压。
                Row(children: [
                  Expanded(
                      child: Focus(
                    onKeyEvent: (_, event) =>
                        _handleComposerKeyEvent(event, conversationId),
                    child: TextField(
                        controller: _controller,
                        focusNode: _composerFocusNode,
                        readOnly: !canSend,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: widget.sendMessageShortcut ==
                                MessageSendShortcut.enter
                            ? TextInputAction.send
                            : TextInputAction.newline,
                        onSubmitted: widget.sendMessageShortcut ==
                                MessageSendShortcut.enter
                            ? (_) => unawaited(_sendMessage(conversationId))
                            : null,
                        decoration: InputDecoration(
                            hintText: canSend ? '输入消息…' : '话题已关闭',
                            isDense: true)),
                  )),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(46, 46),
                        shape: const CircleBorder()),
                    tooltip: '发送',
                    onPressed:
                        !canSend ? null : () => _sendMessage(conversationId),
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
                      icon: const Icon(Icons.mic_none),
                      tooltip: '语音输入',
                      onPressed: !canSend || _sendingFile
                          ? null
                          : () => _showVoiceComposer(conversationId),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (!_supportsFileDrop) return content;
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final enabled = widget.enableFileDrop &&
        routeCurrent &&
        canSend &&
        !_sendingFile &&
        _selectedMessageIds.isEmpty;
    return DropTarget(
      key: const ValueKey('conversation-file-drop-target'),
      enable: enabled,
      onDragEntered: (_) {
        if (!_draggingFile) setState(() => _draggingFile = true);
      },
      onDragExited: (_) {
        if (_draggingFile) setState(() => _draggingFile = false);
      },
      onDragDone: (details) =>
          unawaited(_handleFileDrop(conversationId, details)),
      child: Stack(fit: StackFit.expand, children: [
        content,
        if (_draggingFile) const _ConversationFileDropOverlay(),
      ]),
    );
  }

  bool get _supportsFileDrop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> _copySelected() async {
    List<Contact> contacts;
    try {
      contacts = await (_contactsFuture ?? Future.value(const <Contact>[]));
    } catch (_) {
      contacts = const [];
    }
    final labels = contacts.map((contact) => (
          id: contact.id,
          name: contact.displayName,
        ));
    final text = _visibleMessages
        .where((message) => _selectedMessageIds.contains(message.id))
        .map((message) => formatMentionText(message.text, labels))
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
                            child: Text(contact.displayName.isEmpty
                                ? '?'
                                : contact.displayName.substring(0, 1))),
                        title: Text(contact.displayName),
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
    if (_sendingFile) return;
    setState(() => _sendingFile = true);
    try {
      final result = await FilePicker.pickFiles(withData: kIsWeb);
      final file = result?.files.single;
      if (!mounted ||
          file == null ||
          (file.path == null && file.bytes == null)) {
        if (mounted && result != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('当前平台无法读取所选文件')));
        }
        return;
      }
      if (file.size > 200 * 1024 * 1024) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件不能超过 200MiB')));
        return;
      }
      final upload = AttachmentUpload(
          path: file.path ?? '',
          name: file.name,
          mimeType: _mimeType(file.extension),
          bytes: file.bytes);
      _enqueueAttachment(conversationId, upload, file.size);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法读取附件：$error')));
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<void> _handleFileDrop(
      String conversationId, DropDoneDetails details) async {
    if (_draggingFile && mounted) setState(() => _draggingFile = false);
    if (_sendingFile || !_conversationCanSend(conversationId)) return;
    final file = details.files.firstOrNull;
    if (file == null) return;
    if (file is DropItemDirectory) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂不支持发送文件夹')));
      return;
    }

    setState(() => _sendingFile = true);
    final bookmark = file.extraAppleBookmark;
    var accessingScopedFile = false;
    try {
      if (bookmark?.isNotEmpty == true) {
        accessingScopedFile = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark!);
      }
      final size = await file.length();
      if (size > 200 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('文件不能超过 200MiB')));
        }
        return;
      }
      final rawName = file.name.trim();
      final name = rawName.isEmpty ? '附件' : rawName;
      final dot = name.lastIndexOf('.');
      final extension = dot < 0 ? null : name.substring(dot + 1);
      final inferredMimeType = _mimeType(extension);
      final providedMimeType = file.mimeType?.trim();
      final mimeType = providedMimeType == null ||
              providedMimeType.isEmpty ||
              providedMimeType == 'application/octet-stream'
          ? inferredMimeType
          : providedMimeType;
      final isImage = mimeType.startsWith('image/');
      final needsBytes = kIsWeb ||
          isImage ||
          file.path.isEmpty ||
          bookmark?.isNotEmpty == true;
      final bytes = needsBytes ? await file.readAsBytes() : null;
      final upload = AttachmentUpload(
          path: needsBytes ? '' : file.path,
          name: name,
          mimeType: mimeType,
          bytes: bytes);
      if (!mounted || widget.conversationId != conversationId) return;
      final confirmed = await _confirmDroppedAttachment(upload, size);
      if (confirmed == true &&
          mounted &&
          widget.conversationId == conversationId &&
          _conversationCanSend(conversationId)) {
        _enqueueAttachment(conversationId, upload, size);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法读取拖入文件：$error')));
      }
    } finally {
      if (accessingScopedFile && bookmark != null) {
        await DesktopDrop.instance
            .stopAccessingSecurityScopedResource(bookmark: bookmark);
      }
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<bool?> _confirmDroppedAttachment(AttachmentUpload upload, int size) {
    final isImage = upload.mimeType.startsWith('image/');
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isImage ? '发送图片' : '发送文件'),
        content: SizedBox(
          width: 400,
          child: isImage && upload.bytes != null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 360, maxHeight: 260),
                    child: Image.memory(upload.bytes!, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 12),
                  Text('${upload.name} · ${_formatAttachmentSize(size)}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ])
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined, size: 36),
                  title: Text(upload.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_formatAttachmentSize(size)),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.send_outlined),
              label: const Text('发送')),
        ],
      ),
    );
  }

  void _enqueueAttachment(
      String conversationId, AttachmentUpload upload, int size) {
    _enqueueOptimisticMessage(
      conversationId,
      _OptimisticSendDescriptor(
        clientMessageId: newMessageClientId(),
        kind: upload.mimeType.startsWith('image/')
            ? _OptimisticMessageKind.image
            : _OptimisticMessageKind.file,
        upload: upload,
        replyTo: _replyTo,
        sizeBytes: size,
      ),
    );
  }

  Future<void> _sendMessage(String conversationId) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final descriptor = _OptimisticSendDescriptor(
      clientMessageId: newMessageClientId(),
      kind: _OptimisticMessageKind.text,
      text: text,
      replyTo: _replyTo,
    );
    _controller.clear();
    _enqueueOptimisticMessage(conversationId, descriptor);
    final key = _draftKey;
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
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
                  .where((conversation) => conversation.displayTitle
                      .toLowerCase()
                      .contains(normalized))
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
                                title: Text(conversation.displayTitle),
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
                                    child: Text(
                                        conversation.displayTitle.isEmpty
                                            ? '?'
                                            : conversation.displayTitle
                                                .substring(0, 1))),
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

class _OptimisticMessageBubble extends StatelessWidget {
  const _OptimisticMessageBubble({
    required this.item,
    required this.contactsFuture,
    required this.onRetry,
  });

  final _OptimisticMessage item;
  final Future<List<Contact>>? contactsFuture;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final descriptor = item.descriptor;
    final colors = Theme.of(context).colorScheme;
    final maxWidth =
        (MediaQuery.sizeOf(context).width * .72).clamp(220.0, 520.0);
    return Padding(
      padding: const EdgeInsets.only(left: 44, right: 12, bottom: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
          dimension: 32,
          child: Center(
            child: item.status == _OptimisticMessageStatus.sending
                ? Semantics(
                    label: '消息发送中',
                    child: const SizedBox.square(
                      key: ValueKey('optimistic-message-sending'),
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: const ValueKey('optimistic-message-retry'),
                    tooltip: '重新发送消息',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: onRetry,
                    color: colors.error,
                    icon: const Icon(Icons.error, size: 21),
                  ),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          key: ValueKey('message-bubble-${item.message.id}'),
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: FutureBuilder<List<Contact>>(
            future: contactsFuture,
            builder: (context, snapshot) {
              final contacts = snapshot.data ?? const <Contact>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (descriptor.replyTo != null)
                    _replyPreview(context, descriptor.replyTo!, contacts),
                  _content(context, descriptor, contacts),
                  if (formatMessageTime(item.message.createdAt)
                      case final time?)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(time,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color:
                                      colors.onPrimary.withValues(alpha: .8))),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _content(BuildContext context, _OptimisticSendDescriptor descriptor,
      List<Contact> contacts) {
    final color = Theme.of(context).colorScheme.onPrimary;
    switch (descriptor.kind) {
      case _OptimisticMessageKind.text:
        return Text(
          formatMentionText(
              descriptor.text,
              contacts.map(
                  (contact) => (id: contact.id, name: contact.displayName))),
          style: TextStyle(color: color),
        );
      case _OptimisticMessageKind.image:
        final bytes = descriptor.upload?.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280),
            child: Image.memory(bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _attachmentLabel(descriptor, Icons.image_outlined, color)),
          );
        }
        return _attachmentLabel(descriptor, Icons.image_outlined, color);
      case _OptimisticMessageKind.file:
        return _attachmentLabel(descriptor, Icons.attach_file, color);
      case _OptimisticMessageKind.voice:
        final transcript = descriptor.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.mic_none, size: 18, color: color),
              const SizedBox(width: 6),
              Text('语音 ${formatVoiceDuration(descriptor.durationMs)}',
                  style: TextStyle(color: color)),
            ]),
            if (transcript.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(transcript, style: TextStyle(color: color)),
              ),
          ],
        );
    }
  }

  Widget _attachmentLabel(
      _OptimisticSendDescriptor descriptor, IconData icon, Color color) {
    final name = descriptor.upload?.name.trim();
    final size = descriptor.sizeBytes;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          '${name?.isNotEmpty == true ? name : descriptor.kind == _OptimisticMessageKind.image ? '图片' : '文件'}${size == null ? '' : ' · ${_formatAttachmentSize(size)}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color),
        ),
      ),
    ]);
  }

  Widget _replyPreview(
      BuildContext context, MessageReply reply, List<Contact> contacts) {
    final colors = Theme.of(context).colorScheme;
    final matched =
        contacts.where((contact) => contact.id == reply.authorId).firstOrNull;
    final rawAuthor = reply.author.trim();
    final author = matched?.displayName ??
        (rawAuthor.isEmpty ||
                rawAuthor == reply.authorId ||
                rawAuthor == '用户' ||
                rawAuthor == '成员'
            ? '成员'
            : rawAuthor);
    final text = formatMessageReferenceText(
      reply.text,
      contacts.map((contact) => (id: contact.id, name: contact.displayName)),
      messageId: reply.id,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: colors.onPrimary.withValues(alpha: .16),
        border: Border(left: BorderSide(color: colors.onPrimary, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('回复 $author：$text',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onPrimary)),
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

class _ConversationFileDropOverlay extends StatelessWidget {
  const _ConversationFileDropOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Semantics(
          key: const ValueKey('conversation-file-drop-overlay'),
          liveRegion: true,
          label: '松开发送文件或图片',
          child: ColoredBox(
            color: colors.primary.withValues(alpha: .1),
            child: Center(
              child: Container(
                width: 320,
                height: 180,
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.primary, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: colors.primaryContainer,
                      child: Icon(Icons.upload_file,
                          color: colors.onPrimaryContainer, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text('松开发送文件或图片',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('一次发送一个文件，发送前可确认',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
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
      this.replyTarget,
      required this.repository,
      required this.conversationId,
      this.galleryMessages = const [],
      this.galleryHasOlder = false,
      this.canReact = true,
      this.canRespond = true,
      this.onOpenTopic,
      this.onOpenInternalLink,
      this.onForwardMessage,
      this.contactsFuture,
      this.onReeditMessage,
      this.cacheScope,
      this.preloadedImages = const {},
      this.preloadedAttachmentUrls = const {}});
  final ChatMessage message;
  final ChatMessage? replyTarget;
  final MagicChatRepository repository;
  final String conversationId;
  final List<ChatMessage> galleryMessages;
  final bool galleryHasOlder;
  final bool canReact;
  final bool canRespond;
  final ValueChanged<String>? onOpenTopic;
  final ValueChanged<String>? onOpenInternalLink;
  final Future<void> Function(String messageId)? onForwardMessage;
  final Future<List<Contact>>? contactsFuture;
  final ValueChanged<ChatMessage>? onReeditMessage;
  final MessageCacheScope? cacheScope;
  final Map<String, _CachedImageData> preloadedImages;
  final Map<String, Uri> preloadedAttachmentUrls;

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

  Widget _markdownContent(BuildContext context, bool mine, ColorScheme colors) {
    return FutureBuilder<List<Contact>>(
      future: contactsFuture,
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? const <Contact>[];
        final content = formatMentionText(
            message.text,
            contacts.map((contact) => (
                  id: contact.id,
                  name: contact.displayName,
                )));
        return CollapsibleMessageContent(
          key: ValueKey('collapsible-message-${message.id}'),
          variant: CollapsibleMessageVariant.markdown,
          contentIdentity: content,
          backgroundColor:
              mine ? colors.primary : colors.surfaceContainerHighest,
          foregroundColor: mine ? colors.onPrimary : colors.primary,
          builder: (context) => MarkdownBody(
            data: content,
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: mine ? colors.onPrimary : null),
              a: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: mine ? colors.onPrimary : colors.primary,
                  decoration: TextDecoration.underline),
            ),
            onTapLink: (text, href, title) {
              final uri = parseMarkdownLink(href);
              if (uri != null) {
                unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              }
            },
          ),
        );
      },
    );
  }

  Widget _textContent(BuildContext context, bool mine, ColorScheme colors) {
    return FutureBuilder<List<Contact>>(
      future: contactsFuture,
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? const <Contact>[];
        final content = formatMentionText(
            message.text,
            contacts.map((contact) => (
                  id: contact.id,
                  name: contact.displayName,
                )));
        final text = Text(content,
            style: TextStyle(color: mine ? colors.onPrimary : null));
        if (message.contentType != 'text') return text;
        return CollapsibleMessageContent(
          key: ValueKey('collapsible-message-${message.id}'),
          variant: CollapsibleMessageVariant.text,
          contentIdentity: content,
          backgroundColor:
              mine ? colors.primary : colors.surfaceContainerHighest,
          foregroundColor: mine ? colors.onPrimary : colors.primary,
          builder: (_) => Text(content,
              style: TextStyle(color: mine ? colors.onPrimary : null)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final messageTime = formatMessageTime(message.createdAt);
    if (message.contentType == 'system_event') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          children: [
            Text(
              message.text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (messageTime != null)
              Text(messageTime,
                  key: ValueKey('message-time-${message.id}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
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
    final maxBubbleWidth =
        (MediaQuery.sizeOf(context).width * .78).clamp(220.0, 560.0);
    return Container(
      key: ValueKey('message-bubble-${message.id}'),
      margin: EdgeInsets.only(
          left: mine ? 56 : 12, right: mine ? 12 : 56, bottom: 6),
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
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
          SizedBox(
              height: 28,
              child: FutureBuilder<List<Contact>>(
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
                    final canOpenProfile =
                        snapshot.hasData && avatarContact != null;
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
                              : () => _showContactPanel(context, avatarContact),
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
                  })),
        if (!hasVoicePlayer && message.contentType != 'image')
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
                            ? _markdownContent(context, mine, colors)
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
                                        contactsFuture: contactsFuture,
                                        textColor:
                                            mine ? colors.onPrimary : null)
                                    : _textContent(context, mine, colors)),
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
                  initialData: preloadedImages[message.rawBody['file_id']],
                  onTap: (data) => unawaited(showConversationImageGallery(
                    context,
                    repository: repository,
                    conversationId: conversationId,
                    messages: galleryMessages,
                    initialMessageId: message.id,
                    hasOlder: galleryHasOlder,
                    cacheScope: cacheScope,
                    initialBytes: data?.bytes,
                    initialUri: data?.uri,
                    onForward: onForwardMessage,
                  )),
                )
              else
                FutureBuilder<Uri?>(
                  future: preloadedAttachmentUrls[
                              message.rawBody['file_id'] as String] ==
                          null
                      ? repository
                          .attachmentUrl(message.rawBody['file_id'] as String)
                      : null,
                  initialData: preloadedAttachmentUrls[
                      message.rawBody['file_id'] as String],
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const SizedBox(
                          height: 80,
                          child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text('附件暂时无法加载'))));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                          height: 80,
                          child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: SizedBox(
                                      height: 40,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)))));
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(height: 80);
                    }
                    final uri = snapshot.data;
                    if (uri == null) {
                      return const SizedBox(height: 80);
                    }
                    final name = message.rawBody['name'];
                    final size = message.rawBody['size_bytes'];
                    // URL 解析是异步的；预留完整附件操作区高度，避免
                    // 首屏加载后消息列表从上到下重新排版。
                    return SizedBox(
                      height: 80,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (name is String && name.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(name.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await _cacheAttachment(
                                        message.rawBody['file_id'] as String,
                                        uri);
                                    if (!context.mounted) return;
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text('附件加载失败：$error')));
                                    }
                                  }
                                },
                                icon: const Icon(Icons.download_outlined),
                                label: Text(size is num
                                    ? '打开附件 · ${_formatAttachmentSize(size)}'
                                    : '打开附件')),
                          ],
                        ),
                      ),
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
                      .toList())),
        if (messageTime != null)
          Align(
              alignment: Alignment.centerRight,
              child: Text(messageTime,
                  key: ValueKey('message-time-${message.id}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: (mine ? colors.onPrimary : colors.onSurfaceVariant)
                          .withValues(alpha: .8))))
      ]),
    );
  }

  Contact? _findContact(List<Contact>? contacts, [String? referenceId]) {
    final id = referenceId ?? message.authorId;
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
    Widget content(List<Contact> contacts) {
      final target = replyTarget;
      final authorId = target?.authorId ?? reply.authorId;
      final contact = _findContact(contacts, authorId);
      final fallback = (target?.author ?? reply.author).trim();
      final author = _contactName(contact) ??
          (fallback.isEmpty ||
                  fallback == authorId ||
                  fallback == '用户' ||
                  fallback == '成员'
              ? '成员'
              : fallback);
      final labels = contacts.map((contact) => (
            id: contact.id,
            name: contact.displayName,
          ));
      final referenceText = formatMessageReferenceText(
          target?.text ?? reply.text, labels,
          messageId: reply.id);
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: mine
              ? colors.onPrimary.withValues(alpha: .16)
              : colors.primary.withValues(alpha: .08),
          border: Border(left: BorderSide(color: colors.primary, width: 3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('回复 $author：$referenceText',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: mine ? colors.onPrimary : colors.onSurfaceVariant)),
      );
    }

    final future = contactsFuture;
    if (future == null) return content(const []);
    return FutureBuilder<List<Contact>>(
        future: future,
        builder: (context, snapshot) =>
            content(snapshot.data ?? const <Contact>[]));
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
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EntityDetailsPage(
          repository: repository,
          contact: contact,
          serverUrl: repository is HttpMagicChatRepository
              ? (repository as HttpMagicChatRepository).baseUri.toString()
              : null,
          cacheScope: cacheScope,
          onOpenConversation: onOpenTopic,
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
                            final name =
                                user.name.isNotEmpty && user.name != user.id
                                    ? user.name
                                    : names[user.id]?.isNotEmpty == true
                                        ? names[user.id]!
                                        : '成员';
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
    this.initialData,
    required this.onTap,
  });

  final MagicChatRepository repository;
  final MessageCacheScope? cacheScope;
  final String fileId;
  final _CachedImageData? initialData;
  final ValueChanged<_CachedImageData?> onTap;

  @override
  State<_CachedConversationImage> createState() =>
      _CachedConversationImageState();
}

class _CachedConversationImageState extends State<_CachedConversationImage> {
  Future<_CachedImageData?>? _future;

  @override
  void initState() {
    super.initState();
    _future =
        widget.initialData == null ? _load() : Future.value(widget.initialData);
  }

  @override
  void didUpdateWidget(covariant _CachedConversationImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId ||
        oldWidget.cacheScope != widget.cacheScope ||
        oldWidget.initialData != widget.initialData) {
      _future = widget.initialData == null
          ? _load()
          : Future.value(widget.initialData);
    }
  }

  Future<_CachedImageData?> _load() => _loadCachedConversationImage(
        repository: widget.repository,
        cacheScope: widget.cacheScope,
        fileId: widget.fileId,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CachedImageData?>(
      future: _future,
      initialData: widget.initialData,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final bytes = data?.bytes;
        final displaySize = _conversationImageSize(
            MediaQuery.sizeOf(context), data?.pixelWidth, data?.pixelHeight);
        final child = snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData
            ? const CircularProgressIndicator(strokeWidth: 2)
            : data == null || bytes == null
                ? GestureDetector(
                    onTap: () => widget.onTap(null),
                    child: data?.uri == null
                        ? const Text('图片暂时无法加载')
                        : Image.network(data!.uri.toString(),
                            width: displaySize.width,
                            height: displaySize.height,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('图片暂时无法加载')))
                : GestureDetector(
                    onTap: () => widget.onTap(data),
                    child: Image.memory(bytes,
                        width: displaySize.width,
                        height: displaySize.height,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('图片暂时无法加载')),
                  );
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            key: ValueKey('conversation-image-${widget.fileId}'),
            width: displaySize.width,
            height: displaySize.height,
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

Future<_CachedImageData?> _loadCachedConversationImage({
  required MagicChatRepository repository,
  required MessageCacheScope? cacheScope,
  required String fileId,
}) async {
  final cache = LocalAssetCache();
  final owner =
      cacheScope == null ? '' : '${cacheScope.serverUrl}|${cacheScope.userId}|';
  final key = 'attachment|$owner$fileId';
  Uint8List? cached;
  try {
    cached = await cache.read(key);
  } catch (_) {
    cached = null;
  }
  if (cached != null) return _cachedImageData(cached);
  Uri? uri;
  try {
    uri = await repository.attachmentUrl(fileId);
  } catch (_) {
    uri = null;
  }
  Uint8List? bytes;
  if (uri != null) {
    try {
      bytes = await repository.downloadResource(uri);
    } catch (_) {
      bytes = null;
    }
  }
  if (bytes == null) {
    try {
      bytes = await repository.downloadAttachment(fileId);
    } catch (_) {
      bytes = null;
    }
  }
  if (bytes != null && bytes.isNotEmpty) {
    try {
      await cache.write(key, bytes);
    } catch (_) {
      // 图片已经在内存中，缓存目录不可写不阻断当前消息显示。
    }
  }
  return _cachedImageData(bytes, uri: uri);
}

Size _conversationImageSize(Size viewport, int? pixelWidth, int? pixelHeight) {
  final maxWidth = min(320.0, max(120.0, viewport.width - 132));
  final maxHeight = min(300.0, max(160.0, viewport.height * .45));
  final width =
      pixelWidth != null && pixelWidth > 0 ? pixelWidth.toDouble() : 4;
  final height =
      pixelHeight != null && pixelHeight > 0 ? pixelHeight.toDouble() : 3;
  final scale = min(maxWidth / width, maxHeight / height);
  return Size(width * scale, height * scale);
}

_CachedImageData _cachedImageData(Uint8List? bytes, {Uri? uri}) {
  if (bytes == null || bytes.isEmpty) {
    return _CachedImageData(bytes: bytes, uri: uri);
  }
  final dimensions = _imageDimensions(bytes);
  return _CachedImageData(
      bytes: bytes,
      uri: uri,
      pixelWidth: dimensions?.width,
      pixelHeight: dimensions?.height);
}

_ImageDimensions? _imageDimensions(Uint8List bytes) {
  int be16(int offset) => (bytes[offset] << 8) | bytes[offset + 1];
  int le16(int offset) => bytes[offset] | (bytes[offset + 1] << 8);
  int be32(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  int le24(int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  bool ascii(int offset, String value) {
    if (offset + value.length > bytes.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (bytes.length >= 24 && bytes[0] == 0x89 && ascii(1, 'PNG\r\n\x1a\n')) {
    return _ImageDimensions(be32(16), be32(20));
  }
  if (bytes.length >= 10 && ascii(0, 'GIF')) {
    return _ImageDimensions(le16(6), le16(8));
  }
  if (bytes.length >= 30 && ascii(0, 'RIFF') && ascii(8, 'WEBP')) {
    if (ascii(12, 'VP8X')) {
      return _ImageDimensions(le24(24) + 1, le24(27) + 1);
    }
    if (ascii(12, 'VP8L') && bytes[20] == 0x2f) {
      final width = 1 + bytes[21] + ((bytes[22] & 0x3f) << 8);
      final height =
          1 + (bytes[22] >> 6) + (bytes[23] << 2) + ((bytes[24] & 0x0f) << 10);
      return _ImageDimensions(width, height);
    }
    if (ascii(12, 'VP8 ') &&
        bytes[23] == 0x9d &&
        bytes[24] == 0x01 &&
        bytes[25] == 0x2a) {
      return _ImageDimensions(le16(26) & 0x3fff, le16(28) & 0x3fff);
    }
  }
  if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    while (offset + 8 < bytes.length) {
      if (bytes[offset] != 0xff) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xd8 || marker == 0xd9) {
        offset += 2;
        continue;
      }
      final segmentLength = be16(offset + 2);
      if (segmentLength < 2 || offset + 2 + segmentLength > bytes.length) break;
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf)) {
        return _ImageDimensions(be16(offset + 7), be16(offset + 5));
      }
      offset += 2 + segmentLength;
    }
  }
  return null;
}

class _ImageDimensions {
  const _ImageDimensions(this.width, this.height);

  final int width;
  final int height;
}

class _CachedImageData {
  const _CachedImageData(
      {required this.bytes, this.uri, this.pixelWidth, this.pixelHeight});

  final Uint8List? bytes;
  final Uri? uri;
  final int? pixelWidth;
  final int? pixelHeight;
}
