import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'qr_content.dart';
import 'shared/external_link_launcher.dart';

bool get supportsEmbeddedQrWebView =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

class QrWebViewPage extends StatefulWidget {
  const QrWebViewPage({required this.url, super.key});

  final String url;

  @override
  State<QrWebViewPage> createState() => _QrWebViewPageState();
}

class _QrWebViewPageState extends State<QrWebViewPage> {
  WebViewController? _controller;
  Uri? _safeUri;
  Uri? _currentUri;
  int _progress = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final result = classifyQrContent(widget.url);
    if (result.kind != QrContentKind.web) return;
    _safeUri = Uri.parse(result.value);
    _currentUri = _safeUri;
    if (supportsEmbeddedQrWebView) unawaited(_initializeWebView());
  }

  Future<void> _initializeWebView() async {
    try {
      final uri = _safeUri;
      if (uri == null) return;
      final controller = WebViewController();
      await WebViewCookieManager().clearCookies();
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final target = Uri.tryParse(request.url);
          return target != null && isAllowedQrWebUri(target)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          final uri = Uri.tryParse(url);
          if (!mounted) return;
          setState(() {
            if (uri != null && isAllowedQrWebUri(uri)) _currentUri = uri;
            _loadError = null;
            _progress = 0;
          });
        },
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _progress = 100);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false || !mounted) return;
          setState(() => _loadError = error.description);
        },
      ));
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(uri);
    } catch (_) {
      if (mounted) setState(() => _loadError = '无法初始化内置网页');
    }
  }

  Future<void> _openExternal() async {
    final uri = _currentUri ?? _safeUri;
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchExternalWebLink(context, uri) ?? true;
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前网页暂时无法在浏览器中打开')));
    }
  }

  Future<void> _copy() async {
    final uri = _currentUri ?? _safeUri;
    if (uri == null) return;
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('网页地址已复制')));
    }
  }

  Future<void> _retry() async {
    final controller = _controller;
    final uri = _currentUri ?? _safeUri;
    if (uri == null) return;
    setState(() {
      _loadError = null;
      _progress = 0;
    });
    if (controller == null) {
      await _initializeWebView();
      return;
    }
    try {
      await controller.loadRequest(uri);
    } catch (_) {
      if (mounted) setState(() => _loadError = '网页加载失败');
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.clearCache());
      unawaited(controller.clearLocalStorage());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('网页'),
          actions: [
            IconButton(
                tooltip: '复制网页地址',
                onPressed: _safeUri == null ? null : _copy,
                icon: const Icon(Icons.copy_outlined)),
            IconButton(
                tooltip: '在浏览器里打开',
                onPressed: _safeUri == null ? null : _openExternal,
                icon: const Icon(Icons.open_in_browser_outlined)),
          ],
        ),
        body: _body(context),
      );

  Widget _body(BuildContext context) {
    if (_safeUri == null) {
      return const _WebViewMessage(
          icon: Icons.link_off, title: '无法打开网页', message: '二维码中的链接无效或不受支持');
    }
    if (!supportsEmbeddedQrWebView) {
      return _WebViewMessage(
        icon: Icons.public,
        title: '当前平台暂不支持内置网页',
        message: _safeUri.toString(),
        actions: [
          OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('复制地址')),
          FilledButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_browser_outlined),
              label: const Text('在浏览器里打开')),
        ],
      );
    }
    final controller = _controller;
    if (_loadError != null) {
      return _WebViewMessage(
        icon: Icons.cloud_off_outlined,
        title: '网页加载失败',
        message: _loadError!,
        actions: [
          FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试')),
        ],
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(children: [
      Positioned.fill(child: WebViewWidget(controller: controller)),
      if (_progress < 100)
        Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(value: _progress / 100),
        ),
    ]);
  }
}

class _WebViewMessage extends StatelessWidget {
  const _WebViewMessage(
      {required this.icon,
      required this.title,
      required this.message,
      this.actions = const []});

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions),
              ],
            ]),
          ),
        ),
      );
}
