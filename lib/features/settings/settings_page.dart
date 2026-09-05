import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/auth_service.dart';
import '../../data/avatar_processor.dart';
import '../../data/chat_preferences.dart';
import '../../data/chat_appearance_preferences.dart';
import '../../data/local_notification_service.dart';
import '../../data/realtime_store.dart';
import '../../data/repository.dart';
import '../../data/session_store.dart';
import '../../data/server_store.dart';
import '../../data/storage_service.dart';
import '../../data/update_service.dart';
import '../../data/message_cache_store.dart';
import '../../domain/models.dart';
import '../qr_scanner_page.dart';
import '../shared/cached_avatar.dart';
import 'account_deactivation_page.dart';
import 'server_management_page.dart';
import 'storage_management_page.dart';

Uri? _resolveAssetUri(String? serverUrl, String value) {
  final parsed = Uri.tryParse(value);
  if (parsed == null || value.trim().isEmpty) return null;
  if (parsed.hasScheme) return parsed;
  final server = Uri.tryParse(serverUrl ?? '');
  return server == null ? null : server.resolve(value);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {required this.repository,
      this.realtimeStore,
      required this.serverUrl,
      this.cacheScope,
      this.onServerChanged,
      this.onAccountSwitch,
      this.onLogout,
      this.onDeactivateAccount,
      this.onThemeChanged,
      this.onSendMessageShortcutChanged,
      this.chatAppearance = const ChatAppearance(),
      this.onChatAppearanceChanged,
      this.messageSoundEnabled = true,
      this.onMessageSoundChanged,
      this.notificationPrivacy = MessageNotificationPrivacy.preview,
      this.onNotificationPrivacyChanged,
      this.themeMode = ThemeMode.system,
      this.sendMessageShortcut = MessageSendShortcut.enter,
      super.key});
  final Future<void> Function()? onLogout;
  final Future<void> Function(String code)? onDeactivateAccount;
  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final Future<void> Function(String server)? onServerChanged;
  final ValueChanged<StoredAccount>? onAccountSwitch;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ValueChanged<MessageSendShortcut>? onSendMessageShortcutChanged;
  final ChatAppearance chatAppearance;
  final ValueChanged<ChatAppearance>? onChatAppearanceChanged;
  final bool messageSoundEnabled;
  final ValueChanged<bool>? onMessageSoundChanged;
  final MessageNotificationPrivacy notificationPrivacy;
  final ValueChanged<MessageNotificationPrivacy>? onNotificationPrivacyChanged;
  final ThemeMode themeMode;
  final MessageSendShortcut sendMessageShortcut;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<CurrentUser>? _userFuture;
  bool _notificationsEnabled = true;
  late bool _messageSoundEnabled;
  late MessageNotificationPrivacy _notificationPrivacy;
  late MessageSendShortcut _sendMessageShortcut;
  @override
  void initState() {
    super.initState();
    _sendMessageShortcut = widget.sendMessageShortcut;
    _messageSoundEnabled = widget.messageSoundEnabled;
    _notificationPrivacy = widget.notificationPrivacy;
    widget.realtimeStore?.addListener(_onRealtimeChanged);
    _userFuture = widget.repository.currentUser();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted)
        setState(() => _notificationsEnabled =
            prefs.getBool('magicchat.notifications.enabled') ?? true);
    });
  }

  void _onRealtimeChanged() {
    if (widget.realtimeStore?.lastEvent != 'user.profile.updated') return;
    _reloadUser();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sendMessageShortcut != widget.sendMessageShortcut) {
      _sendMessageShortcut = widget.sendMessageShortcut;
    }
    if (oldWidget.messageSoundEnabled != widget.messageSoundEnabled) {
      _messageSoundEnabled = widget.messageSoundEnabled;
    }
    if (oldWidget.notificationPrivacy != widget.notificationPrivacy) {
      _notificationPrivacy = widget.notificationPrivacy;
    }
  }

  void _reloadUser() {
    if (!mounted) return;
    setState(() {
      _userFuture = widget.repository.currentUser();
    });
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    super.dispose();
  }

  Future<void> _setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      final granted =
          await const LocalNotificationService().requestPermission();
      if (!granted) {
        await prefs.setBool('magicchat.notifications.enabled', false);
        if (mounted) {
          setState(() => _notificationsEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('系统通知权限未开启，请在系统设置中允许通知')));
        }
        return;
      }
    }
    await prefs.setBool('magicchat.notifications.enabled', value);
    if (mounted) setState(() => _notificationsEnabled = value);
  }

  Future<void> _setSendMessageShortcut(MessageSendShortcut value) async {
    setState(() => _sendMessageShortcut = value);
    widget.onSendMessageShortcutChanged?.call(value);
    await const ChatPreferences().writeSendShortcut(value);
  }

  Future<void> _editChatAppearance() async {
    final result = await showDialog<ChatAppearance>(
      context: context,
      builder: (_) => _ChatAppearanceDialog(initial: widget.chatAppearance),
    );
    if (result != null && mounted) {
      widget.onChatAppearanceChanged?.call(result);
    }
  }

  void _setMessageSoundEnabled(bool value) {
    setState(() => _messageSoundEnabled = value);
    widget.onMessageSoundChanged?.call(value);
  }

  void _setNotificationPrivacy(MessageNotificationPrivacy value) {
    setState(() => _notificationPrivacy = value);
    widget.onNotificationPrivacyChanged?.call(value);
  }

  String _notificationPrivacyLabel(MessageNotificationPrivacy value) =>
      switch (value) {
        MessageNotificationPrivacy.hidden => '隐藏内容',
        MessageNotificationPrivacy.metadata => '仅显示来源',
        MessageNotificationPrivacy.preview => '显示预览',
      };

  Future<void> _checkForUpdate() async {
    try {
      final release = await const UpdateService().check();
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('检查更新'),
                content: Text(release == null
                    ? '当前已是最新版本（${UpdateService.currentVersion}）'
                    : '发现新版本 ${release.version}（${release.build}）'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭')),
                  if (release != null)
                    FilledButton(
                        onPressed: () async {
                          await launchUrl(Uri.parse(release.url),
                              mode: LaunchMode.externalApplication);
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                        },
                        child: const Text('打开下载页')),
                ],
              ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('检查更新失败：$error')));
      }
    }
  }

  Future<void> _editNickname(CurrentUser user) async {
    final controller = TextEditingController(text: user.nickname);
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('修改昵称'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 64,
                  decoration: const InputDecoration(labelText: '昵称')),
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
    if (value == null || !mounted) return;
    try {
      setState(
          () => _userFuture = widget.repository.updateProfile(nickname: value));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _pickAvatar() async {
    final result =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || !mounted) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null && file.path == null) return;
    try {
      final processed =
          bytes == null ? null : const AvatarProcessor().process(bytes);
      setState(() {
        _userFuture = widget.repository.uploadAvatar(AttachmentUpload(
            path: file.path ?? '',
            name: processed == null ? file.name : 'avatar.webp',
            mimeType: processed == null
                ? 'image/${file.extension ?? 'webp'}'
                : 'image/webp',
            bytes: processed));
      });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('头像上传失败：$error')));
    }
  }

  Future<void> _openServerManagement() async {
    const store = ServerStore();
    final active = widget.serverUrl;
    if (active != null) {
      await store.rememberUrl(active, select: true, recent: true);
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ServerManagementPage(
          store: store,
          activeServerUrl: active,
          onSelect: widget.onServerChanged == null
              ? null
              : (server) => widget.onServerChanged!(server.url),
        ),
      ),
    );
  }

  Future<void> _chooseAccount() async {
    final accounts = await const SessionStore().readAccounts();
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('账户管理'),
              content: SizedBox(
                  width: 420,
                  child: accounts.isEmpty
                      ? const Text('暂无已保存账户')
                      : ListView(
                          shrinkWrap: true,
                          children: accounts
                              .map((account) => ListTile(
                                  leading:
                                      const Icon(Icons.account_circle_outlined),
                                  title: Text(account.name.isEmpty
                                      ? account.email
                                      : account.name),
                                  subtitle: Text(
                                      account.status == 'reauth-required'
                                          ? '需要重新登录 · ${account.serverUrl}'
                                          : account.serverUrl),
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    if (account.status == 'reauth-required') {
                                      _reauthAccount(account);
                                    } else {
                                      widget.onAccountSwitch?.call(account);
                                    }
                                  },
                                  onLongPress: () async {
                                    final remove = await showDialog<bool>(
                                        context: dialogContext,
                                        builder: (confirmContext) =>
                                            AlertDialog(
                                              title: const Text('删除已保存账户？'),
                                              content: Text(
                                                  account.email.isEmpty
                                                      ? account.serverUrl
                                                      : account.email),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            confirmContext,
                                                            false),
                                                    child: const Text('取消')),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            confirmContext,
                                                            true),
                                                    child: const Text('删除'))
                                              ],
                                            ));
                                    if (remove == true) {
                                      await const SessionStore()
                                          .removeAccount(account.id);
                                      if (dialogContext.mounted)
                                        Navigator.pop(dialogContext);
                                    }
                                  }))
                              .toList())),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'))
              ],
            ));
  }

  Future<void> _reauthAccount(StoredAccount account) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('重新登录账户'),
              content: TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(labelText: account.email)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('登录'))
              ],
            ));
    controller.dispose();
    if (password == null || password.isEmpty || !mounted) return;
    try {
      await AuthService().login(
          serverUrl: account.serverUrl,
          email: account.email,
          password: password);
      final token = await const SessionStore().readToken();
      if (token == null || !mounted) return;
      final replacement = StoredAccount(
          id: account.id,
          serverUrl: account.serverUrl,
          token: token,
          email: account.email,
          name: account.name);
      await const SessionStore().saveAccount(replacement);
      widget.onAccountSwitch?.call(replacement);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重新登录失败：$error')));
      }
    }
  }

  Future<void> _openAccountDeactivation() async {
    final deactivate = widget.onDeactivateAccount;
    final server = widget.serverUrl;
    if (deactivate == null || server == null) return;
    try {
      final user = await _userFuture;
      if (!mounted || user == null) return;
      final confirmed = await _confirmAccountDeactivation(user.email);
      if (confirmed != true || !mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AccountDeactivationPage(
            serverUrl: server,
            email: user.email,
            onDeactivate: deactivate,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('账户信息加载失败：$error')));
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认退出登录？'),
        content: const Text('退出后将清除本机登录凭据和离线缓存，需要重新登录才能继续使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onLogout?.call();
    }
  }

  Future<bool?> _confirmAccountDeactivation(String email) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => _AccountDeactivationConfirmDialog(email: email),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        FutureBuilder<CurrentUser>(
            future: _userFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('账户信息加载失败'),
                    trailing: TextButton.icon(
                        onPressed: _reloadUser,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试')));
              }
              final user = snapshot.data;
              if (user == null)
                return const ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('加载账户信息…'));
              return ListTile(
                  leading: GestureDetector(
                      onTap: _pickAvatar,
                      child: CachedAvatar(
                          repository: widget.repository,
                          cacheScope: widget.cacheScope,
                          avatarUri:
                              _resolveAssetUri(widget.serverUrl, user.avatar),
                          name: user.displayName)),
                  title: Text(user.displayName),
                  subtitle: Text(user.email),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editNickname(user));
            }),
        const SizedBox(height: 12),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('账户'),
              subtitle: const Text('切换已保存的登录账户'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _chooseAccount),
          ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('扫描二维码'),
              subtitle: const Text('扫描链接或查看二维码文本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QrScannerPage()))),
          ListTile(
              leading: Icon(Icons.dns),
              title: Text('服务器'),
              subtitle: Text(widget.serverUrl ?? '管理 MagicChat Server'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openServerManagement),
        ])),
        const SizedBox(height: 12),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('外观'),
              subtitle: const Text('主题设置'),
              trailing: DropdownButton<ThemeMode>(
                  value: widget.themeMode,
                  onChanged: (mode) {
                    if (mode != null) widget.onThemeChanged?.call(mode);
                  },
                  items: const [
                    DropdownMenuItem(
                        value: ThemeMode.system, child: Text('跟随系统')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                  ]),
              onTap: _editChatAppearance),
          ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text('发送快捷键'),
              subtitle: Text(_sendMessageShortcut == MessageSendShortcut.enter
                  ? 'Enter 发送，Shift+Enter 换行'
                  : 'Ctrl/⌘+Enter 发送，Enter 换行'),
              trailing: DropdownButton<MessageSendShortcut>(
                  value: _sendMessageShortcut,
                  onChanged: (value) {
                    if (value != null) {
                      _setSendMessageShortcut(value);
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                        value: MessageSendShortcut.enter, child: Text('Enter')),
                    DropdownMenuItem(
                        value: MessageSendShortcut.commandOrControlEnter,
                        child: Text('Ctrl/⌘+Enter')),
                  ])),
          SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('通知'),
              subtitle: const Text('接收新消息和系统通知'),
              value: _notificationsEnabled,
              onChanged: _setNotifications),
          SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('新消息提示音'),
              subtitle: const Text('收到普通新消息时播放提示音'),
              value: _messageSoundEnabled,
              onChanged: _setMessageSoundEnabled),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('通知隐私'),
            subtitle: const Text('控制系统通知中显示的消息内容'),
            trailing: DropdownButton<MessageNotificationPrivacy>(
                value: _notificationPrivacy,
                onChanged: (value) {
                  if (value != null) _setNotificationPrivacy(value);
                },
                items: MessageNotificationPrivacy.values
                    .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(_notificationPrivacyLabel(value))))
                    .toList()),
          ),
        ])),
        const SizedBox(height: 12),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('存储空间'),
              subtitle: const Text('查看和清理本地缓存'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          StorageManagementPage(service: StorageService())))),
          ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('检查更新'),
              subtitle: const Text('检查 MagicChat 新版本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _checkForUpdate),
          const ListTile(
              leading: Icon(Icons.info_outline), title: Text('关于 MagicChat')),
        ])),
        if (widget.onLogout != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                  child: ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('退出登录'),
                      onTap: _confirmLogout))),
        if (widget.onDeactivateAccount != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                  child: ListTile(
                      leading: Icon(Icons.person_off_outlined,
                          color: Theme.of(context).colorScheme.error),
                      title: Text('注销账号',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      subtitle: const Text('永久删除当前账号'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openAccountDeactivation)))
      ]);
}

class _AccountDeactivationConfirmDialog extends StatefulWidget {
  const _AccountDeactivationConfirmDialog({required this.email});

  final String email;

  @override
  State<_AccountDeactivationConfirmDialog> createState() =>
      _AccountDeactivationConfirmDialogState();
}

class _AccountDeactivationConfirmDialogState
    extends State<_AccountDeactivationConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('确认注销账号？'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('注销后将删除当前账号的本地登录信息，并使所有设备上的会话失效，此操作无法恢复。'),
          const SizedBox(height: 12),
          Text(
              '验证码将发送至：${widget.email.trim().isEmpty ? '当前账号邮箱' : widget.email.trim()}'),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            controller: _controller,
            decoration: const InputDecoration(
                labelText: '输入“注销”继续', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim() == '注销'
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('继续注销'))),
        ],
      );
}

class _ChatAppearanceDialog extends StatefulWidget {
  const _ChatAppearanceDialog({required this.initial});

  final ChatAppearance initial;

  @override
  State<_ChatAppearanceDialog> createState() => _ChatAppearanceDialogState();
}

class _ChatAppearanceDialogState extends State<_ChatAppearanceDialog> {
  late ChatSkin _skin = widget.initial.skin;
  late double _fontSize = widget.initial.fontSize;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('聊天外观'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<ChatSkin>(
            initialValue: _skin,
            decoration: const InputDecoration(labelText: '聊天皮肤'),
            items: ChatSkin.values
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _skin = value);
            },
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Text('消息字体'),
            Expanded(
                child: Slider(
                    min: 12,
                    max: 24,
                    divisions: 12,
                    value: _fontSize,
                    label: _fontSize.toStringAsFixed(0),
                    onChanged: (value) => setState(() => _fontSize = value))),
            Text(_fontSize.toStringAsFixed(0)),
          ]),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('字体大小仅保存在本机，不会影响其他设备。')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, ChatAppearance(skin: _skin, fontSize: _fontSize)),
              child: const Text('保存')),
        ],
      );
}
