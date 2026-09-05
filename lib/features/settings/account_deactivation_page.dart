import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth_service.dart';

class AccountDeactivationPage extends StatefulWidget {
  const AccountDeactivationPage({
    required this.serverUrl,
    required this.email,
    required this.onDeactivate,
    this.authService,
    super.key,
  });

  final String serverUrl;
  final String email;
  final Future<void> Function(String code) onDeactivate;
  final AuthService? authService;

  @override
  State<AccountDeactivationPage> createState() =>
      _AccountDeactivationPageState();
}

class _AccountDeactivationPageState extends State<AccountDeactivationPage> {
  final _codeController = TextEditingController();
  late final AuthService _authService = widget.authService ?? AuthService();
  Timer? _retryTimer;
  int _retrySeconds = 0;
  bool _sending = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _codeController
      ..removeListener(_onCodeChanged)
      ..dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    final normalized = normalizeAccountDeactivationCode(_codeController.text);
    if (normalized != _codeController.text) {
      _codeController.value = TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length));
      return;
    }
    if (mounted) setState(() => _error = null);
  }

  Future<void> _requestCode() async {
    if (_sending || _submitting || _retrySeconds > 0) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await _authService.requestAccountDeactivationCode(
          serverUrl: widget.serverUrl);
      if (!mounted) return;
      _startRetryTimer(result.retryAfterSeconds);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('验证码已发送，${result.expiresInSeconds} 秒内有效')));
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startRetryTimer(int seconds) {
    _retryTimer?.cancel();
    setState(() => _retrySeconds = seconds);
    if (seconds <= 0) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _retrySeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _retrySeconds = 0);
        return;
      }
      setState(() => _retrySeconds--);
    });
  }

  Future<void> _deactivate() async {
    final code = normalizeAccountDeactivationCode(_codeController.text);
    if (_submitting || _sending || code.length != 8) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onDeactivate(code);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _errorText(error);
        });
      }
    }
  }

  String _errorText(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) return '请求超时，请稍后重试';
    return error
        .toString()
        .replaceFirst(RegExp(r'^(AuthRequestException|Exception):\s*'), '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('注销账号')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '账号注销后将无法恢复，所有设备上的会话都会失效。',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('验证码将发送至当前账号邮箱：'),
                      const SizedBox(height: 4),
                      Text(widget.email.trim().isEmpty
                          ? '邮箱不可用'
                          : widget.email.trim()),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('account-deactivation-code'),
                        controller: _codeController,
                        autofocus: true,
                        enabled: !_submitting,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        maxLength: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                          labelText: '邮箱验证码',
                          hintText: '输入 8 位数字验证码',
                          suffixIcon: TextButton(
                            onPressed:
                                _sending || _submitting || _retrySeconds > 0
                                    ? null
                                    : _requestCode,
                            child: _sending
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(_retrySeconds > 0
                                    ? '$_retrySeconds 秒'
                                    : '发送验证码'),
                          ),
                        ),
                        onSubmitted: (_) => _deactivate(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            foregroundColor:
                                Theme.of(context).colorScheme.onError,
                            minimumSize: const Size.fromHeight(48)),
                        onPressed: _submitting ||
                                _sending ||
                                _codeController.text.length != 8
                            ? null
                            : _deactivate,
                        icon: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.person_off_outlined),
                        label: const Text('注销账号'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
