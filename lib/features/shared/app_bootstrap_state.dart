import 'package:flutter/material.dart';

class BrandLoadingView extends StatelessWidget {
  const BrandLoadingView({
    this.message = '正在启动 MagicChat',
    this.detail = '正在为你准备工作空间',
    super.key,
  });

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox.square(
                dimension: 76,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.square(
                    dimension: 76,
                    child: CircularProgressIndicator(
                      key: const ValueKey('brand-loading-ring'),
                      strokeWidth: 2,
                      color: colors.primary,
                      backgroundColor: colors.primaryContainer,
                    ),
                  ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.forum_rounded,
                        size: 29, color: colors.onPrimaryContainer),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 22),
              Semantics(
                label: '加载进度',
                value: '加载中',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    key: ValueKey('brand-loading-progress'),
                    minHeight: 5,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class AppInitializationErrorView extends StatelessWidget {
  const AppInitializationErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.cloud_off_outlined,
                        size: 32, color: colors.onErrorContainer),
                  ),
                  const SizedBox(height: 18),
                  Text('无法打开工作空间',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('MagicChat 未能读取本地账户和偏好，请检查系统存储权限后重试。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('bootstrap-error-detail'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.errorContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onErrorContainer)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('bootstrap-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
