import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/auth_service.dart';
import '../../data/avatar_processor.dart';
import '../../data/local_notification_service.dart';
import '../../data/realtime_store.dart';
import '../../data/repository.dart';
import '../../data/session_store.dart';
import '../../data/storage_service.dart';
import '../../data/update_service.dart';
import '../../data/message_cache_store.dart';
import '../../domain/models.dart';
import '../qr_scanner_page.dart';
import '../shared/cached_avatar.dart';

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
      this.onThemeChanged,
      this.themeMode = ThemeMode.system,
      super.key});
  final Future<void> Function()? onLogout;
  final MagicChatRepository repository;
  final RealtimeStore? realtimeStore;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final ValueChanged<String>? onServerChanged;
  final ValueChanged<StoredAccount>? onAccountSwitch;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ThemeMode themeMode;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<CurrentUser>? _userFuture;
  bool _notificationsEnabled = true;
  @override
  void initState() {
    super.initState();
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
    if (mounted) setState(() => _userFuture = widget.repository.currentUser());
  }

  @override
  void dispose() {
    widget.realtimeStore?.removeListener(_onRealtimeChanged);
    super.dispose();
  }

  Future<void> _setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('magicchat.notifications.enabled', value);
    if (value) {
      await const LocalNotificationService().requestPermission();
    }
    if (mounted) setState(() => _notificationsEnabled = value);
  }

  Future<void> _showStorage() async {
    final service = StorageService();
    var info = await service.inspect();
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: const Text('存储管理'),
                content: Text('缓存占用：${info.formatted}\n位置：${info.path}'),
                actions: [
                  TextButton(
                      onPressed: () async {
                        await service.clearCache();
                        info = await service.inspect();
                        setDialogState(() {});
                      },
                      child: const Text('清理缓存')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭')),
                ],
              ),
            ));
  }

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
      setState(() => _userFuture = widget.repository.uploadAvatar(
          AttachmentUpload(
              path: file.path ?? '',
              name: processed == null ? file.name : 'avatar.webp',
              mimeType: processed == null
                  ? 'image/${file.extension ?? 'webp'}'
                  : 'image/webp',
              bytes: processed)));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('头像上传失败：$error')));
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: widget.serverUrl ?? '');
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('服务器配置'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://chat.example.com')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('切换'))
              ],
            ));
    controller.dispose();
    if (value == null || value.isEmpty || !mounted || value == widget.serverUrl)
      return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('切换服务器？'),
              content: const Text('切换后需要重新登录，当前会话将被清除。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认切换'))
              ],
            ));
    if (confirmed == true) widget.onServerChanged?.call(value);
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

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        FutureBuilder<CurrentUser>(
            future: _userFuture,
            builder: (context, snapshot) {
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
              subtitle: Text('配置 MagicChat Server 地址'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editServer),
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
                  ])),
          SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('通知'),
              subtitle: const Text('接收新消息和系统通知'),
              value: _notificationsEnabled,
              onChanged: _setNotifications),
        ])),
        const SizedBox(height: 12),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('存储空间'),
              subtitle: const Text('查看和清理本地缓存'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showStorage),
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
                      onTap: widget.onLogout)))
      ]);
}
