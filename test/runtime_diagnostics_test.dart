import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/local_notification_service.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/realtime.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/runtime_diagnostics.dart';
import 'package:magicchat_client/data/storage_service.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/settings/runtime_diagnostics_page.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'magicchat.notifications.enabled': false,
      }));

  test('采集真实连接与 WAL 状态，报告移除凭据和用户信息', () async {
    final directory = await Directory.systemTemp.createTemp('diagnostics-db-');
    final messageCache = MessageCacheStore(databaseDirectory: directory.path);
    final realtime = RealtimeSession(
      realtime: MagicChatRealtime(
        serverUrl: 'https://chat.example.com/base',
        sessionToken: 'session-token-secret',
        connector: (_, __) => throw StateError('offline cookie=secret-cookie'),
      ),
      delays: const [60000],
    );
    await realtime.connect();
    addTearDown(() async {
      await realtime.close();
      await messageCache.clearAll();
      await messageCache.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final store = RealtimeStore()
      ..conversations['conversation-secret'] =
          const ChatConversation(id: 'conversation-secret', title: '不应进入报告')
      ..messages['message-secret'] = const ChatMessage(
          id: 'message-secret', author: 'Alice', text: '私密消息正文');
    final service = RuntimeDiagnosticsService(
      repository: _DiagnosticRepository(),
      serverUrl:
          'https://alice:password@chat.example.com/base/?token=secret#cookie',
      realtimeSession: realtime,
      realtimeStore: store,
      cacheScope: const MessageCacheScope(
          serverUrl: 'https://chat.example.com', userId: 'alice@example.com'),
      messageCacheStore: messageCache,
      storageService: _DiagnosticStorageService(),
      notificationService: _DiagnosticNotificationService(),
      platform: 'Linux x64',
      version: '1.2.3+4',
      buildMode: 'release',
      messageSoundEnabled: false,
      notificationPrivacy: MessageNotificationPrivacy.metadata,
    );

    final view = await service.refresh();
    final report = service.buildReport(view);

    expect(view.snapshot.server, 'https://chat.example.com/base');
    expect(view.snapshot.http.state, HttpProbeState.reachable);
    expect(view.snapshot.http.statusCode, 200);
    expect(view.snapshot.realtimeStatus, RealtimeStatus.reconnecting);
    expect(view.snapshot.reconnectAttempt, 1);
    expect(view.snapshot.reconnectDelayMs, 60000);
    expect(view.snapshot.cacheJournalModes.values.toSet(), {'wal'});
    expect(view.snapshot.messageCacheBytes, 2048);
    expect(view.snapshot.notificationPermission,
        NotificationPermissionStatus.denied);
    expect(view.snapshot.notificationsEnabled, isFalse);
    expect(view.recordStats.count, 1);
    expect(report, contains('client_evidence_boundary'));
    expect(report, contains('https://chat.example.com/base'));
    for (final secret in [
      'session-token-secret',
      'secret-cookie',
      'alice@example.com',
      'password',
      'token=secret',
      'conversation-secret',
      'message-secret',
      '私密消息正文',
    ]) {
      expect(report, isNot(contains(secret)));
    }

    expect((await service.clearRecords()).count, 0);
  });

  test('本地记录读取只保留白名单字段', () async {
    const store =
        RuntimeDiagnosticRecordStore(preferenceKey: 'diagnostic-test');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('diagnostic-test', '''[
      {
        "captured_at":"2026-09-06T00:00:00Z",
        "http_state":"reachable",
        "http_latency_ms":12,
        "realtime_status":"connected",
        "realtime_ready":true,
        "reconnect_attempt":0,
        "realtime_cursor":8,
        "message_cache_bytes":20,
        "notification_permission":"granted",
        "token":"must-not-survive",
        "email":"alice@example.com"
      }
    ]''');

    final record = (await store.read()).single;
    expect(record['http_latency_ms'], 12);
    expect(record, isNot(contains('token')));
    expect(record, isNot(contains('email')));
  });

  testWidgets('诊断页面支持刷新、复制报告和二次确认清理', (tester) async {
    final source = _FakeDiagnosticsSource();
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: RuntimeDiagnosticsPage(source: source)));
    await tester.pumpAndSettle();

    expect(find.text('连接与运行诊断'), findsOneWidget);
    expect(find.text('HTTP 连接'), findsOneWidget);
    expect(find.text('实时连接'), findsOneWidget);
    expect(find.text('缓存与存储'), findsOneWidget);
    expect(find.text('通知与权限'), findsOneWidget);
    expect(find.text('https://chat.example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('复制脱敏报告'));
    await tester.pumpAndSettle();
    expect(copiedText, 'sanitized-report');

    final clearRecords = find.text('清理记录', skipOffstage: false);
    await tester.ensureVisible(clearRecords);
    await tester.pumpAndSettle();
    await tester.tap(clearRecords);
    await tester.pumpAndSettle();
    expect(find.text('清理诊断记录？'), findsOneWidget);
    expect(source.clearCount, 0);
    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await tester.pumpAndSettle();
    expect(source.clearCount, 1);
    expect(find.text('0 条 · 0 B'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新诊断'));
    await tester.pumpAndSettle();
    expect(source.refreshCount, 2);
  });

  testWidgets('设置页提供连接与运行诊断入口', (tester) async {
    final source = _FakeDiagnosticsSource();
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsPage(
          repository: DemoRepository(),
          serverUrl: 'https://chat.example.com',
          diagnosticsSource: source,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final entry = find.text('连接与运行诊断', skipOffstage: false);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(RuntimeDiagnosticsPage), findsOneWidget);
    expect(source.refreshCount, 1);
  });
}

class _DiagnosticRepository extends DemoRepository {
  @override
  Future<CurrentUser> currentUser() async =>
      const CurrentUser(id: 'alice', name: 'Alice', email: 'alice@example.com');
}

class _DiagnosticStorageService extends StorageService {
  @override
  Future<StorageInfo> inspect() async =>
      const StorageInfo(mediaBytes: 1024, messageBytes: 2048);
}

class _DiagnosticNotificationService extends LocalNotificationService {
  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.denied;
}

class _FakeDiagnosticsSource implements RuntimeDiagnosticsSource {
  int refreshCount = 0;
  int clearCount = 0;

  @override
  Future<RuntimeDiagnosticsView> refresh() async {
    refreshCount++;
    return RuntimeDiagnosticsView(
      snapshot: RuntimeDiagnosticsSnapshot(
        capturedAt: DateTime.utc(2026, 9, 6, 8),
        platform: 'Windows',
        version: '1.2.3+4',
        buildMode: 'release',
        server: 'https://chat.example.com',
        http: const HttpProbeResult(
            state: HttpProbeState.reachable, latencyMs: 18, statusCode: 200),
        realtimeStatus: RealtimeStatus.connected,
        realtimeReady: true,
        reconnectAttempt: 0,
        reconnectDelayMs: null,
        realtimeCursor: 42,
        cachedConversationCount: 3,
        loadedMessageCount: 8,
        cacheAvailable: true,
        messageCacheBytes: 2048,
        mediaCacheBytes: 1024,
        cacheJournalModes: const {
          'direct': 'wal',
          'group': 'wal',
          'app': 'wal',
          'topic': 'wal',
        },
        notificationsEnabled: true,
        notificationPermission: NotificationPermissionStatus.granted,
        messageSoundEnabled: true,
        notificationPrivacy: MessageNotificationPrivacy.preview,
      ),
      recordStats: const DiagnosticRecordStats(count: 2, bytes: 512),
      recentRecords: const [],
    );
  }

  @override
  Future<DiagnosticRecordStats> clearRecords() async {
    clearCount++;
    return const DiagnosticRecordStats(count: 0, bytes: 0);
  }

  @override
  String buildReport(RuntimeDiagnosticsView view) => 'sanitized-report';
}
