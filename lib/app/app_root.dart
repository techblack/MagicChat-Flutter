part of '../main.dart';

Uri? _resolveAssetUri(String? serverUrl, String value) {
  final parsed = Uri.tryParse(value);
  if (parsed == null || value.trim().isEmpty) return null;
  if (parsed.hasScheme) return parsed;
  final server = Uri.tryParse(serverUrl ?? '');
  return server == null ? null : server.resolve(value);
}

bool shouldShowLocalMessageNotification({
  required String conversationId,
  String? selectedConversationId,
  bool muted = false,
  String? senderId,
  String? currentUserId,
}) =>
    conversationId.isNotEmpty &&
    conversationId != selectedConversationId &&
    (senderId == null || currentUserId == null || senderId != currentUserId) &&
    !muted;

double effectiveInterfaceTextScale(
        TextScaler system, InterfaceFontScale interfaceScale) =>
    system.scale(16) / 16 * interfaceScale.ratio;

Uri buildThirdPartyLoginUri(String serverUrl, String providerKey) {
  final base = Uri.parse('${normalizeServerUrl(serverUrl)}/');
  return base.resolve(
      'api/client/auth/third-party/${Uri.encodeComponent(providerKey)}/start?redirect=/init');
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      kReleaseMode &&
      defaultTargetPlatform == TargetPlatform.macOS) {
    await FilePicker.skipEntitlementsChecks();
  }
  runApp(MagicChatApp(launchArguments: arguments));
}

class MagicChatApp extends StatefulWidget {
  const MagicChatApp(
      {this.launchArguments = const [],
      this.desktopAutoLaunch,
      this.desktopTray,
      this.desktopWindowController,
      super.key});
  final List<String> launchArguments;
  final DesktopAutoLaunchController? desktopAutoLaunch;
  final DesktopSystemTrayController? desktopTray;
  final DesktopWindowController? desktopWindowController;
  @override
  State<MagicChatApp> createState() => _MagicChatAppState();
}

class _MagicChatAppState extends State<MagicChatApp> {
  MagicChatRepository? _repository;
  RealtimeSession? _realtime;
  final _realtimeStore = RealtimeStore();
  ThemeMode _themeMode = ThemeMode.system;
  ChatAppearance _chatAppearance = const ChatAppearance();
  final _conversationAppearances = <String, ChatConversationAppearance>{};
  bool _messageSoundEnabled = true;
  MessageNotificationPrivacy _notificationPrivacy =
      MessageNotificationPrivacy.preview;
  InterfaceFontScale _interfaceFontScale = InterfaceFontScale.normal;
  DesktopCloseBehavior _desktopCloseBehavior = DesktopCloseBehavior.background;
  String? _serverUrl;
  String? _loginError;
  bool _loading = true;
  bool _sessionExpiring = false;
  late final DesktopAutoLaunchController _desktopAutoLaunch;
  late final DesktopSystemTrayController _desktopTray;
  late final DesktopWindowController _desktopWindowController;
  String? _trayConversationId;
  int _trayOpenRequest = 0;

  @override
  void initState() {
    super.initState();
    _desktopAutoLaunch = widget.desktopAutoLaunch ?? DesktopAutoLaunchService();
    _desktopTray = widget.desktopTray ?? DesktopSystemTray();
    _desktopWindowController = widget.desktopWindowController ??
        const PlatformDesktopWindowController();
    unawaited(_initializeDesktopIntegration());
    _restoreSession();
  }

  Future<void> _initializeDesktopIntegration() async {
    var trayReady = false;
    try {
      trayReady =
          await _desktopTray.initialize(onOpenConversation: (conversationId) {
        if (!mounted) return;
        setState(() {
          _trayConversationId = conversationId;
          _trayOpenRequest++;
        });
      });
    } catch (_) {
      trayReady = false;
    }
    final hiddenRequested = isHiddenDesktopLaunch(widget.launchArguments);
    if (!hiddenRequested) return;
    var enabled = false;
    try {
      enabled = _desktopAutoLaunch.isSupported &&
          await _desktopAutoLaunch.isEnabled();
    } catch (_) {
      enabled = false;
    }
    if (!shouldKeepDesktopLaunchHidden(
        hiddenRequested: hiddenRequested,
        autoLaunchEnabled: enabled,
        trayReady: trayReady)) {
      try {
        await _desktopWindowController.show();
      } on PlatformException {
        // 非桌面平台不会收到系统自启动参数。
      } on MissingPluginException {
        // Runner 尚未提供窗口桥接时沿用平台默认显示行为。
      }
    }
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    const serverStore = ServerStore();
    await serverStore
        .rememberAccounts(await const SessionStore().readAccounts());
    final serverState = await serverStore.read();
    final server = prefs.getString('magicchat.server_url') ??
        serverState.selectedServer.url;
    final token = await const SessionStore().readToken();
    final theme = prefs.getString('magicchat.theme');
    final chatAppearance = await const ChatAppearancePreferences().readGlobal();
    final messageSoundEnabled =
        await const ChatPreferences().readMessageSoundEnabled();
    final notificationPrivacy =
        await const ChatPreferences().readNotificationPrivacy();
    final interfaceFontScale =
        await const ChatPreferences().readInterfaceFontScale();
    final desktopCloseBehavior =
        await const ChatPreferences().readDesktopCloseBehavior();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      await _desktopWindowController.setCloseBehavior(desktopCloseBehavior);
    }
    if (!mounted) return;
    setState(() {
      _serverUrl = server;
      _repository = token != null ? _createRepository(server, token) : null;
      _realtime = token != null
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
      _chatAppearance = chatAppearance;
      _messageSoundEnabled = messageSoundEnabled;
      _notificationPrivacy = notificationPrivacy;
      _interfaceFontScale = interfaceFontScale;
      _desktopCloseBehavior = desktopCloseBehavior;
    });
    if (token != null) {
      unawaited(_registerPush(server, token));
    }
  }

  Future<void> _login(String server, String email, String password) async {
    await AuthService()
        .login(serverUrl: server, email: email, password: password);
    final prefs = await SharedPreferences.getInstance();
    final token = await const SessionStore().readToken();
    await prefs.setString('magicchat.server_url', server);
    await const ServerStore().rememberUrl(server, select: true, recent: true);
    if (token == null) {
      throw const FormatException('无法保存登录会话，请检查系统安全存储权限');
    }
    if (!mounted) return;
    await const SessionStore().saveAccount(StoredAccount(
        id: '$server|$email', serverUrl: server, token: token, email: email));
    setState(() {
      _serverUrl = server;
      _loginError = null;
      _repository = _createRepository(server, token);
      _realtime = RealtimeSession(
          realtime: MagicChatRealtime(
              serverUrl: server,
              sessionToken: token,
              connector: connectWithAuthorization));
    });
    unawaited(_registerPush(server, token));
  }

  Future<void> _loginWithCode(String server, String email, String code) async {
    await AuthService()
        .loginWithEmailCode(serverUrl: server, email: email, code: code);
    final prefs = await SharedPreferences.getInstance();
    final token = await const SessionStore().readToken();
    await prefs.setString('magicchat.server_url', server);
    await const ServerStore().rememberUrl(server, select: true, recent: true);
    if (token == null) {
      throw const FormatException('无法保存登录会话，请检查系统安全存储权限');
    }
    if (!mounted) return;
    await const SessionStore().saveAccount(StoredAccount(
        id: '$server|$email', serverUrl: server, token: token, email: email));
    setState(() {
      _serverUrl = server;
      _loginError = null;
      _repository = _createRepository(server, token);
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

  HttpMagicChatRepository _createRepository(String server, String token) =>
      HttpMagicChatRepository(
          serverUrl: server,
          sessionToken: token,
          onUnauthorized: () => unawaited(_expireSession(server, token)));

  Future<void> _expireSession(String server, String token) async {
    final current = _repository;
    if (current is! HttpMagicChatRepository ||
        current.sessionToken != token ||
        _serverUrl != server) {
      return;
    }
    if (_sessionExpiring) return;
    _sessionExpiring = true;
    await const SessionStore()
        .markAccountReauthRequired(serverUrl: server, token: token);
    await _realtime?.close();
    await const SessionStore().clear();
    await MessageCacheStore().clearAll();
    await ContactCacheStore().clearAll();
    await LocalAssetCache().clearAll();
    await const AppBadgeService().setCount(0);
    _realtimeStore.reset();
    if (mounted) {
      setState(() {
        _repository = null;
        _realtime = null;
        _loginError = '登录已过期，请重新登录';
      });
    }
    _sessionExpiring = false;
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString('magicchat.server_url');
    final token = await const SessionStore().readToken();
    if (server != null && token != null) {
      await _revokePush(server, token);
      await const SessionStore()
          .markAccountReauthRequired(serverUrl: server, token: token);
    }
    if (server != null) {
      try {
        await AuthService().logout(serverUrl: server);
      } catch (_) {
        // 远端不可达时仍完成本地注销。
      }
    } else {
      await const SessionStore().clear();
    }
    await prefs.remove('magicchat.server_url');
    await MessageCacheStore().clearAll();
    await ContactCacheStore().clearAll();
    await LocalAssetCache().clearAll();
    await const AppBadgeService().setCount(0);
    await _realtime?.close();
    _realtimeStore.reset();
    final selectedServer =
        (await const ServerStore().read()).selectedServer.url;
    if (mounted) {
      setState(() {
        _repository = null;
        _realtime = null;
        _serverUrl = selectedServer;
        _loginError = null;
      });
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('magicchat.theme', mode.name);
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _setChatAppearance(ChatAppearance appearance) async {
    await const ChatAppearancePreferences().writeGlobal(appearance);
    if (mounted) setState(() => _chatAppearance = appearance);
  }

  Future<void> _setMessageSoundEnabled(bool enabled) async {
    await const ChatPreferences().writeMessageSoundEnabled(enabled);
    if (mounted) setState(() => _messageSoundEnabled = enabled);
  }

  Future<void> _setNotificationPrivacy(
      MessageNotificationPrivacy privacy) async {
    await const ChatPreferences().writeNotificationPrivacy(privacy);
    if (mounted) setState(() => _notificationPrivacy = privacy);
  }

  Future<void> _setInterfaceFontScale(InterfaceFontScale scale) async {
    await const ChatPreferences().writeInterfaceFontScale(scale);
    if (mounted) setState(() => _interfaceFontScale = scale);
  }

  Future<void> _setDesktopCloseBehavior(DesktopCloseBehavior behavior) async {
    await _desktopWindowController.setCloseBehavior(behavior);
    await const ChatPreferences().writeDesktopCloseBehavior(behavior);
    if (mounted) setState(() => _desktopCloseBehavior = behavior);
  }

  Future<void> _setConversationAppearance(
      String conversationId, ChatConversationAppearance appearance) async {
    await const ChatAppearancePreferences()
        .writeConversation(conversationId, appearance);
    if (mounted) {
      setState(() => _conversationAppearances[conversationId] = appearance);
    }
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
    await MessageCacheStore().clearAll();
    await ContactCacheStore().clearAll();
    await LocalAssetCache().clearAll();
    await const AppBadgeService().setCount(0);
    _realtimeStore.reset();
    await const ServerStore().rememberUrl(normalized, select: true);
    await prefs.setString('magicchat.server_url', normalized);
    if (mounted)
      setState(() {
        _repository = null;
        _realtime = null;
        _serverUrl = normalized;
        _loginError = null;
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
    _realtimeStore.reset();
    await const SessionStore().writeToken(account.token);
    await const AppBadgeService().setCount(0);

    await prefs.setString('magicchat.server_url', account.serverUrl);
    await const ServerStore()
        .rememberUrl(account.serverUrl, select: true, recent: true);
    if (!mounted) return;
    setState(() {
      _serverUrl = account.serverUrl;
      _loginError = null;
      _repository = _createRepository(account.serverUrl, account.token);
      _realtime = RealtimeSession(
          realtime: MagicChatRealtime(
              serverUrl: account.serverUrl,
              sessionToken: account.token,
              connector: connectWithAuthorization));
    });
    unawaited(_registerPush(account.serverUrl, account.token));
  }

  Future<void> _deactivateAccount(String code) async {
    final preferences = await SharedPreferences.getInstance();
    final server = _serverUrl ?? preferences.getString('magicchat.server_url');
    final sessions = const SessionStore();
    final token = await sessions.readToken();
    if (server == null || token == null) {
      throw const AuthRequestException('当前账号已失效');
    }

    try {
      await AuthService().deactivateAccount(serverUrl: server, code: code);
    } catch (error) {
      if (error is FormatException ||
          isSafeAccountDeactivationRejection(error)) {
        rethrow;
      }
      await sessions.markAccountReauthRequired(serverUrl: server, token: token);
      await _realtime?.close();
      await sessions.clear();
      await preferences.setString('magicchat.server_url', server);
      _realtimeStore.reset();
      await const AppBadgeService().setCount(0);
      if (mounted) {
        setState(() {
          _repository = null;
          _realtime = null;
          _serverUrl = server;
          _loginError = '账号状态需要重新确认，请重新登录';
        });
      }
      rethrow;
    }

    await _realtime?.close();
    final removed =
        await sessions.removeAccountForSession(serverUrl: server, token: token);
    final remaining = (await sessions.readAccounts())
        .where(
            (account) => account.serverUrl != server || account.token != token)
        .toList(growable: false);
    final candidate = selectRecentReadyAccount(remaining, removed?.id);
    await sessions.clear();
    await MessageCacheStore().clearAll();
    await ContactCacheStore().clearAll();
    await LocalAssetCache().clearAll();
    await const AppBadgeService().setCount(0);
    _realtimeStore.reset();

    if (candidate != null) {
      await preferences.remove('magicchat.server_url');
      await _switchAccount(candidate);
      return;
    }

    final selectedServer =
        (await const ServerStore().read()).selectedServer.url;
    await preferences.remove('magicchat.server_url');
    if (mounted) {
      setState(() {
        _repository = null;
        _realtime = null;
        _serverUrl = selectedServer;
        _loginError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MagicChat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: _chatAppearance.skin.seedColor,
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
                seedColor: _chatAppearance.skin.seedColor,
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
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(effectiveInterfaceTextScale(
                  media.textScaler, _interfaceFontScale)),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: _loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _repository == null
                ? LoginPage(
                    onLogin: _login,
                    onCodeLogin: _loginWithCode,
                    initialServer: _serverUrl,
                    initialError: _loginError)
                : AppShell(
                    key: ValueKey(_repository),
                    repository: _repository!,
                    serverUrl: _serverUrl,
                    onServerChanged: _changeServer,
                    onAccountSwitch: _switchAccount,
                    realtime: _realtime,
                    realtimeStore: _realtimeStore,
                    onLogout: _logout,
                    onDeactivateAccount: _deactivateAccount,
                    onThemeChanged: _setTheme,
                    chatAppearance: _chatAppearance,
                    conversationAppearances: _conversationAppearances,
                    onChatAppearanceChanged: _setChatAppearance,
                    onConversationAppearanceChanged: _setConversationAppearance,
                    messageSoundEnabled: _messageSoundEnabled,
                    onMessageSoundChanged: _setMessageSoundEnabled,
                    notificationPrivacy: _notificationPrivacy,
                    onNotificationPrivacyChanged: _setNotificationPrivacy,
                    interfaceFontScale: _interfaceFontScale,
                    onInterfaceFontScaleChanged: _setInterfaceFontScale,
                    desktopCloseBehavior: _desktopCloseBehavior,
                    onDesktopCloseBehaviorChanged: _setDesktopCloseBehavior,
                    desktopTray: _desktopTray,
                    trayConversationId: _trayConversationId,
                    trayOpenRequest: _trayOpenRequest,
                    themeMode: _themeMode),
      );

  @override
  void dispose() {
    unawaited(_desktopTray.dispose());
    super.dispose();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage(
      {required this.onLogin,
      required this.onCodeLogin,
      this.initialServer,
      this.initialError,
      this.authService,
      this.serverStore,
      super.key});
  final Future<void> Function(String server, String email, String password)
      onLogin;
  final Future<void> Function(String server, String email, String code)
      onCodeLogin;
  final String? initialServer;
  final String? initialError;
  final AuthService? authService;
  final ServerStore? serverStore;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverFieldKey = GlobalKey<FormFieldState<String>>();
  final _emailFieldKey = GlobalKey<FormFieldState<String>>();
  late final TextEditingController _server = TextEditingController(
      text: widget.initialServer ?? 'https://app.jiying.chat');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _submitting = false;
  bool _sendingCode = false;
  bool _codeMode = false;
  bool _passwordVisible = false;
  bool _legalConsentAccepted = false;
  bool _infoLoading = false;
  ClientAppInfo? _appInfo;
  late String? _error = widget.initialError;
  String? _serverStatus;
  int _infoGeneration = 0;
  int _resendIn = 0;
  Timer? _resendTimer;

  late final AuthService _authService = widget.authService ?? AuthService();
  late final ServerStore _serverStore =
      widget.serverStore ?? const ServerStore();

  Future<void> _openServerManagement() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => ServerManagementPage(store: _serverStore)),
    );
    if (selected == null || !mounted) return;
    _server.text = selected;
    _onServerChanged(selected);
    await _loadAppInfo();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppInfo());
  }

  Future<void> _loadAppInfo() async {
    String server;
    try {
      server = normalizeServerUrl(_server.text);
    } catch (error) {
      if (mounted) setState(() => _serverStatus = _errorText(error));
      return;
    }
    if (_infoLoading) return;
    final generation = ++_infoGeneration;
    setState(() {
      _infoLoading = true;
      _serverStatus = null;
    });
    try {
      final info = await _authService.fetchClientInfo(serverUrl: server);
      if (!mounted ||
          generation != _infoGeneration ||
          normalizeServerUrl(_server.text) != server) {
        return;
      }
      setState(() {
        _server.text = server;
        _appInfo = info;
        _serverStatus = _loginCapabilityText(info);
        if (!info.passwordLoginEnabled && info.emailCodeLoginEnabled) {
          _codeMode = true;
        } else if (!info.emailCodeLoginEnabled) {
          _codeMode = false;
        }
      });
    } catch (error) {
      if (mounted && generation == _infoGeneration) {
        setState(() => _serverStatus = '连接检查失败：${_errorText(error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _infoLoading = false);
      }
    }
  }

  void _onServerChanged(String value) {
    _infoGeneration++;
    if (_appInfo == null && _error == null && !_codeMode) return;
    setState(() {
      _appInfo = null;
      _error = null;
      _serverStatus = null;
      _codeMode = false;
    });
  }

  String _loginCapabilityText(ClientAppInfo info) {
    final methods = <String>[
      if (info.passwordLoginEnabled) '密码',
      if (info.emailCodeLoginEnabled) '邮箱验证码',
    ];
    return methods.isEmpty
        ? '服务器已连接，但未开放可用登录方式'
        : '服务器已连接 · 支持${methods.join('、')}登录';
  }

  String? _validateServer(String? value) {
    try {
      normalizeServerUrl(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return '请输入邮箱';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return '请输入有效的邮箱地址';
    }
    return null;
  }

  String? _validateSecret(String? value) {
    if (_codeMode) {
      return RegExp(r'^\d{8}$').hasMatch(value?.trim() ?? '')
          ? null
          : '请输入 8 位邮箱验证码';
    }
    return (value ?? '').isEmpty ? '请输入密码' : null;
  }

  String _errorText(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) return '请求超时，请检查网络和服务器地址';
    final message = error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|ClientException):\s*'), '');
    if (message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('XMLHttpRequest error')) {
      return '无法连接到服务器，请检查网络和服务器地址';
    }
    return message;
  }

  Future<void> _requestEmailCode() async {
    if (_submitting || _sendingCode || _resendIn > 0) return;
    final valid = (_serverFieldKey.currentState?.validate() ?? false) &
        (_emailFieldKey.currentState?.validate() ?? false);
    if (!valid) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sendingCode = true;
      _error = null;
    });
    try {
      final server = normalizeServerUrl(_server.text);
      final result = await _authService.requestEmailCode(
          serverUrl: server, email: _email.text.trim());
      if (!mounted) return;
      _server.text = server;
      _startResendTimer(result.retryAfterSeconds);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('验证码已发送，${result.expiresInSeconds} 秒内有效')));
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _submit() async {
    if (_submitting ||
        _sendingCode ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!_legalConsentAccepted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先阅读并同意用户协议和隐私政策')));
      return;
    }
    FocusScope.of(context).unfocus();
    final server = normalizeServerUrl(_server.text);
    setState(() {
      _submitting = true;
      _error = null;
      _server.text = server;
    });
    try {
      if (_codeMode) {
        await widget.onCodeLogin(server, _email.text.trim(), _code.text.trim());
      } else {
        await widget.onLogin(server, _email.text.trim(), _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _startThirdPartyLogin(ClientThirdPartyProvider provider) async {
    if (_submitting || !kIsWeb) return;
    try {
      final server = normalizeServerUrl(_server.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('magicchat.server_url', server);
      await _serverStore.rememberUrl(server, select: true);
      await const SessionStore().writeToken(SessionStore.cookieSessionToken);
      final launched = await launchUrl(
          buildThirdPartyLoginUri(server, provider.key),
          mode: LaunchMode.platformDefault);
      if (!launched && mounted) {
        await const SessionStore().clear();
        await prefs.remove('magicchat.server_url');
        setState(() => _error = '无法打开第三方登录页面');
      }
    } catch (error) {
      await const SessionStore().clear();
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _openLegalDocument(String url) async {
    final launched = await launchExternalWebLink(context, Uri.parse(url));
    if (launched == false && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法打开协议页面，请稍后重试')));
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.forum_rounded,
                                  size: 32,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text('登录 MagicChat',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 6),
                              Text(
                                '连接你的团队工作空间',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                key: _serverFieldKey,
                                controller: _server,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.url],
                                validator: _validateServer,
                                decoration: InputDecoration(
                                  labelText: '服务器地址',
                                  hintText: 'https://chat.example.com',
                                  prefixIcon: const Icon(Icons.dns_outlined),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: '检查服务器',
                                        onPressed:
                                            _infoLoading ? null : _loadAppInfo,
                                        icon: _infoLoading
                                            ? const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(Icons.refresh),
                                      ),
                                      IconButton(
                                          tooltip: '服务器管理',
                                          onPressed: _submitting
                                              ? null
                                              : _openServerManagement,
                                          icon: const Icon(Icons.dns_outlined)),
                                    ],
                                  ),
                                ),
                                onChanged: _onServerChanged,
                                onFieldSubmitted: (_) => _loadAppInfo(),
                              ),
                              if (_serverStatus != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _appInfo == null
                                            ? Icons.info_outline
                                            : Icons.check_circle_outline,
                                        size: 17,
                                        color: _appInfo == null
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _serverStatus!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: _emailFieldKey,
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                autocorrect: false,
                                validator: _validateEmail,
                                decoration: const InputDecoration(
                                  labelText: '邮箱',
                                  prefixIcon: Icon(Icons.mail_outline),
                                ),
                              ),
                              if (_appInfo?.emailCodeLoginEnabled == true &&
                                  _appInfo?.passwordLoginEnabled == true)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _submitting || _sendingCode
                                        ? null
                                        : () => setState(
                                            () => _codeMode = !_codeMode),
                                    child: Text(
                                        _codeMode ? '使用密码登录' : '使用邮箱验证码登录'),
                                  ),
                                )
                              else
                                const SizedBox(height: 12),
                              if (_codeMode &&
                                  _appInfo?.emailCodeLoginEnabled == true)
                                TextFormField(
                                  controller: _code,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode
                                  ],
                                  maxLength: 8,
                                  validator: _validateSecret,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: '邮箱验证码',
                                    prefixIcon:
                                        const Icon(Icons.password_outlined),
                                    counterText: '',
                                    suffixIcon: TextButton(
                                      onPressed: _submitting ||
                                              _sendingCode ||
                                              _resendIn > 0
                                          ? null
                                          : _requestEmailCode,
                                      child: _sendingCode
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : Text(_resendIn > 0
                                              ? '${_resendIn}s'
                                              : '发送'),
                                    ),
                                  ),
                                )
                              else if (_appInfo?.passwordLoginEnabled != false)
                                TextFormField(
                                  controller: _password,
                                  obscureText: !_passwordVisible,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  validator: _validateSecret,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip:
                                          _passwordVisible ? '隐藏密码' : '显示密码',
                                      onPressed: () => setState(() =>
                                          _passwordVisible = !_passwordVisible),
                                      icon: Icon(_passwordVisible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined),
                                    ),
                                  ),
                                ),
                              if (_error != null)
                                Semantics(
                                  liveRegion: true,
                                  child: Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Semantics(
                                label: '同意用户协议和隐私政策',
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      value: _legalConsentAccepted,
                                      onChanged: _submitting
                                          ? null
                                          : (value) => setState(() =>
                                              _legalConsentAccepted =
                                                  value == true),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            const Text('我已阅读并同意 '),
                                            InkWell(
                                              onTap: () => unawaited(
                                                  _openLegalDocument(
                                                      magicChatUserAgreementUrl)),
                                              child: Text('《用户协议》',
                                                  style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      decoration: TextDecoration
                                                          .underline)),
                                            ),
                                            const Text(' 和 '),
                                            InkWell(
                                              onTap: () => unawaited(
                                                  _openLegalDocument(
                                                      magicChatPrivacyPolicyUrl)),
                                              child: Text('《隐私政策》',
                                                  style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      decoration: TextDecoration
                                                          .underline)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _submitting ||
                                          _sendingCode ||
                                          (_codeMode &&
                                              _appInfo?.emailCodeLoginEnabled !=
                                                  true) ||
                                          (!_codeMode &&
                                              _appInfo?.passwordLoginEnabled ==
                                                  false)
                                      ? null
                                      : _submit,
                                  child: _submitting
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Text('登录'),
                                ),
                              ),
                              if (kIsWeb &&
                                  _appInfo?.thirdPartyProviders.isNotEmpty ==
                                      true) ...[
                                const SizedBox(height: 20),
                                Row(children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text('其他登录方式',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium)),
                                  const Expanded(child: Divider()),
                                ]),
                                const SizedBox(height: 10),
                                ..._appInfo!.thirdPartyProviders.map(
                                  (provider) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _submitting
                                            ? null
                                            : () =>
                                                _startThirdPartyLogin(provider),
                                        icon: const Icon(Icons.login_outlined),
                                        label: Text('使用 ${provider.name} 登录'),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
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
      this.onDeactivateAccount,
      this.onThemeChanged,
      this.chatAppearance = const ChatAppearance(),
      this.conversationAppearances = const {},
      this.onChatAppearanceChanged,
      this.onConversationAppearanceChanged,
      this.messageSoundEnabled = true,
      this.onMessageSoundChanged,
      this.notificationPrivacy = MessageNotificationPrivacy.preview,
      this.onNotificationPrivacyChanged,
      this.interfaceFontScale = InterfaceFontScale.normal,
      this.onInterfaceFontScaleChanged,
      this.desktopCloseBehavior = DesktopCloseBehavior.background,
      this.onDesktopCloseBehaviorChanged,
      this.desktopTray,
      this.trayConversationId,
      this.trayOpenRequest = 0,
      this.desktopSearchShortcut,
      this.themeMode = ThemeMode.system,
      super.key});
  final MagicChatRepository repository;
  final String? serverUrl;
  final Future<void> Function(String server)? onServerChanged;
  final ValueChanged<StoredAccount>? onAccountSwitch;
  final RealtimeSession? realtime;
  final RealtimeStore? realtimeStore;
  final Future<void> Function()? onLogout;
  final Future<void> Function(String code)? onDeactivateAccount;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ChatAppearance chatAppearance;
  final Map<String, ChatConversationAppearance> conversationAppearances;
  final ValueChanged<ChatAppearance>? onChatAppearanceChanged;
  final Future<void> Function(
          String conversationId, ChatConversationAppearance appearance)?
      onConversationAppearanceChanged;
  final bool messageSoundEnabled;
  final ValueChanged<bool>? onMessageSoundChanged;
  final MessageNotificationPrivacy notificationPrivacy;
  final ValueChanged<MessageNotificationPrivacy>? onNotificationPrivacyChanged;
  final InterfaceFontScale interfaceFontScale;
  final ValueChanged<InterfaceFontScale>? onInterfaceFontScaleChanged;
  final DesktopCloseBehavior desktopCloseBehavior;
  final ValueChanged<DesktopCloseBehavior>? onDesktopCloseBehaviorChanged;
  final DesktopSystemTrayController? desktopTray;
  final String? trayConversationId;
  final int trayOpenRequest;
  final DesktopSearchShortcutController? desktopSearchShortcut;
  final ThemeMode themeMode;
  @override
  State<AppShell> createState() => _AppShellState();
}

typedef _AppNavigationLocation = ({
  int index,
  String? selectedConversation,
  String? focusMessageId,
  int? focusMessageSequence,
  String? focusContactId,
  ContactDirectoryCategory? focusContactCategory,
  String? focusProjectId,
  String? focusTaskProjectId,
  String? focusTaskId,
  String? focusDocumentId,
  bool focusRouteReturnsToSource,
});

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final MagicChatRepository _repository = widget.repository;
  String? _currentUserId;
  bool _identityReady = false;
  bool _realtimeReconnecting = false;
  int _index = 0;
  int _messagesReselectToken = 0;
  String? _selectedConversation;
  String? _focusMessageId;
  int? _focusMessageSequence;
  String? _focusContactId;
  ContactDirectoryCategory? _focusContactCategory;
  String? _focusProjectId;
  String? _focusTaskProjectId;
  String? _focusTaskId;
  String? _focusDocumentId;
  bool _focusRouteReturnsToSource = false;
  int _unreadCount = 0;
  MessageSendShortcut _sendMessageShortcut = MessageSendShortcut.enter;
  DesktopScreenshotShortcut _screenshotShortcut =
      DesktopScreenshotShortcut.defaultFor(defaultTargetPlatform);
  DesktopSearchShortcut _searchShortcut =
      DesktopSearchShortcut.defaultFor(defaultTargetPlatform);
  int _screenshotRequestToken = 0;
  final _navigationHistory = <_AppNavigationLocation>[];
  final _contactCacheStore = ContactCacheStore();
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  final _notifications = const LocalNotificationService();
  final _pushTokenProvider = const PushTokenProvider();
  final _appBadge = const AppBadgeService();
  final _desktopScreenshot = DesktopScreenshotController();
  late final DesktopSearchShortcutController _desktopSearchShortcut =
      widget.desktopSearchShortcut ?? DesktopSearchShortcutController();
  final _desktopWindow = const PlatformDesktopWindowController();
  final _messageCacheStore = MessageCacheStore();
  final _conversationDraftStore = ConversationDraftStore();
  final _handledNotificationRoutes = <String>{};
  final _loadedConversationAppearances = <String, ChatConversationAppearance>{};
  bool _searchDialogOpen = false;

  Future<void> _loadConversationAppearance(String conversationId) async {
    if (conversationId.isEmpty ||
        widget.conversationAppearances.containsKey(conversationId) ||
        _loadedConversationAppearances.containsKey(conversationId)) return;
    final appearance = await const ChatAppearancePreferences()
        .readConversationOverride(conversationId,
            fallback: ChatConversationAppearance(
                background: widget.chatAppearance.background,
                bubble: widget.chatAppearance.bubble));
    if (mounted &&
        appearance != null &&
        !widget.conversationAppearances.containsKey(conversationId) &&
        !_loadedConversationAppearances.containsKey(conversationId)) {
      setState(
          () => _loadedConversationAppearances[conversationId] = appearance);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushTokenProvider
        .setRouteOpenedHandler((route) => _openPendingPushRoute(route));
    unawaited(_loadChatPreferences());
    final realtime = widget.realtime;
    final store = widget.realtimeStore;
    if (realtime != null && store != null) {
      unawaited(_startRealtime(realtime, store));
    }
    if (realtime == null || store == null) {
      unawaited(_loadCurrentUser());
    }
    _resolveNotificationRoute(recordSource: false);
    unawaited(_restoreMobileImageRecoveryRoute());
    if (widget.trayOpenRequest > 0 && widget.trayConversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openConversation(widget.trayConversationId!, recordSource: false);
        }
      });
    }
  }

  Future<void> _restoreMobileImageRecoveryRoute() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = await SharedPreferences.getInstance();
    final conversationId =
        prefs.getString(mobileImageRecoveryConversationKey)?.trim();
    if (!mounted || conversationId == null || conversationId.isEmpty) return;
    if (_selectedConversation == null) {
      _openConversation(conversationId, recordSource: false);
    }
  }

  void _syncDesktopTray() {
    final tray = widget.desktopTray;
    if (tray == null) return;
    unawaited(tray.update(
      unreadCount: _unreadCount,
      conversations: widget.realtimeStore?.conversations.values ?? const [],
      contacts: widget.realtimeStore?.contacts ?? const {},
      privacy: widget.notificationPrivacy,
    ));
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationPrivacy != widget.notificationPrivacy) {
      _syncDesktopTray();
    }
    if (oldWidget.trayOpenRequest != widget.trayOpenRequest &&
        widget.trayConversationId != null) {
      _openConversation(widget.trayConversationId!);
    }
  }

  Future<void> _startRealtime(
      RealtimeSession realtime, RealtimeStore store) async {
    final rememberedId = await _readRememberedCurrentUserId();
    if (!mounted) return;
    if (rememberedId != null) {
      store.setCurrentUserId(rememberedId);
      await _conversationDraftStore.load(_messageCacheScopeFor(rememberedId));
      if (!mounted) return;
      setState(() {
        _currentUserId = rememberedId;
        _identityReady = true;
      });
      _listenRealtime(realtime, store);
      unawaited(_loadCurrentUser(store: store));
      return;
    }
    await _loadCurrentUser(store: store);
    if (!mounted) return;
    _listenRealtime(realtime, store);
  }

  void _listenRealtime(RealtimeSession realtime, RealtimeStore store) {
    try {
      _realtimeSubscription ??= realtime.events.asyncMap((event) async {
        await applyRealtimeEventAfterPersistence(
            store: store,
            event: event,
            persist: (message) => _persistRealtimeMessage(store, message));
        return event;
      }).listen((event) {
        final eventName = event['event'];
        if (eventName == 'system.connection_lost' ||
            eventName == 'system.connection_error') {
          if (mounted && !_realtimeReconnecting) {
            setState(() => _realtimeReconnecting = true);
          }
        } else if (eventName == 'system.ready' &&
            mounted &&
            _realtimeReconnecting) {
          setState(() => _realtimeReconnecting = false);
        }
        unawaited(_notifyIncomingMessage(event));
      });
      realtime.connect();
    } catch (_) {
      // RealtimeSession 自身会负责连接重试；初始化失败不阻断缓存浏览。
    }
  }

  void _retryRealtime() {
    final realtime = widget.realtime;
    if (realtime == null) return;
    unawaited(realtime.reconnect());
  }

  Future<void> _loadCurrentUser({RealtimeStore? store}) async {
    try {
      final user = await widget.repository.currentUser();
      if (!mounted) return;
      store?.setCurrentUserId(user.id);
      await _rememberCurrentUser(user);
      await _conversationDraftStore.load(_messageCacheScopeFor(user.id));
      if (!mounted) return;
      if (mounted && _currentUserId != user.id) {
        setState(() => _currentUserId = user.id);
      }
    } catch (_) {
      // 当前用户接口失败不阻断已缓存内容；实时重连后仍可继续刷新。
    } finally {
      if (mounted && !_identityReady) {
        setState(() => _identityReady = true);
      }
    }
  }

  Future<void> _persistRealtimeMessage(
      RealtimeStore store, ChatMessage message) async {
    final scope = _messageCacheScope;
    final conversationId = message.conversationId;
    if (scope == null || conversationId == null || conversationId.isEmpty)
      return;
    final type = store.conversations[conversationId]?.type ?? 'direct';
    await _messageCacheStore.upsert(
        scope, conversationId, messageCacheRecord(message),
        conversationType: type);
  }

  Future<void> _rememberCurrentUser(CurrentUser user) async {
    final server = widget.serverUrl?.trim();
    if (server == null || server.isEmpty || user.id.trim().isEmpty) return;
    await _contactCacheStore
        .write(MessageCacheScope(serverUrl: server, userId: user.id), [
      Contact(
          id: user.id,
          name: user.name,
          nickname: user.nickname,
          email: user.email,
          phone: user.phone,
          avatar: user.avatar),
    ]);
    final key = _rememberedCurrentUserKey;
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, user.id);
    }
  }

  String? get _rememberedCurrentUserKey {
    final server = widget.serverUrl?.trim();
    final repository = widget.repository;
    if (server == null ||
        server.isEmpty ||
        repository is! HttpMagicChatRepository) return null;
    final identity = sha256.convert(utf8.encode(repository.sessionToken));
    return 'magicchat.current-user.${base64Url.encode(utf8.encode(server)).replaceAll('=', '')}.$identity';
  }

  Future<String?> _readRememberedCurrentUserId() async {
    final key = _rememberedCurrentUserKey;
    if (key == null) return null;
    final value =
        (await SharedPreferences.getInstance()).getString(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _loadChatPreferences() async {
    final values = await Future.wait([
      const ChatPreferences().readSendShortcut(),
      const DesktopScreenshotPreferences().read(defaultTargetPlatform),
      const DesktopSearchShortcutPreferences().read(defaultTargetPlatform),
    ]);
    if (!mounted) return;
    final sendShortcut = values[0] as MessageSendShortcut;
    final screenshotShortcut = values[1] as DesktopScreenshotShortcut;
    final searchShortcut = values[2] as DesktopSearchShortcut;
    setState(() {
      _sendMessageShortcut = sendShortcut;
      _screenshotShortcut = screenshotShortcut;
      _searchShortcut = searchShortcut;
    });
    final registered = await _desktopScreenshot.configure(
        screenshotShortcut, _triggerScreenshotFromShortcut);
    if (!registered && screenshotShortcut.enabled && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('截图快捷键注册失败，可在设置中修改或禁用')));
        }
      });
    }
    final searchRegistered = await _desktopSearchShortcut.configure(
        searchShortcut, _triggerGlobalSearchShortcut);
    if (!searchRegistered && searchShortcut.enabled && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('全局搜索快捷键注册失败，可在设置中修改或禁用')));
        }
      });
    }
  }

  Future<bool> _updateScreenshotShortcut(
      DesktopScreenshotShortcut shortcut) async {
    final registered = await _desktopScreenshot.configure(
        shortcut, _triggerScreenshotFromShortcut);
    if (!registered || !mounted) return registered;
    setState(() => _screenshotShortcut = shortcut);
    return true;
  }

  Future<DesktopShortcutUpdateStatus> _updateSearchShortcut(
      DesktopSearchShortcut shortcut) async {
    final previous = _searchShortcut;
    final status = await updateDesktopShortcut(
      previous: previous,
      candidate: shortcut,
      configure: (value) =>
          _desktopSearchShortcut.configure(value, _triggerGlobalSearchShortcut),
      persist: const DesktopSearchShortcutPreferences().write,
    );
    if (status == DesktopShortcutUpdateStatus.updated && mounted) {
      setState(() => _searchShortcut = shortcut);
    }
    return status;
  }

  Future<bool> _setSearchShortcutRecording(bool recording) => recording
      ? _desktopSearchShortcut.beginRecording()
      : _desktopSearchShortcut.cancelRecording();

  Future<void> _triggerGlobalSearchShortcut() async {
    await _desktopWindow.show();
    if (mounted) await _showSearch(context);
  }

  Future<void> _triggerScreenshotFromShortcut() async {
    await _desktopWindow.show();
    if (!mounted) return;
    final conversationId = _selectedConversation;
    if (conversationId == null || conversationId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先打开一个会话再截图')));
      return;
    }
    final conversation = widget.realtimeStore?.conversations[conversationId];
    if (conversation?.canSend == false ||
        conversation?.topic?.archived == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前会话为只读，无法发送截图')));
      return;
    }
    setState(() {
      _index = 0;
      _screenshotRequestToken++;
    });
  }

  Future<void> _notifyIncomingMessage(Map<String, dynamic> event) async {
    if (event['event'] != 'message.created') return;
    final payload = event['payload'];
    if (payload is! Map<String, dynamic>) return;
    final message = payload['message'];
    final data = message is Map<String, dynamic> ? message : payload;
    final conversationId = data['conversation_id'];
    final sender = data['sender'];
    final senderId = sender is Map<String, dynamic> ? sender['id'] : null;
    if (conversationId is! String ||
        !shouldShowLocalMessageNotification(
            conversationId: conversationId,
            selectedConversationId: _selectedConversation,
            senderId: senderId is String ? senderId : null,
            currentUserId: widget.realtimeStore?.currentUserId,
            muted: widget.realtimeStore?.conversations[conversationId]?.muted ==
                true)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('magicchat.notifications.enabled') ?? true)) return;
    if (widget.messageSoundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.alert).catchError((_) {}));
    }
    final senderTitle =
        sender is Map<String, dynamic> && sender['name'] is String
            ? sender['name'] as String
            : '新消息';
    final body =
        MessageContent.fromEnvelope(data['body'], revokedAt: data['revoked_at'])
            .text;
    final (title, notificationBody) = switch (widget.notificationPrivacy) {
      MessageNotificationPrivacy.hidden => ('新消息', '你收到了一条新消息'),
      MessageNotificationPrivacy.metadata => (senderTitle, '你收到了一条新消息'),
      MessageNotificationPrivacy.preview => (senderTitle, body),
    };
    await _notifications.showMessage(
        conversationId: conversationId,
        messageId: data['id'] is String ? data['id'] as String : '',
        title: title,
        body: notificationBody);
  }

  Future<void> _resolveNotificationRoute({bool recordSource = true}) async {
    final urlToken = Uri.base.queryParameters['route_token'];
    final urlConversationId = Uri.base.queryParameters['conversation_id'];
    final urlMessageId = Uri.base.queryParameters['message_id'];
    final pending = await _pushTokenProvider.takePendingRoute();
    final routeToken = urlToken?.trim().isNotEmpty == true
        ? urlToken!.trim()
        : pending?.routeToken ?? '';
    await _openPendingPushRoute(
        PendingPushRoute(
            routeToken: routeToken,
            conversationId: urlConversationId?.trim().isNotEmpty == true
                ? urlConversationId!.trim()
                : pending?.conversationId ?? '',
            messageId: urlMessageId?.trim().isNotEmpty == true
                ? urlMessageId!.trim()
                : pending?.messageId ?? ''),
        recordSource: recordSource);
  }

  Future<void> _openPendingPushRoute(PendingPushRoute pending,
      {bool recordSource = true}) async {
    final routeToken = pending.routeToken;
    if (routeToken.isEmpty) {
      final conversationId = pending.conversationId;
      if (conversationId.isEmpty) return;
      final messageId = pending.messageId;
      final key = 'message:$conversationId:$messageId';
      if (!_handledNotificationRoutes.add(key)) return;
      if (messageId.isEmpty) {
        _selectConversationFromList(conversationId, recordSource: recordSource);
      } else {
        _openMessageFromSearch(conversationId, messageId, null,
            recordSource: recordSource);
      }
      return;
    }
    if (widget.serverUrl == null) return;
    final key = 'token:$routeToken';
    if (!_handledNotificationRoutes.add(key)) return;
    try {
      final token = await const SessionStore().readToken();
      if (token == null) return;
      final route = await PushService().resolveRoute(
          serverUrl: widget.serverUrl!,
          sessionToken: token,
          routeToken: routeToken);
      if (mounted) {
        _openMessageFromSearch(route.conversationId, route.messageId, null,
            recordSource: recordSource);
      }
    } catch (_) {
      _handledNotificationRoutes.remove(key);
      // 通知路由失效时保留正常首页，不阻断主应用启动。
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushTokenProvider.setRouteOpenedHandler(null);
    _realtimeSubscription?.cancel();
    widget.realtime?.close();
    unawaited(_messageCacheStore.close());
    _conversationDraftStore.dispose();
    unawaited(_desktopScreenshot.dispose());
    unawaited(_desktopSearchShortcut.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resolveNotificationRoute());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_conversationDraftStore.flush());
    }
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
      !_identityReady
          ? const Center(child: CircularProgressIndicator())
          : MessagesPage(
              repository: _repository,
              serverUrl: widget.serverUrl,
              realtimeSession: widget.realtime,
              realtimeStore: widget.realtimeStore,
              cacheScope: _messageCacheScope,
              draftStore: _conversationDraftStore,
              sendMessageShortcut: _sendMessageShortcut,
              chatAppearance: widget.chatAppearance,
              conversationAppearance:
                  widget.conversationAppearances[_selectedConversation] ??
                      _loadedConversationAppearances[_selectedConversation],
              onConversationAppearanceChanged:
                  widget.onConversationAppearanceChanged,
              enableFileDrop: _index == 0,
              screenshotController: _desktopScreenshot,
              screenshotRequestToken: _screenshotRequestToken,
              selectedId: _selectedConversation,
              focusMessageId: _focusMessageId,
              focusMessageSequence: _focusMessageSequence,
              onSelect: _selectConversationFromList,
              onRestoreLastConversation: (id) {
                if (_index == 0 && _selectedConversation == null) {
                  _selectConversationFromList(id, recordSource: false);
                }
              },
              onOpenConversation: _openConversation,
              onConversationRemoved: _forgetConversation,
              onBack: _backConversation,
              onOpenMessage: _openMessageFromSearch,
              onOpenInternalLink: _openInternalMessageLink,
              onUnreadChanged: _setUnreadCount,
              messagesReselectToken: _messagesReselectToken,
              onMessageFocused: () {
                if (mounted) {
                  setState(() {
                    _focusMessageId = null;
                    _focusMessageSequence = null;
                  });
                }
              }),
      ContactsPage(
          repository: _repository,
          active: _index == 1,
          realtimeSession: widget.realtime,
          realtimeStore: widget.realtimeStore,
          serverUrl: widget.serverUrl,
          cacheScope: _messageCacheScope,
          initialContactId: _focusContactId,
          initialContactCategory: _focusContactCategory,
          onInitialContactOpened: () {
            if (mounted && _index == 1 && _focusContactId != null) {
              _completeFocusedRoute();
            }
          },
          onOpenConversation: (id, source) {
            if (source != null) {
              _focusContactId = source.contact.id;
              _focusContactCategory = source.category;
            }
            _openConversation(id);
          }),
      ProjectsPage(
          repository: _repository,
          realtimeSession: widget.realtime,
          initialProjectId: _focusProjectId,
          initialTaskProjectId: _focusTaskProjectId,
          initialTaskId: _focusTaskId,
          initialDocumentId: _focusDocumentId,
          onInitialProjectOpened: () {
            if (mounted && _index == 2 && _focusProjectId != null) {
              _completeFocusedRoute();
            }
          },
          onInitialTaskOpened: () {
            if (mounted &&
                _index == 2 &&
                _focusTaskProjectId != null &&
                _focusTaskId != null) {
              _completeFocusedRoute();
            }
          },
          onInitialDocumentOpened: () {
            if (mounted && _index == 2 && _focusDocumentId != null) {
              _completeFocusedRoute();
            }
          },
          documentCollaborationFactory: documentCollaborationFactory),
      SettingsPage(
          repository: _repository,
          realtimeSession: widget.realtime,
          realtimeStore: widget.realtimeStore,
          serverUrl: widget.serverUrl,
          cacheScope: _messageCacheScope,
          messageCacheStore: _messageCacheStore,
          onServerChanged: widget.onServerChanged,
          onAccountSwitch: widget.onAccountSwitch,
          onLogout: widget.onLogout,
          onDeactivateAccount: widget.onDeactivateAccount,
          onThemeChanged: widget.onThemeChanged,
          onSendMessageShortcutChanged: (shortcut) {
            setState(() => _sendMessageShortcut = shortcut);
          },
          screenshotShortcut: _screenshotShortcut,
          onScreenshotShortcutChanged: _updateScreenshotShortcut,
          searchShortcut: _searchShortcut,
          onSearchShortcutChanged: _updateSearchShortcut,
          onSearchShortcutRecordingChanged: _setSearchShortcutRecording,
          chatAppearance: widget.chatAppearance,
          onChatAppearanceChanged: widget.onChatAppearanceChanged,
          messageSoundEnabled: widget.messageSoundEnabled,
          onMessageSoundChanged: widget.onMessageSoundChanged,
          notificationPrivacy: widget.notificationPrivacy,
          onNotificationPrivacyChanged: widget.onNotificationPrivacyChanged,
          interfaceFontScale: widget.interfaceFontScale,
          onInterfaceFontScaleChanged: widget.onInterfaceFontScaleChanged,
          desktopCloseBehavior: widget.desktopCloseBehavior,
          onDesktopCloseBehaviorChanged: widget.onDesktopCloseBehaviorChanged,
          themeMode: widget.themeMode,
          sendMessageShortcut: _sendMessageShortcut),
    ];
    final destinations = [
      NavigationDestination(
          icon: _NavigationBadgeIcon(
              icon: Icons.chat_bubble_outline, count: _unreadCount),
          selectedIcon: _NavigationBadgeIcon(
              icon: Icons.chat_bubble, count: _unreadCount),
          label: '消息'),
      const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '联系人'),
      const NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: '项目'),
      const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置'),
    ];
    const sectionTitles = ['消息', '联系人', '项目', '设置'];
    final compactConversation =
        !wide && _index == 0 && _selectedConversation != null;
    return PopScope<void>(
      canPop: _navigationHistory.isEmpty &&
          _selectedConversation == null &&
          _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleSystemBack();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final keyboard = HardwareKeyboard.instance;
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyK &&
              (keyboard.isControlPressed || keyboard.isMetaPressed)) {
            unawaited(_showSearch(context));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          appBar: compactConversation
              ? null
              : AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('MagicChat',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(sectionTitles[_index],
                          key: const ValueKey('app-section-title'),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  letterSpacing: 0)),
                    ],
                  ),
                  actions: [
                      IconButton(
                          onPressed: () => _showSearch(context),
                          icon: const Icon(Icons.search),
                          tooltip: '搜索')
                    ]),
          body: Column(children: [
            if (_realtimeReconnecting)
              Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: Row(children: [
                    const SizedBox(width: 16),
                    Icon(Icons.sync_problem_outlined,
                        size: 18,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('实时连接已断开，正在重新连接；本地缓存仍可浏览',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer))),
                    TextButton(
                        onPressed:
                            widget.realtime == null ? null : _retryRealtime,
                        child: const Text('重试')),
                    const SizedBox(width: 16),
                  ]),
                ),
              ),
            Expanded(
              child: Row(children: [
                if (wide)
                  NavigationRail(
                      backgroundColor:
                          Theme.of(context).scaffoldBackgroundColor,
                      useIndicator: true,
                      selectedIndex: _index,
                      onDestinationSelected: _selectSection,
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations
                          .map((d) => NavigationRailDestination(
                              icon: d.icon,
                              selectedIcon: d.selectedIcon,
                              label: Text(d.label)))
                          .toList()),
                Expanded(child: IndexedStack(index: _index, children: pages))
              ]),
            ),
          ]),
          bottomNavigationBar: wide || compactConversation
              ? null
              : NavigationBar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  elevation: 0,
                  selectedIndex: _index,
                  onDestinationSelected: _selectSection,
                  destinations: destinations),
        ),
      ),
    );
  }

  void _setUnreadCount(int value) {
    if (!mounted) return;
    unawaited(_appBadge.setCount(value));
    if (value != _unreadCount) setState(() => _unreadCount = value);
    _syncDesktopTray();
  }

  _AppNavigationLocation get _currentNavigationLocation => (
        index: _index,
        selectedConversation: _selectedConversation,
        focusMessageId: _focusMessageId,
        focusMessageSequence: _focusMessageSequence,
        focusContactId: _focusContactId,
        focusContactCategory: _focusContactCategory,
        focusProjectId: _focusProjectId,
        focusTaskProjectId: _focusTaskProjectId,
        focusTaskId: _focusTaskId,
        focusDocumentId: _focusDocumentId,
        focusRouteReturnsToSource: _focusRouteReturnsToSource,
      );

  void _pushNavigationSource() {
    final source = _currentNavigationLocation;
    if (_navigationHistory.lastOrNull != source) {
      _navigationHistory.add(source);
    }
  }

  void _clearFocusTargets() {
    _focusMessageId = null;
    _focusMessageSequence = null;
    _focusContactId = null;
    _focusContactCategory = null;
    _focusProjectId = null;
    _focusTaskProjectId = null;
    _focusTaskId = null;
    _focusDocumentId = null;
    _focusRouteReturnsToSource = false;
  }

  void _applyNavigationLocation(_AppNavigationLocation location) {
    _index = location.index;
    _selectedConversation = location.selectedConversation;
    _focusMessageId = location.focusMessageId;
    _focusMessageSequence = location.focusMessageSequence;
    _focusContactId = location.focusContactId;
    _focusContactCategory = location.focusContactCategory;
    _focusProjectId = location.focusProjectId;
    _focusTaskProjectId = location.focusTaskProjectId;
    _focusTaskId = location.focusTaskId;
    _focusDocumentId = location.focusDocumentId;
    _focusRouteReturnsToSource = location.focusRouteReturnsToSource;
  }

  void _selectSection(int index) {
    if (!mounted || index < 0 || index > 3) return;
    if (index == _index) {
      if (index == 0) setState(() => _messagesReselectToken++);
      return;
    }
    setState(() {
      _pushNavigationSource();
      _clearFocusTargets();
      _index = index;
    });
  }

  void _selectConversationFromList(String id, {bool recordSource = true}) {
    if (!mounted) return;
    if (id.isEmpty) {
      _restoreNavigationSource();
      return;
    }
    _openConversation(id, recordSource: recordSource);
  }

  void _openConversation(String id, {bool recordSource = true}) {
    if (!mounted || id.isEmpty) return;
    final sameConversation = _index == 0 &&
        _selectedConversation == id &&
        _focusMessageId == null &&
        _focusContactId == null &&
        _focusProjectId == null &&
        _focusTaskProjectId == null &&
        _focusTaskId == null &&
        _focusDocumentId == null;
    if (sameConversation && !recordSource && _navigationHistory.isNotEmpty) {
      setState(_navigationHistory.clear);
    } else if (!sameConversation) {
      setState(() {
        if (recordSource) {
          _pushNavigationSource();
        } else {
          _navigationHistory.clear();
        }
        _clearFocusTargets();
        _selectedConversation = id;
        _index = 0;
      });
    }
    unawaited(_rememberConversation(id));
    unawaited(_loadConversationAppearance(id));
  }

  void _openMessageFromSearch(
      String conversationId, String messageId, int? messageSequence,
      {bool recordSource = true}) {
    if (!mounted || conversationId.isEmpty || messageId.isEmpty) return;
    setState(() {
      if (recordSource) {
        _pushNavigationSource();
      } else {
        _navigationHistory.clear();
      }
      _clearFocusTargets();
      _focusMessageId = messageId;
      _focusMessageSequence = messageSequence;
      _selectedConversation = conversationId;
      _index = 0;
    });
    unawaited(_rememberConversation(conversationId));
  }

  Future<void> _rememberConversation(String conversationId) =>
      const LastConversationStore().write(_messageCacheScope, conversationId);

  void _forgetConversation(String conversationId) {
    unawaited(const LastConversationStore()
        .clearIfMatches(_messageCacheScope, conversationId));
    _navigationHistory.removeWhere(
        (location) => location.selectedConversation == conversationId);
  }

  void _restoreNavigationSource() {
    if (!mounted) return;
    String? conversationId;
    setState(() {
      if (_navigationHistory.isNotEmpty) {
        _applyNavigationLocation(_navigationHistory.removeLast());
      } else {
        _index = 0;
        _selectedConversation = null;
        _clearFocusTargets();
      }
      conversationId = _selectedConversation;
    });
    if (conversationId?.isNotEmpty == true) {
      unawaited(_loadConversationAppearance(conversationId!));
    }
  }

  void _completeFocusedRoute() {
    if (_focusRouteReturnsToSource) {
      _restoreNavigationSource();
    } else {
      setState(_clearFocusTargets);
    }
  }

  void _backConversation() => _restoreNavigationSource();

  void _handleSystemBack() {
    if (_navigationHistory.isNotEmpty ||
        _index != 0 ||
        _selectedConversation != null) {
      _restoreNavigationSource();
    }
  }

  MessageCacheScope? _messageCacheScopeFor(String? userId) {
    final server = widget.serverUrl?.trim();
    final user = userId?.trim();
    if (server == null || server.isEmpty || user == null || user.isEmpty) {
      return null;
    }
    return MessageCacheScope(serverUrl: server, userId: user);
  }

  MessageCacheScope? get _messageCacheScope =>
      _messageCacheScopeFor(_currentUserId);

  void _openContactTarget(String contactId) {
    if (!mounted || contactId.isEmpty) return;
    setState(() {
      _pushNavigationSource();
      _clearFocusTargets();
      _focusContactId = contactId;
      _focusRouteReturnsToSource = true;
      _index = 1;
    });
  }

  void _openProjectTarget(String projectId) {
    if (!mounted || projectId.isEmpty) return;
    setState(() {
      _pushNavigationSource();
      _clearFocusTargets();
      _focusProjectId = projectId;
      _focusRouteReturnsToSource = true;
      _index = 2;
    });
  }

  void _openTaskTarget(String projectId, String taskId) {
    if (!mounted || projectId.isEmpty || taskId.isEmpty) return;
    setState(() {
      _pushNavigationSource();
      _clearFocusTargets();
      _focusTaskProjectId = projectId;
      _focusTaskId = taskId;
      _focusRouteReturnsToSource = true;
      _index = 2;
    });
  }

  void _openDocumentTarget(String documentId) {
    if (!mounted || documentId.isEmpty) return;
    setState(() {
      _pushNavigationSource();
      _clearFocusTargets();
      _focusDocumentId = documentId;
      _focusRouteReturnsToSource = true;
      _index = 2;
    });
  }

  void _openInternalMessageLink(String path) {
    final target = parseInternalMessagePath(path);
    if (target == null) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    final task = parseProjectTaskMessagePath(target);
    if (task != null) {
      _openTaskTarget(task.projectId, task.taskId);
      return;
    }
    final document = parseDocumentMessagePath(target);
    if (document != null) {
      _openDocumentTarget(document.documentId);
      return;
    }
    if (uri.path == '/projects' || uri.path.startsWith('/projects/')) {
      _selectSection(2);
    }
  }

  Future<void> _showSearch(BuildContext context) async {
    if (_searchDialogOpen) return;
    _searchDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => GlobalSearchDialog(
          repository: _repository,
          cacheScope: _messageCacheScope,
          onOpenConversation: _selectConversationFromList,
          onOpenMessage: _openMessageFromSearch,
          onOpenProject: _openProjectTarget,
          onOpenContact: (contact) => _openContactTarget(contact.id),
        ),
      );
    } finally {
      _searchDialogOpen = false;
    }
  }
}

class _NavigationBadgeIcon extends StatelessWidget {
  const _NavigationBadgeIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) => Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(icon),
      );
}
