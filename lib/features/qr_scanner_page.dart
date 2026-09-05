import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'qr_content.dart';
import 'qr_result_page.dart';
import 'qr_webview_page.dart';

Widget buildQrScanDestination(String content,
    {WidgetBuilder? scanAgainBuilder}) {
  final result = classifyQrContent(content);
  return result.kind == QrContentKind.web
      ? QrWebViewPage(url: result.value)
      : QrResultPage(content: result.value, scanAgainBuilder: scanAgainBuilder);
}

/// 二维码扫描页。相机不可用的平台仍可粘贴二维码内容并按同一规则处理。
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handled = false;

  Future<void> _handle(String raw) async {
    if (_handled || raw.trim().isEmpty) return;
    _handled = true;
    try {
      await _controller.stop();
    } catch (_) {
      // 粘贴内容在无相机平台也应继续打开结果。
    }
    if (!mounted) return;
    unawaited(Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => buildQrScanDestination(raw,
            scanAgainBuilder: (_) => const QrScannerPage()),
      ),
    ));
  }

  Future<void> _paste() async {
    try {
      await _controller.stop();
    } catch (_) {
      // 无相机平台仍可粘贴内容。
    }
    if (!mounted) return;
    final controller = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('输入二维码内容'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: '粘贴链接或文本')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('打开'))
              ],
            ));
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await _handle(value);
    } else if (mounted) {
      unawaited(_controller.start());
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('扫一扫')),
        body: Column(children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final value = capture.barcodes.isEmpty
                    ? null
                    : capture.barcodes.first.rawValue;
                if (value != null) unawaited(_handle(value));
              },
              errorBuilder: (context, error) => _ScannerError(
                permissionDenied:
                    error.errorCode == MobileScannerErrorCode.permissionDenied,
                onRetry: _controller.start,
              ),
              placeholderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
              overlayBuilder: (_, __) => const _ScannerOverlay(),
            ),
          ),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste),
                        label: const Text('粘贴二维码内容')),
                  )))
        ]),
      );
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ColoredBox(
          color: Colors.black26,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.transparent,
                ),
              ),
              const SizedBox(height: 24),
              const Text('将二维码放入框内，即可自动扫描',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.permissionDenied, required this.onRetry});

  final bool permissionDenied;
  final Future<void> Function() onRetry;

  bool get _canOpenSettings =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                permissionDenied
                    ? Icons.no_photography
                    : Icons.camera_alt_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(permissionDenied ? '需要相机权限' : '无法使用相机',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                permissionDenied
                    ? '请允许 MagicChat 使用相机扫描二维码'
                    : '相机启动失败，请稍后重试或粘贴二维码内容',
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
              FilledButton.icon(
                  onPressed: () => unawaited(onRetry()),
                  icon: Icon(permissionDenied
                      ? Icons.camera_alt_outlined
                      : Icons.refresh),
                  label: Text(permissionDenied ? '重新授权' : '重试')),
              if (permissionDenied && _canOpenSettings)
                OutlinedButton.icon(
                    onPressed: () => unawaited(AppSettings.openAppSettings()),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('系统设置')),
            ]),
          ]),
        ),
      );
}
