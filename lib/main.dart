import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/repository.dart';
import 'data/auth_service.dart';
import 'data/session_store.dart';
import 'data/platform_connector_selector.dart';
import 'data/realtime.dart';
import 'data/realtime_store.dart';
import 'data/document_collaboration.dart';
import 'data/push_service.dart';
import 'data/local_notification_service.dart';
import 'data/voice_recorder.dart';
import 'data/avatar_processor.dart';
import 'features/contacts/contacts_page.dart';
import 'features/messages/history_attachments_dialog.dart';
import 'features/messages/message_link_card.dart';
import 'features/messages/topic_reply_preview.dart';
import 'features/messages/topics_dialog.dart';
import 'features/messages/topic_source_banner.dart';
import 'features/messages/conversation_list.dart';
import 'features/messages/voice_message_player.dart';
import 'features/projects/projects_page.dart';
import 'features/search/global_search.dart';
import 'features/settings/settings_page.dart';
import 'domain/models.dart';
import 'domain/message_content.dart';

Uri? _resolveAssetUri(String? serverUrl, String value) {
  final parsed = Uri.tryParse(value);
  if (parsed == null || value.trim().isEmpty) return null;
  if (parsed.hasScheme) return parsed;
  final server = Uri.tryParse(serverUrl ?? '');
  return server == null ? null : server.resolve(value);
}

void main() => runApp(const MagicChatApp());

class MagicChatApp extends StatefulWidget {
  const MagicChatApp({super.key});
  @override
  State<MagicChatApp> createState() => _MagicChatAppState();
}

class _MagicChatAppState extends State<MagicChatApp> {
  MagicChatRepository? _repository;
  RealtimeSession? _realtime;
  final _realtimeStore = RealtimeStore();
  ThemeMode _themeMode = ThemeMode.system;
  String? _serverUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString('magicchat.server_url');
    final token = await const SessionStore().readToken();
    final theme = prefs.getString('magicchat.theme');
    if (!mounted) return;
    setState(() {
      _serverUrl = server;
      _repository = server != null && token != null
          ? HttpMagicChatRepository(serverUrl: server, sessionToken: token)
          : null;
      _realtime = server != null && token != null
          ? RealtimeSession(
              realtime: MagicChatRealtime(
                  serverUrl: server,
                  sessionToken: token,
                  connector: connectWithAuthorization))
          : null;
      _loading = false;
      _themeMode = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
    if (server != null && token != null) {
      unawaited(_registerPush(server, token));
    }
  }

  Future<void> _login(String server, String email, String password) async {
    await AuthService()
        .login(serverUrl: server, email: email, password: password);
    final prefs = await SharedPreferences.getInstance();
    final token = await const SessionStore().readToken();
    await prefs.setString('magicchat.server_url', server);
    if (!mounted || token == null) return;
    await const SessionStore().saveAccount(StoredAccount(
        id: '$server|$email', serverUrl: server, token: token, email: email));
    setState(() => _repository =
        HttpMagicChatRepository(serverUrl: server, sessionToken: token));
    setState(() => _serverUrl = server);
    setState(() => _realtime = RealtimeSession(
        realtime: MagicChatRealtime(
            serverUrl: server,
            sessionToken: token,
            connector: connectWithAuthorization)));
    unawaited(_registerPush(server, token));
  }

  Future<void> _loginWithCode(String server, String email, String code) async {
    await AuthService()
        .loginWithEmailCode(serverUrl: server, email: email, code: code);
    final prefs = await SharedPreferences.getInstance();
    final token = await const SessionStore().readToken();
    await prefs.setString('magicchat.server_url', server);
    if (!mounted || token == null) return;
    await const SessionStore().saveAccount(StoredAccount(
        id: '$server|$email', serverUrl: server, token: token, email: email));
    setState(() {
      _serverUrl = server;
      _repository =
          HttpMagicChatRepository(serverUrl: server, sessionToken: token);
      _realtime = RealtimeSession(
          realtime: MagicChatRealtime(
              serverUrl: server,
              sessionToken: token,
              connector: connectWithAuthorization));
    });
    unawaited(_registerPush(server, token));
  }

  Future<void> _registerPush(String server, String token) async {
    try {
      await const LocalNotificationService().requestPermission();
      await PushService().registerPlatformGrant(
          serverUrl: server,
          sessionToken: token,
          platform: pushPlatformName(defaultTargetPlatform));
    } catch (_) {
      // Push registration is optional; login must not be blocked by a plugin
      // or network failure.
    }
  }

  Future<void> _revokePush(String server, String token) async {
    try {
      await PushService()
          .revokePlatformGrant(serverUrl: server, sessionToken: token);
    } catch (_) {
      // Revocation is best effort; logout and account switching must continue.
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString('magicchat.server_url');
    final token = await const SessionStore().readToken();
    if (server != null && token != null) await _revokePush(server, token);
    if (server != null) {
      await AuthService().logout(serverUrl: server);
    }
    await prefs.remove('magicchat.server_url');
    await _realtime?.close();
    if (mounted) {
      setState(() {
        _repository = null;
        _realtime = null;
        _serverUrl = null;
      });
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('magicchat.theme', mode.name);
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _changeServer(String server) async {
    final normalized = server.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final oldServer = prefs.getString('magicchat.server_url');
    final oldToken = await const SessionStore().readToken();
    if (oldServer != null && oldToken != null) {
      await _revokePush(oldServer, oldToken);
    }
    await _realtime?.close();
    await const SessionStore().clear();
    await prefs.setString('magicchat.server_url', normalized);
    if (mounted)
      setState(() {
        _repository = null;
        _realtime = null;
        _serverUrl = normalized;
      });
  }

  Future<void> _switchAccount(StoredAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    final oldServer = prefs.getString('magicchat.server_url');
    final oldToken = await const SessionStore().readToken();
    if (oldServer != null && oldToken != null) {
      await _revokePush(oldServer, oldToken);
    }
    await _realtime?.close();
    await const SessionStore().writeToken(account.token);
    await prefs.setString('magicchat.server_url', account.serverUrl);
    if (!mounted) return;
    setState(() {
      _serverUrl = account.serverUrl;
      _repository = HttpMagicChatRepository(
          serverUrl: account.serverUrl, sessionToken: account.token);
      _realtime = RealtimeSession(
          realtime: MagicChatRealtime(
              serverUrl: account.serverUrl,
              sessionToken: account.token,
              connector: connectWithAuthorization));
    });
    unawaited(_registerPush(account.serverUrl, account.token));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MagicChat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff3a76f0),
                brightness: Brightness.light),
            scaffoldBackgroundColor: const Color(0xfff7f8fa),
            appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xfff7f8fa),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                centerTitle: false),
            inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide:
                        BorderSide(color: Color(0xff3a76f0), width: 1.5)),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            cardTheme: const CardThemeData(
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)))),
            useMaterial3: true),
        darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff3a76f0),
                brightness: Brightness.dark),
            scaffoldBackgroundColor: const Color(0xff17191c),
            appBarTheme: const AppBarTheme(
                surfaceTintColor: Colors.transparent, elevation: 0),
            inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none)),
            cardTheme: const CardThemeData(
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)))),
            useMaterial3: true),
        themeMode: _themeMode,
        home: _loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _repository == null
                ? LoginPage(
                    onLogin: _login,
                    onCodeLogin: _loginWithCode,
                    initialServer: _serverUrl)
                : AppShell(
                    repository: _repository!,
                    serverUrl: _serverUrl,
                    onServerChanged: _changeServer,
                    onAccountSwitch: _switchAccount,
                    realtime: _realtime,
                    realtimeStore: _realtimeStore,
                    onLogout: _logout,
                    onThemeChanged: _setTheme,
                    themeMode: _themeMode),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage(
      {required this.onLogin,
      required this.onCodeLogin,
      this.initialServer,
      super.key});
  final Future<void> Function(String server, String email, String password)
      onLogin;
  final Future<void> Function(String server, String email, String code)
      onCodeLogin;
  final String? initialServer;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _server = TextEditingController(
      text: widget.initialServer ?? 'https://app.jiying.chat');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeMode = false;
  String? _error;
  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    shape: BoxShape.circle),
                                child: Icon(Icons.forum_rounded,
                                    size: 32,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer)),
                            const SizedBox(height: 16),
                            Text('登录 MagicChat',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 6),
                            Text('安全、私密地连接你的团队',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                            const SizedBox(height: 24),
                            TextField(
                                controller: _server,
                                decoration: const InputDecoration(
                                    labelText: '服务器地址',
                                    prefixIcon: Icon(Icons.dns))),
                            const SizedBox(height: 12),
                            TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration:
                                    const InputDecoration(labelText: '邮箱')),
                            const SizedBox(height: 8),
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _codeMode = !_codeMode),
                                    child: Text(
                                        _codeMode ? '使用密码登录' : '使用邮箱验证码登录'))),
                            if (_codeMode) ...[
                              TextField(
                                  controller: _code,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                      labelText: '邮箱验证码',
                                      suffixIcon: TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () async {
                                                  try {
                                                    await AuthService()
                                                        .requestEmailCode(
                                                            serverUrl: _server
                                                                .text
                                                                .trim(),
                                                            email: _email.text
                                                                .trim());
                                                    if (mounted)
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      '验证码已发送')));
                                                  } catch (error) {
                                                    if (mounted)
                                                      setState(() => _error =
                                                          error.toString());
                                                  }
                                                },
                                          child: const Text('发送')))),
                            ] else
                              TextField(
                                  controller: _password,
                                  obscureText: true,
                                  decoration:
                                      const InputDecoration(labelText: '密码')),
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            const SizedBox(height: 20),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            setState(() {
                                              _busy = true;
                                              _error = null;
                                            });
                                            try {
                                              if (_codeMode) {
                                                await widget.onCodeLogin(
                                                    _server.text.trim(),
                                                    _email.text.trim(),
                                                    _code.text.trim());
                                              } else {
                                                await widget.onLogin(
                                                    _server.text.trim(),
                                                    _email.text.trim(),
                                                    _password.text);
                                              }
                                            } catch (error) {
                                              if (mounted) {
                                                setState(() =>
                                                    _error = error.toString());
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(() => _busy = false);
                                              }
                                            }
                                          },
                                    child: _busy
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Text('登录')))
                          ])))))));
}

class AppShell extends StatefulWidget {
  const AppShell(
      {required this.repository,
      this.serverUrl,
      this.onServerChanged,
      this.onAccountSwitch,
      this.realtime,
      this.realtimeStore,
      this.onLogout,
      this.onThemeChanged,
      this.themeMode = ThemeMode.system,
      super.key});
  final MagicChatRepository repository;
  final String? serverUrl;
  final ValueChanged<String>? onServerChanged;
  final ValueChanged<StoredAccount>? onAccountSwitch;
  final RealtimeSession? realtime;
  final RealtimeStore? realtimeStore;
  final Future<void> Function()? onLogout;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ThemeMode themeMode;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final MagicChatRepository _repository = widget.repository;
  int _index = 0;
  String? _selectedConversation;
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  final _notifications = const LocalNotificationService();

  @override
  void initState() {
    super.initState();
    final realtime = widget.realtime;
    final store = widget.realtimeStore;
    if (realtime != null && store != null) {
      unawaited(widget.repository.currentUser().then((user) {
        store.setCurrentUserId(user.id);
      }).catchError((_) {}));
      _realtimeSubscription = realtime.events.listen((event) {
        store.apply(event);
        _notifyIncomingMessage(event);
      });
      realtime.connect();
    }
    _resolveNotificationRoute();
  }

  Future<void> _notifyIncomingMessage(Map<String, dynamic> event) async {
    if (event['event'] != 'message.created') return;
    final payload = event['payload'];
    if (payload is! Map<String, dynamic>) return;
    final message = payload['message'];
    final data = message is Map<String, dynamic> ? message : payload;
    final conversationId = data['conversation_id'];
    if (conversationId is! String || conversationId == _selectedConversation) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('magicchat.notifications.enabled') ?? true)) return;
    final sender = data['sender'];
    final title = sender is Map<String, dynamic> && sender['name'] is String
        ? sender['name'] as String
        : '新消息';
    final body =
        MessageContent.fromEnvelope(data['body'], revokedAt: data['revoked_at'])
            .text;
    await _notifications.showMessage(
        conversationId: conversationId, title: title, body: body);
  }

  Future<void> _resolveNotificationRoute() async {
    final routeToken = Uri.base.queryParameters['route_token'];
    if (routeToken == null || routeToken.isEmpty || widget.serverUrl == null)
      return;
    try {
      final token = await const SessionStore().readToken();
      if (token == null) return;
      final route = await PushService().resolveRoute(
          serverUrl: widget.serverUrl!,
          sessionToken: token,
          routeToken: routeToken);
      if (mounted) setState(() => _selectedConversation = route.conversationId);
    } catch (_) {
      // 通知路由失效时保留正常首页，不阻断主应用启动。
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    widget.realtime?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final httpRepository = widget.repository;
    final documentCollaborationFactory =
        httpRepository is HttpMagicChatRepository && widget.serverUrl != null
            ? (ProjectDocument document) =>
                document.documentType == 'markdown' ||
                        document.documentType == 'document'
                    ? DocumentCollaborationSession(
                        serverUrl: widget.serverUrl!,
                        token: httpRepository.sessionToken,
                        documentId: document.id,
                        documentType: document.documentType!,
                        connector: connectWithAuthorization)
                    : null
            : null;
    final pages = <Widget>[
      MessagesPage(
          repository: _repository,
          serverUrl: widget.serverUrl,
          realtimeStore: widget.realtimeStore,
          selectedId: _selectedConversation,
          onSelect: (id) =>
              setState(() => _selectedConversation = id.isEmpty ? null : id),
          onOpenInternalLink: _openInternalMessageLink),
      ContactsPage(
          repository: _repository,
          realtimeStore: widget.realtimeStore,
          serverUrl: widget.serverUrl,
          onOpenConversation: (id) => setState(() {
                _selectedConversation = id;
                _index = 0;
              })),
      ProjectsPage(
          repository: _repository,
          documentCollaborationFactory: documentCollaborationFactory),
      SettingsPage(
          repository: _repository,
          realtimeStore: widget.realtimeStore,
          serverUrl: widget.serverUrl,
          onServerChanged: widget.onServerChanged,
          onAccountSwitch: widget.onAccountSwitch,
          onLogout: widget.onLogout,
          onThemeChanged: widget.onThemeChanged,
          themeMode: widget.themeMode),
    ];
    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: '消息'),
      NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '联系人'),
      NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: '项目'),
      NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置'),
    ];
    return Scaffold(
      appBar: AppBar(
          title: const Text('MagicChat',
              style:
                  TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.2)),
          actions: [
            IconButton(
                onPressed: () => _showSearch(context),
                icon: const Icon(Icons.search),
                tooltip: '搜索')
          ]),
      body: Row(children: [
        if (wide)
          NavigationRail(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              useIndicator: true,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label)))
                  .toList()),
        Expanded(child: pages[_index])
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: destinations),
    );
  }

  void _openInternalMessageLink(String path) {
    final target = parseInternalMessagePath(path);
    if (target == null) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    if (uri.path == '/projects' || uri.path.startsWith('/projects/')) {
      setState(() => _index = 2);
    }
  }

  Future<void> _showSearch(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => GlobalSearchDialog(
        repository: _repository,
        onOpenConversation: (id) => setState(() {
          _selectedConversation = id;
          _index = 0;
        }),
        onOpenProject: (_) => setState(() => _index = 2),
        onOpenContact: (_) => setState(() => _index = 1),
      ),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage(
      {required this.repository,
      this.serverUrl,
      this.realtimeStore,
      required this.selectedId,
      required this.onSelect,
      this.onOpenInternalLink,
      super.key});
  final MagicChatRepository repository;
  final String? serverUrl;
  final RealtimeStore? realtimeStore;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpenInternalLink;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final split = constraints.maxWidth >= 700;
        // 移动端使用单列导航：选择会话后进入聊天，返回按钮回到列表。
        if (!split && selectedId != null) {
          return Column(children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SizedBox(
                height: 52,
                child: Row(children: [
                  IconButton(
                    tooltip: '返回会话列表',
                    onPressed: () => onSelect(''),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Text('聊天',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            Expanded(
              child: ConversationView(
                repository: repository,
                realtimeStore: realtimeStore,
                conversationId: selectedId,
                onOpenConversation: onSelect,
                onOpenInternalLink: onOpenInternalLink,
              ),
            ),
          ]);
        }
        return Stack(children: [
          Row(children: [
            SizedBox(
                width: split ? 300 : constraints.maxWidth,
                child: _ConversationList(
                    repository: repository,
                    serverUrl: serverUrl,
                    realtimeStore: realtimeStore,
                    selectedId: selectedId,
                    onSelect: onSelect)),
            if (split)
              Expanded(
                  child: ConversationView(
                      repository: repository,
                      realtimeStore: realtimeStore,
                      conversationId: selectedId,
                      onOpenConversation: onSelect,
                      onOpenInternalLink: onOpenInternalLink))
          ]),
          Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                  onPressed: () => _createGroup(context),
                  child: const Icon(Icons.group_add),
                  tooltip: '新建群聊')),
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
      this.realtimeStore,
      required this.selectedId,
      required this.onSelect});
  final MagicChatRepository repository;
  final String? serverUrl;
  final RealtimeStore? realtimeStore;
  final String? selectedId;
  final ValueChanged<String> onSelect;
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

  void _reload() => _future = widget.repository.conversations();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ChatConversation>>(
      future: _future,
      builder: (context, snapshot) {
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
                return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('没有匹配的会话')));
              }
              final c = conversations.elementAt(i - 1);
              final mentionUnread = c.lastMentionedSeq > c.lastReadSeq;
              final choiceUnread = c.lastChoiceSeq > c.lastReadSeq;
              final hasUnread = c.unread > 0 || mentionUnread || choiceUnread;
              return ListTile(
                  minVerticalPadding: 10,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  selected: c.id == widget.selectedId,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  leading: CircleAvatar(
                      radius: 23,
                      backgroundImage:
                          _resolveAssetUri(widget.serverUrl, c.avatar) == null
                              ? null
                              : NetworkImage(
                                  _resolveAssetUri(widget.serverUrl, c.avatar)!
                                      .toString()),
                      child: c.avatar.isEmpty
                          ? Text(
                              c.title.isEmpty ? '?' : c.title.substring(0, 1))
                          : null),
                  title: Text(c.title,
                      style: TextStyle(
                          fontWeight:
                              hasUnread ? FontWeight.w700 : FontWeight.w500)),
                  subtitle: Text(
                      c.announcement.isNotEmpty
                          ? '公告：${c.announcement}'
                          : c.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: hasUnread ? FontWeight.w600 : null)),
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
                      await widget.repository
                          .markConversationRead(c.id, c.lastMessageSeq);
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

class ConversationView extends StatefulWidget {
  const ConversationView(
      {required this.repository,
      this.realtimeStore,
      required this.conversationId,
      this.onOpenConversation,
      this.onOpenInternalLink,
      super.key});
  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final String? conversationId;
  final ValueChanged<String>? onOpenConversation;
  final ValueChanged<String>? onOpenInternalLink;
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
  final _scrollController = ScrollController();
  final _voiceRecorder = VoiceRecorder();
  Future<List<ChatMessage>>? _messagesFuture;
  bool _sendingFile = false;
  bool _recording = false;
  Future<List<Contact>>? _contactsFuture;
  final _olderMessages = <ChatMessage>[];
  bool _loadingOlder = false;
  int _lastReadSequence = 0;
  final _selectedMessageIds = <String>{};
  List<ChatMessage> _visibleMessages = const [];
  MessageReply? _replyTo;
  ChatConversation? _conversation;
  TopicDetail? _topicDetail;
  bool _canSend = true;

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

  bool _canForwardOrSelect(ChatMessage message) =>
      _forwardableMessageTypes.contains(message.contentType);

  bool _hasMessageActions(ChatMessage message) =>
      message.contentType != 'revoked' &&
      message.contentType != 'unsupported' &&
      message.contentType != 'system_event';

  @override
  void initState() {
    super.initState();
    _messagesFuture = _loadMessages();
    _contactsFuture = _loadConversationContacts();
    _scrollController.addListener(_onScroll);
    _controller.addListener(_persistDraft);
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    unawaited(_restoreDraft());
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
            contacts[member.id] = member;
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

  String _messageCacheKey(String id) => 'magicchat.messages.$id';

  ChatMessage? _messageFromCache(Object? value) {
    if (value is! Map<String, dynamic> || value['id'] is! String) return null;
    final reactions = value['reactions'];
    final choice = value['choice'];
    final reply = value['reply_to'];
    final rawTopic = value['topic'];
    return ChatMessage(
      id: value['id'] as String,
      author: '${value['author'] ?? '用户'}',
      authorId:
          value['author_id'] is String ? value['author_id'] as String : null,
      conversationId: value['conversation_id'] as String?,
      sequence: (value['sequence'] as num?)?.toInt(),
      contentType: '${value['content_type'] ?? 'text'}',
      rawBody: value['raw_body'] is Map
          ? Map<String, dynamic>.from(value['raw_body'] as Map)
          : const {},
      text: '${value['text'] ?? ''}',
      mine: value['mine'] == true,
      choice: parseMessageChoiceState(choice),
      replyTo: reply is Map<String, dynamic> && reply['id'] is String
          ? MessageReply(
              id: reply['id'] as String,
              author: '${reply['author'] ?? '用户'}',
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _messageCacheKey(id),
        jsonEncode(messages
            .map((message) => {
                  'id': message.id,
                  'author': message.author,
                  'author_id': message.authorId,
                  'conversation_id': message.conversationId,
                  'sequence': message.sequence,
                  'content_type': message.contentType,
                  'raw_body': message.rawBody,
                  'text': message.text,
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
            .toList()));
  }

  Future<List<ChatMessage>> _readCachedMessages(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_messageCacheKey(id));
    if (encoded == null) return const [];
    final decoded = jsonDecode(encoded);
    return decoded is List
        ? decoded.map(_messageFromCache).whereType<ChatMessage>().toList()
        : const [];
  }

  Future<List<ChatMessage>> _loadMessages() async {
    final id = widget.conversationId;
    if (id == null) return const [];
    final cached = await _readCachedMessages(id);
    if (cached.isNotEmpty) unawaited(_refreshMessages(id));
    if (cached.isNotEmpty) return cached;
    final fresh = await widget.repository.messages(id);
    unawaited(_cacheMessages(id, fresh));
    // 消息接口返回的 choice/reaction 可能来自旧缓存或断线前的视图；
    // 快照查询是尽力而为的后台修正，失败时不影响消息首屏加载。
    unawaited(_refreshMessageSnapshots(id, fresh));
    return fresh;
  }

  Future<void> _refreshMessages(String id) async {
    final fresh = await widget.repository.messages(id);
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
    final updated = await _applyMessageSnapshots(conversationId, messages);
    if (!mounted || widget.conversationId != conversationId) return;
    await _cacheMessages(conversationId, updated);
    if (!mounted || widget.conversationId != conversationId) return;
    setState(() {
      _messagesFuture = Future.value(updated);
    });
  }

  void _onRealtimeChanged() {
    final id = widget.conversationId;
    final current = id == null ? null : widget.realtimeStore?.conversations[id];
    if (!mounted || current == null) return;
    final canSend = current.canSend && current.topic?.archived != true;
    final cancelRecording = _recording && !canSend;
    setState(() {
      _conversation = current;
      _canSend = current.canSend;
      if (!canSend) _replyTo = null;
    });
    if (cancelRecording) unawaited(_cancelRecording());
  }

  void _markLatestRead(List<ChatMessage> messages, String conversationId) {
    final latest = messages
        .where((message) => message.sequence != null)
        .fold<int>(0, (value, message) => max(value, message.sequence!));
    if (latest <= 0 || latest <= _lastReadSequence) return;
    final atBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <
            48;
    if (!atBottom) return;
    _lastReadSequence = latest;
    unawaited(widget.repository.markConversationRead(conversationId, latest));
  }

  Future<void> _onScroll() async {
    if (_loadingOlder ||
        !_scrollController.hasClients ||
        _scrollController.position.pixels > 24) return;
    final id = widget.conversationId;
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
    if (first?.sequence == null || first!.sequence! <= 1) return;
    setState(() => _loadingOlder = true);
    try {
      final older = await widget.repository
          .messages(id, beforeSeq: first.sequence, limit: 50);
      if (mounted) {
        final existing =
            {..._olderMessages, ...snapshot}.map((item) => item.id).toSet();
        final added =
            older.where((item) => !existing.contains(item.id)).toList();
        _olderMessages.insertAll(0, added);
        unawaited(_cacheMessages(id, [..._olderMessages, ...snapshot]));
        setState(() {});
        if (added.isNotEmpty)
          unawaited(_refreshOlderMessageSnapshots(id, added));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
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

  @override
  void didUpdateWidget(covariant ConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeStore != widget.realtimeStore) {
      oldWidget.realtimeStore?.removeListener(_onRealtimeChanged);
      widget.realtimeStore?.addListener(_onRealtimeChanged);
    }
    if (oldWidget.conversationId != widget.conversationId) {
      if (_recording) unawaited(_cancelRecording());
      _olderMessages.clear();
      _lastReadSequence = 0;
      _replyTo = null;
      _conversation = null;
      _topicDetail = null;
      _canSend = true;
      _messagesFuture = _loadMessages();
      _contactsFuture = _loadConversationContacts();
      _controller.clear();
      unawaited(_restoreDraft());
    }
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    _persistDraft();
    _controller.removeListener(_persistDraft);
    _controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final conversationId = widget.conversationId;
    if (conversationId == null) return const Center(child: Text('选择一个会话开始聊天'));
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
          child: FutureBuilder<List<ChatMessage>>(
            future: _messagesFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final realtimeMessages = widget.realtimeStore?.messages.values
                  .where((message) =>
                      message.id.isNotEmpty &&
                      message.conversationId == conversationId)
                  .toList();
              final messages =
                  realtimeMessages == null || realtimeMessages.isEmpty
                      ? snapshot.data!
                      : [...snapshot.data!, ...realtimeMessages];
              final allMessages = [..._olderMessages, ...messages]
                  .fold<List<ChatMessage>>([], (result, message) {
                if (!result.any((item) => item.id == message.id))
                  result.add(message);
                return result;
              });
              _visibleMessages = allMessages;
              _markLatestRead(allMessages, conversationId);
              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                children: allMessages
                    .map((message) => Align(
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
                            child: _MessageBubble(
                                message: message,
                                repository: widget.repository,
                                conversationId: conversationId,
                                canReact: _topicIsOpen(conversationId),
                                canRespond: canSend,
                                onOpenTopic: widget.onOpenConversation,
                                onOpenInternalLink: widget.onOpenInternalLink,
                                contactsFuture: _contactsFuture),
                          ),
                        ))
                    .toList(),
              );
            },
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
                Row(
                  children: [
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
                    Expanded(
                        child: TextField(
                            controller: _controller,
                            readOnly: !canSend,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                                hintText: canSend ? '输入消息…' : '话题已关闭',
                                prefixIcon: IconButton(
                                  tooltip: '选择表情',
                                  icon: Icon(Icons.emoji_emotions_outlined),
                                  onPressed: canSend ? _showEmojiPicker : null,
                                ),
                                isDense: true))),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      icon: const Icon(Icons.send_rounded),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(46, 46),
                          shape: const CircleBorder()),
                      tooltip: '发送',
                      onPressed: !canSend
                          ? null
                          : () async {
                              final text = _controller.text.trim();
                              if (text.isEmpty) return;
                              try {
                                await widget.repository.sendMessage(
                                    conversationId, text,
                                    replyToMessageId: _replyTo?.id);
                                _controller.clear();
                                if (mounted) setState(() => _replyTo = null);
                                final key = _draftKey;
                                if (key != null) {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.remove(key);
                                }
                                if (mounted) setState(() {});
                              } catch (error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('发送消息失败：$error')));
                                }
                              }
                            },
                    ),
                  ],
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
            id: message.id, author: message.author, text: message.text));
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message,
      required this.repository,
      required this.conversationId,
      this.canReact = true,
      this.canRespond = true,
      this.onOpenTopic,
      this.onOpenInternalLink,
      this.contactsFuture});
  final ChatMessage message;
  final MagicChatRepository repository;
  final String conversationId;
  final bool canReact;
  final bool canRespond;
  final ValueChanged<String>? onOpenTopic;
  final ValueChanged<String>? onOpenInternalLink;
  final Future<List<Contact>>? contactsFuture;

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
          Container(
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
            child: Text(
              '回复 ${message.replyTo!.author}：${message.replyTo!.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: mine ? colors.onPrimary : colors.onSurfaceVariant),
            ),
          ),
        if (!mine)
          FutureBuilder<List<Contact>>(
              future: contactsFuture,
              builder: (context, snapshot) {
                final contactName = message.authorId == null
                    ? null
                    : snapshot.data
                        ?.where((contact) => contact.id == message.authorId)
                        .map((contact) => contact.name)
                        .firstOrNull;
                return Text(
                    contactName?.isNotEmpty == true
                        ? contactName!
                        : message.author,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary, fontWeight: FontWeight.w600));
              }),
        if (!hasVoicePlayer)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (prefix != null) Icon(prefix, size: 18),
            if (prefix != null) const SizedBox(width: 6),
            Flexible(
                child: revoked
                    ? Text(message.text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontStyle: FontStyle.italic))
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
                                    p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: mine ? colors.onPrimary : null),
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
                                                        name: c.name
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
              FutureBuilder<Uri?>(
                future: repository
                    .attachmentUrl(message.rawBody['file_id'] as String),
                builder: (context, snapshot) {
                  final uri = snapshot.data;
                  if (uri == null) return const SizedBox.shrink();
                  if (message.contentType == 'image') {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => Dialog(
                            child: InteractiveViewer(
                                child: Image.network(uri.toString(),
                                    fit: BoxFit.contain)),
                          ),
                        ),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxWidth: 320, maxHeight: 240),
                            child: Image.network(uri.toString(),
                                fit: BoxFit.contain)),
                      ),
                    );
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
                          onPressed: () => launchUrl(uri,
                              mode: LaunchMode.externalApplication),
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
                                            name: contact.name
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

class _ChoiceOptionView {
  const _ChoiceOptionView({required this.id, required this.label});

  final String id;
  final String label;
}

List<_ChoiceOptionView> _choiceOptions(Object? value) => value is List
    ? value
        .whereType<Map<String, dynamic>>()
        .map((option) {
          final id = option['id'];
          final label = option['label'] ?? option['text'];
          return id is String && id.isNotEmpty && label is String
              ? _ChoiceOptionView(id: id, label: label)
              : null;
        })
        .whereType<_ChoiceOptionView>()
        .toList(growable: false)
    : const [];

class _ChoiceOptions extends StatefulWidget {
  const _ChoiceOptions(
      {required this.options,
      required this.selection,
      required this.choice,
      required this.canRespond,
      required this.onSubmit});

  final List<_ChoiceOptionView> options;
  final String selection;
  final MessageChoiceState? choice;
  final bool canRespond;
  final Future<void> Function(List<String> optionIds) onSubmit;

  @override
  State<_ChoiceOptions> createState() => _ChoiceOptionsState();
}

class _ChoiceOptionsState extends State<_ChoiceOptions> {
  late Set<String> _selected;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _selected = {...?widget.choice?.myOptionIds};
  }

  @override
  void didUpdateWidget(covariant _ChoiceOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_submitting && widget.choice != oldWidget.choice) {
      _selected = {...?widget.choice?.myOptionIds};
    }
  }

  Future<void> _submit(List<String> ids) async {
    if (ids.isEmpty || _submitting || _submitted || !widget.canRespond) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(ids);
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('提交选择失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answered =
        _submitted || widget.choice?.myOptionIds.isNotEmpty == true;
    final counts = {
      for (final option in widget.choice?.options ?? const [])
        option.id: option.responseCount
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...widget.options.map((option) {
        final count = counts[option.id] ?? 0;
        final label = count > 0 ? '${option.label} · $count' : option.label;
        final selected = _selected.contains(option.id);
        return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: widget.selection == 'multiple'
                ? FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: !answered && widget.canRespond && !_submitting
                        ? (value) => setState(() {
                              if (value) {
                                _selected.add(option.id);
                              } else {
                                _selected.remove(option.id);
                              }
                            })
                        : null)
                : ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: !answered && widget.canRespond && !_submitting
                        ? (_) => _submit([option.id])
                        : null));
      }),
      if (widget.selection == 'multiple')
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: !answered && !_submitting && widget.canRespond
                    ? () => _submit(_selected.toList())
                    : null,
                child: Text(_submitting
                    ? '提交中…'
                    : answered
                        ? '已提交'
                        : '提交选择'))),
      if (widget.choice != null)
        Text('${widget.choice!.responseCount} 人已选择',
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _ForwardBundlePreview extends StatelessWidget {
  const _ForwardBundlePreview(
      {required this.body, required this.summary, this.textColor});

  final Map<String, dynamic> body;
  final String summary;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final items = body['items'];
    final first = items is List && items.isNotEmpty && items.first is Map
        ? (items.first as Map)['summary']
        : null;
    final preview =
        first is String && first.trim().isNotEmpty ? first.trim() : summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, color: textColor, size: 18),
          const SizedBox(width: 6),
          Text('聊天记录',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        ]),
        if (preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor)),
          ),
      ],
    );
  }
}

/// 结构化图表消息的轻量级跨平台预览。
class ChartPreview extends StatelessWidget {
  const ChartPreview({required this.body, super.key});
  final Map<String, dynamic> body;

  @override
  Widget build(BuildContext context) {
    final data = body['data'];
    if (data is! Map<String, dynamic>) return const SizedBox.shrink();
    final chart = switch (body['chart_type']) {
      'line' => _ChartLine(data: data),
      'radar' => _ChartRadar(data: data),
      'pie' => _ChartPie(data: data),
      _ => _cartesianChart(data),
    };
    final title = body['title'];
    final description = body['description'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title is String && title.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(title.trim(),
                style: Theme.of(context).textTheme.titleSmall),
          ),
        chart,
        if (description is String && description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(description.trim(),
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _cartesianChart(Map<String, dynamic> data) {
    final labels = data['labels'];
    final series = data['series'];
    if (labels is! List || series is! List || labels.isEmpty) {
      final items = data['items'];
      return items is List ? _ChartBars(items: items) : const SizedBox.shrink();
    }
    final typedSeries = series.whereType<Map<String, dynamic>>().toList();
    final first = typedSeries.isEmpty ? null : typedSeries.first;
    final values = first?['values'];
    if (values is! List) return const SizedBox.shrink();
    return _ChartBars(items: [
      for (var i = 0; i < labels.length && i < values.length; i++)
        {'name': '${labels[i]}', 'value': values[i]}
    ]);
  }
}

class _ChartPie extends StatelessWidget {
  const _ChartPie({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rawItems = data['items'];
    if (rawItems is! List) return const SizedBox.shrink();
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map((item) => (
              name: '${item['name'] ?? item['label'] ?? ''}',
              value: (item['value'] as num?)?.toDouble() ?? 0,
            ))
        .where((item) => item.name.trim().isNotEmpty && item.value > 0)
        .toList(growable: false);
    final total = items.fold<double>(0, (sum, item) => sum + item.value);
    if (items.length < 2 || total <= 0) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
            width: 160,
            height: 160,
            child: CustomPaint(
                painter: _PieChartPainter(
                    items.map((item) => item.value).toList()))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _PieChartPainter
                                .palette[i % _PieChartPainter.palette.length])),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(items[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(_formatChartNumber(items[i].value)),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter(this.values);
  final List<double> values;
  static const palette = [
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.purple,
    Colors.red,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final diameter = min(size.width, size.height) - 8;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: diameter,
        height: diameter);
    var start = -pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * pi;
      canvas.drawArc(rect, start, sweep, true,
          Paint()..color = palette[i % palette.length]);
      start += sweep;
    }
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), diameter * .22,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

String _formatChartNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _formatAttachmentSize(num value) {
  final bytes = value < 0 ? 0 : value.toDouble();
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _ChartLine extends StatelessWidget {
  const _ChartLine({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final labels = data['labels'];
    final series = data['series'];
    if (labels is! List || series is! List || labels.length < 2) {
      return const SizedBox.shrink();
    }
    final values = series
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final raw = item['values'];
          return raw is List
              ? raw.map((value) => (value as num?)?.toDouble()).toList()
              : <double?>[];
        })
        .where((values) => values.length >= labels.length)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(painter: _LineChartPainter(values)),
    );
  }
}

class _ChartRadar extends StatelessWidget {
  const _ChartRadar({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final axes = data['axes'];
    final series = data['series'];
    if (axes is! List || axes.length < 3 || series is! List) {
      return const SizedBox.shrink();
    }
    final maxes = axes
        .whereType<Map<String, dynamic>>()
        .map((axis) => (axis['max'] as num?)?.toDouble() ?? 1)
        .toList();
    final values = series
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final raw = item['values'];
          return raw is List
              ? raw.map((value) => (value as num?)?.toDouble() ?? 0).toList()
              : <double>[];
        })
        .where((item) => item.length == maxes.length)
        .toList();
    if (maxes.length != axes.length || values.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
        height: 220,
        width: double.infinity,
        child: CustomPaint(painter: _RadarChartPainter(maxes, values)));
  }
}

class _RadarChartPainter extends CustomPainter {
  _RadarChartPainter(this.maxes, this.series);
  final List<double> maxes;
  final List<List<double>> series;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .38;
    final count = maxes.length;
    Offset point(double r, int index) {
      final angle =
          -3.141592653589793 / 2 + index * 2 * 3.141592653589793 / count;
      return center + Offset(r * cos(angle), r * sin(angle));
    }

    final grid = Paint()
      ..color = const Color(0x44333333)
      ..style = PaintingStyle.stroke;
    for (var level = 1; level <= 4; level++) {
      final path = Path()
        ..moveTo(
            point(radius * level / 4, 0).dx, point(radius * level / 4, 0).dy);
      for (var i = 1; i < count; i++) {
        final p = point(radius * level / 4, i);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    for (var i = 0; i < count; i++)
      canvas.drawLine(center, point(radius, i), grid);
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple];
    for (var s = 0; s < series.length; s++) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final p = point(radius * (series[s][i] / maxes[i]).clamp(0, 1), i);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      final color = colors[s % colors.length];
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .18));
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) => true;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.series);
  final List<List<double?>> series;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final values = series.expand((item) => item).whereType<double>().toList();
    if (values.isEmpty) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max == min ? 1 : max - min;
    final grid = Paint()
      ..color = const Color(0x33222222)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple];
    for (var s = 0; s < series.length; s++) {
      final points = <Offset>[];
      final item = series[s];
      for (var i = 0; i < item.length; i++) {
        final value = item[i];
        if (value == null) continue;
        points.add(Offset(plot.left + plot.width * i / (item.length - 1),
            plot.bottom - (value - min) / range * plot.height));
      }
      if (points.length < 2) continue;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) path.lineTo(point.dx, point.dy);
      canvas.drawPath(
          path,
          Paint()
            ..color = colors[s % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.series != series;
}

class _ChartBars extends StatelessWidget {
  const _ChartBars({required this.items});
  final List<Object?> items;

  @override
  Widget build(BuildContext context) {
    final values = items.map((item) {
      if (item is Map<String, dynamic>)
        return (item['value'] as num?)?.toDouble() ?? 0;
      return 0.0;
    }).toList();
    final max = values.fold<double>(
        0, (current, value) => value > current ? value : current);
    if (max <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                  width: 90,
                  child:
                      Text(_label(items[i]), overflow: TextOverflow.ellipsis)),
              Expanded(
                  child: LinearProgressIndicator(
                      value: values[i] / max, minHeight: 10)),
              const SizedBox(width: 8),
              Text(_format(values[i]))
            ]),
          )
      ],
    );
  }

  String _label(Object? item) => item is Map<String, dynamic>
      ? '${item['name'] ?? item['label'] ?? ''}'
      : '';
  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}
