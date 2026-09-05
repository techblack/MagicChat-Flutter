import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QrResultPage extends StatelessWidget {
  const QrResultPage({required this.content, this.scanAgainBuilder, super.key});

  final String content;
  final WidgetBuilder? scanAgainBuilder;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('扫描结果已复制')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('扫描结果'),
          actions: [
            IconButton(
                tooltip: '复制扫描结果',
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_outlined)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      content.isEmpty ? '未获取到二维码内容' : content,
                      key: const ValueKey('qr-result-content'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _copy(context),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('复制内容')),
                  ),
                  if (scanAgainBuilder != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pushReplacement<void, void>(
                          context,
                          MaterialPageRoute(builder: scanAgainBuilder!),
                        ),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('再次扫描'),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      );
}
