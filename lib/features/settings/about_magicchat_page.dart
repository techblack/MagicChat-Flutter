import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_links.dart';
import '../../data/update_service.dart';
import '../shared/external_link_launcher.dart';

String magicChatPlatformLabel({bool? isWeb, TargetPlatform? platform}) {
  if (isWeb ?? kIsWeb) return 'Web';
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

class AboutMagicChatPage extends StatelessWidget {
  const AboutMagicChatPage({
    this.version = UpdateService.currentVersion,
    this.buildNumber = UpdateService.currentBuild,
    this.isWeb,
    this.platform,
    this.linkLauncher,
    super.key,
  });

  final String version;
  final int buildNumber;
  final bool? isWeb;
  final TargetPlatform? platform;
  final ExternalUriLauncher? linkLauncher;

  Future<void> _openLink(
      BuildContext context, String label, String value) async {
    final opened = await launchExternalWebLink(
      context,
      Uri.parse(value),
      launcher: linkLauncher,
    );
    if (opened == false && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('暂时无法打开$label，请稍后重试')));
    }
  }

  void _openLicenses(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LicensePage(
          applicationName: 'MagicChat',
          applicationVersion: '$version+$buildNumber',
          applicationIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Image.asset(
              'assets/tray_icon.png',
              width: 64,
              height: 64,
              semanticLabel: 'MagicChat 图标',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platformName =
        magicChatPlatformLabel(isWeb: isWeb, platform: platform);
    return Scaffold(
      appBar: AppBar(title: const Text('关于 MagicChat')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 640;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 32 : 20,
                vertical: 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _brand(context, wide, platformName),
                      const SizedBox(height: 28),
                      _sectionTitle(context, '法律与许可'),
                      const Divider(height: 1),
                      _linkTile(
                        icon: Icons.description_outlined,
                        label: '用户协议',
                        onTap: () => _openLink(
                            context, '用户协议', magicChatUserAgreementUrl),
                      ),
                      _linkTile(
                        icon: Icons.privacy_tip_outlined,
                        label: '隐私政策',
                        onTap: () => _openLink(
                            context, '隐私政策', magicChatPrivacyPolicyUrl),
                      ),
                      _linkTile(
                        icon: Icons.code_outlined,
                        label: '开源许可',
                        trailingIcon: Icons.chevron_right,
                        onTap: () => _openLicenses(context),
                      ),
                      const SizedBox(height: 20),
                      _sectionTitle(context, '项目'),
                      const Divider(height: 1),
                      _linkTile(
                        icon: Icons.home_outlined,
                        label: '项目主页',
                        onTap: () =>
                            _openLink(context, '项目主页', magicChatProjectUrl),
                      ),
                      _linkTile(
                        icon: Icons.new_releases_outlined,
                        label: 'Release 页面',
                        onTap: () => _openLink(
                            context, 'Release 页面', magicChatReleasesUrl),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _brand(BuildContext context, bool wide, String platformName) {
    final icon = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/tray_icon.png',
        width: 88,
        height: 88,
        semanticLabel: 'MagicChat 图标',
      ),
    );
    final details = Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          'MagicChat',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text('版本 $version · 构建 $buildNumber'),
        const SizedBox(height: 4),
        Text(
          '运行平台 · $platformName',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
    if (wide) {
      return Row(
        key: const ValueKey('about-brand-wide'),
        children: [icon, const SizedBox(width: 20), Expanded(child: details)],
      );
    }
    return Column(
      key: const ValueKey('about-brand-compact'),
      children: [icon, const SizedBox(height: 14), details],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Widget _linkTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    IconData trailingIcon = Icons.open_in_new,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Icon(trailingIcon, size: 20),
        onTap: onTap,
      );
}
