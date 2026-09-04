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
}) =>
    conversationId.isNotEmpty &&
    conversationId != selectedConversationId &&
    !muted;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      kReleaseMode &&
      defaultTargetPlatform == TargetPlatform.macOS) {
    await FilePicker.skipEntitlementsChecks();
  }
  runApp(const MagicChatApp());
}

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
  String? _loginError;
  bool _loading = true;
  bool _sessionExpiring = false;

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
          ? _createRepository(server, token)
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
    await _realtime?.close();
    if (mounted) {
      setState(() {
        _repository = null;
        _realtime = null;
        _serverUrl = null;
        _loginError = null;
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
      await const SessionStore()
          .markAccountReauthRequired(serverUrl: oldServer, token: oldToken);
    }
    await _realtime?.close();
    await const SessionStore().clear();
    await MessageCacheStore().clearAll();
    await ContactCacheStore().clearAll();
    await LocalAssetCache().clearAll();
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
      await const SessionStore()
          .markAccountReauthRequired(serverUrl: oldServer, token: oldToken);
    }
    await _realtime?.close();
    await const SessionStore().writeToken(account.token);

    await prefs.setString('magicchat.server_url', account.serverUrl);
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
                    onThemeChanged: _setTheme,
                    themeMode: _themeMode),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage(
      {required this.onLogin,
      required this.onCodeLogin,
      this.initialServer,
      this.initialError,
      this.authService,
      super.key});
  final Future<void> Function(String server, String email, String password)
      onLogin;
  final Future<void> Function(String server, String email, String code)
      onCodeLogin;
  final String? initialServer;
  final String? initialError;
  final AuthService? authService;
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
  bool _infoLoading = false;
  ClientAppInfo? _appInfo;
  late String? _error = widget.initialError;
  String? _serverStatus;
  int _infoGeneration = 0;
  int _resendIn = 0;
  Timer? _resendTimer;

  late final AuthService _authService = widget.authService ?? AuthService();

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
                                  suffixIcon: IconButton(
                                    tooltip: '检查服务器',
                                    onPressed:
                                        _infoLoading ? null : _loadAppInfo,
                                    icon: _infoLoading
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.refresh),
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final MagicChatRepository _repository = widget.repository;
  String? _currentUserId;
  int _index = 0;
  String? _selectedConversation;
  String? _focusMessageId;
  int? _focusMessageSequence;
  String? _focusContactId;
  String? _focusProjectId;
  int _unreadCount = 0;
  final _conversationHistory = <String>[];
  final _contactCacheStore = ContactCacheStore();
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  final _notifications = const LocalNotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final realtime = widget.realtime;
    final store = widget.realtimeStore;
    if (realtime != null && store != null) {
      unawaited(widget.repository.currentUser().then((user) {
        store.setCurrentUserId(user.id);
        unawaited(_rememberCurrentUser(user));
        if (mounted) setState(() => _currentUserId = user.id);
      }).catchError((_) {}));
      _realtimeSubscription = realtime.events.listen((event) {
        store.apply(event);
        _notifyIncomingMessage(event);
      });
      realtime.connect();
    }
    if (realtime == null || store == null) {
      unawaited(widget.repository.currentUser().then((user) {
        unawaited(_rememberCurrentUser(user));
        if (mounted) setState(() => _currentUserId = user.id);
      }).catchError((_) {}));
    }
    _resolveNotificationRoute();
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
  }

  Future<void> _notifyIncomingMessage(Map<String, dynamic> event) async {
    if (event['event'] != 'message.created') return;
    final payload = event['payload'];
    if (payload is! Map<String, dynamic>) return;
    final message = payload['message'];
    final data = message is Map<String, dynamic> ? message : payload;
    final conversationId = data['conversation_id'];
    if (conversationId is! String ||
        !shouldShowLocalMessageNotification(
            conversationId: conversationId,
            selectedConversationId: _selectedConversation,
            muted: widget.realtimeStore?.conversations[conversationId]?.muted ==
                true)) {
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
    final routeToken = Uri.base.queryParameters['route_token'] ??
        await const PushTokenProvider().takePendingRouteToken();
    if (routeToken == null || routeToken.isEmpty || widget.serverUrl == null)
      return;
    try {
      final token = await const SessionStore().readToken();
      if (token == null) return;
      final route = await PushService().resolveRoute(
          serverUrl: widget.serverUrl!,
          sessionToken: token,
          routeToken: routeToken);
      if (mounted) {
        _openMessageFromSearch(route.conversationId, route.messageId, null);
      }
    } catch (_) {
      // 通知路由失效时保留正常首页，不阻断主应用启动。
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSubscription?.cancel();
    widget.realtime?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resolveNotificationRoute());
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
      MessagesPage(
          repository: _repository,
          serverUrl: widget.serverUrl,
          realtimeStore: widget.realtimeStore,
          cacheScope: _messageCacheScope,
          selectedId: _selectedConversation,
          focusMessageId: _focusMessageId,
          focusMessageSequence: _focusMessageSequence,
          onSelect: _selectConversationFromList,
          onOpenConversation: _openConversation,
          onBack: _backConversation,
          onSearch: () => _showSearch(context),
          onOpenInternalLink: _openInternalMessageLink,
          onUnreadChanged: _setUnreadCount,
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
          realtimeStore: widget.realtimeStore,
          serverUrl: widget.serverUrl,
          cacheScope: _messageCacheScope,
          initialContactId: _focusContactId,
          onInitialContactOpened: () {
            if (mounted) setState(() => _focusContactId = null);
          },
          onOpenConversation: (id) {
            _focusContactId = null;
            _selectConversationFromList(id);
            if (mounted) setState(() => _index = 0);
          }),
      ProjectsPage(
          repository: _repository,
          initialProjectId: _focusProjectId,
          onInitialProjectOpened: () {
            if (mounted) setState(() => _focusProjectId = null);
          },
          documentCollaborationFactory: documentCollaborationFactory),
      SettingsPage(
          repository: _repository,
          realtimeStore: widget.realtimeStore,
          serverUrl: widget.serverUrl,
          cacheScope: _messageCacheScope,
          onServerChanged: widget.onServerChanged,
          onAccountSwitch: widget.onAccountSwitch,
          onLogout: widget.onLogout,
          onThemeChanged: widget.onThemeChanged,
          themeMode: widget.themeMode),
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
      canPop: _selectedConversation == null && _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleSystemBack();
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            letterSpacing: 0)),
                  ],
                ),
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
          Expanded(child: IndexedStack(index: _index, children: pages))
        ]),
        bottomNavigationBar: wide || compactConversation
            ? null
            : NavigationBar(
                backgroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: destinations),
      ),
    );
  }

  void _setUnreadCount(int value) {
    if (!mounted || value == _unreadCount) return;
    setState(() => _unreadCount = value);
  }

  void _selectConversationFromList(String id) {
    if (!mounted) return;
    setState(() {
      _conversationHistory.clear();
      _focusMessageId = null;
      _focusMessageSequence = null;
      _selectedConversation = id.isEmpty ? null : id;
      if (id.isNotEmpty) _index = 0;
    });
  }

  void _openConversation(String id) {
    if (!mounted || id.isEmpty) return;
    setState(() {
      _focusMessageId = null;
      _focusMessageSequence = null;
      if (_selectedConversation != null &&
          _selectedConversation != id &&
          !_conversationHistory.contains(_selectedConversation)) {
        _conversationHistory.add(_selectedConversation!);
      }
      _selectedConversation = id;
      _index = 0;
    });
  }

  void _openMessageFromSearch(
      String conversationId, String messageId, int? messageSequence) {
    if (!mounted || conversationId.isEmpty || messageId.isEmpty) return;
    setState(() {
      _focusMessageId = messageId;
      _focusMessageSequence = messageSequence;
      if (_selectedConversation != null &&
          _selectedConversation != conversationId &&
          !_conversationHistory.contains(_selectedConversation)) {
        _conversationHistory.add(_selectedConversation!);
      }
      _selectedConversation = conversationId;
      _index = 0;
    });
  }

  void _backConversation() {
    if (!mounted) return;
    setState(() {
      if (_conversationHistory.isNotEmpty) {
        _selectedConversation = _conversationHistory.removeLast();
      } else {
        _selectedConversation = null;
      }
    });
  }

  void _handleSystemBack() {
    if (_index != 0) {
      setState(() => _index = 0);
    } else if (_selectedConversation != null) {
      _backConversation();
    }
  }

  MessageCacheScope? get _messageCacheScope {
    final server = widget.serverUrl?.trim();
    final user = _currentUserId?.trim();
    if (server == null || server.isEmpty || user == null || user.isEmpty) {
      return null;
    }
    return MessageCacheScope(serverUrl: server, userId: user);
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
        onOpenConversation: _selectConversationFromList,
        onOpenMessage: _openMessageFromSearch,
        onOpenProject: (id) {
          setState(() {
            _focusProjectId = id;
            _index = 2;
          });
        },
        onOpenContact: (contact) {
          setState(() {
            _focusContactId = contact.id;
            _index = 1;
          });
        },
      ),
    );
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
