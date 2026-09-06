import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_preferences.dart';
import 'local_notification_service.dart';
import 'message_cache_store.dart';
import 'realtime.dart';
import 'realtime_store.dart';
import 'repository.dart';
import 'storage_service.dart';
import 'update_service.dart';

enum HttpProbeState {
  reachable,
  unauthorized,
  serverError,
  invalidResponse,
  unreachable,
}

class HttpProbeResult {
  const HttpProbeResult({
    required this.state,
    required this.latencyMs,
    this.statusCode,
  });

  final HttpProbeState state;
  final int latencyMs;
  final int? statusCode;

  bool get reachedServer => state != HttpProbeState.unreachable;
}

class RuntimeDiagnosticsSnapshot {
  const RuntimeDiagnosticsSnapshot({
    required this.capturedAt,
    required this.platform,
    required this.version,
    required this.buildMode,
    required this.server,
    required this.http,
    required this.realtimeStatus,
    required this.realtimeReady,
    required this.reconnectAttempt,
    required this.reconnectDelayMs,
    required this.realtimeCursor,
    required this.cachedConversationCount,
    required this.loadedMessageCount,
    required this.cacheAvailable,
    required this.messageCacheBytes,
    required this.mediaCacheBytes,
    required this.cacheJournalModes,
    required this.notificationsEnabled,
    required this.notificationPermission,
    required this.messageSoundEnabled,
    required this.notificationPrivacy,
  });

  final DateTime capturedAt;
  final String platform;
  final String version;
  final String buildMode;
  final String server;
  final HttpProbeResult http;
  final RealtimeStatus? realtimeStatus;
  final bool realtimeReady;
  final int reconnectAttempt;
  final int? reconnectDelayMs;
  final int realtimeCursor;
  final int cachedConversationCount;
  final int loadedMessageCount;
  final bool cacheAvailable;
  final int messageCacheBytes;
  final int mediaCacheBytes;
  final Map<String, String> cacheJournalModes;
  final bool notificationsEnabled;
  final NotificationPermissionStatus notificationPermission;
  final bool messageSoundEnabled;
  final MessageNotificationPrivacy notificationPrivacy;

  Map<String, Object?> toSanitizedJson() => {
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'application': {
          'platform': platform,
          'version': version,
          'build_mode': buildMode,
        },
        'server': server,
        'http': {
          'state': http.state.name,
          'latency_ms': http.latencyMs,
          if (http.statusCode != null) 'status_code': http.statusCode,
        },
        'realtime': {
          'status': realtimeStatus?.name ?? 'unavailable',
          'ready': realtimeReady,
          'reconnect_attempt': reconnectAttempt,
          if (reconnectDelayMs != null) 'reconnect_delay_ms': reconnectDelayMs,
          'cursor': realtimeCursor,
        },
        'cache': {
          'available': cacheAvailable,
          'message_bytes': messageCacheBytes,
          'media_bytes': mediaCacheBytes,
          'journal_modes': cacheJournalModes,
          'conversation_count': cachedConversationCount,
          'loaded_message_count': loadedMessageCount,
        },
        'notifications': {
          'enabled': notificationsEnabled,
          'permission': notificationPermission.name,
          'sound_enabled': messageSoundEnabled,
          'privacy': notificationPrivacy.name,
        },
      };
}

class DiagnosticRecordStats {
  const DiagnosticRecordStats({required this.count, required this.bytes});

  final int count;
  final int bytes;
}

class RuntimeDiagnosticsView {
  const RuntimeDiagnosticsView({
    required this.snapshot,
    required this.recordStats,
    required this.recentRecords,
  });

  final RuntimeDiagnosticsSnapshot snapshot;
  final DiagnosticRecordStats recordStats;
  final List<Map<String, Object?>> recentRecords;

  RuntimeDiagnosticsView withRecordStats(DiagnosticRecordStats stats) =>
      RuntimeDiagnosticsView(
        snapshot: snapshot,
        recordStats: stats,
        recentRecords: stats.count == 0 ? const [] : recentRecords,
      );
}

abstract interface class RuntimeDiagnosticsSource {
  Future<RuntimeDiagnosticsView> refresh();
  Future<DiagnosticRecordStats> clearRecords();
  String buildReport(RuntimeDiagnosticsView view);
}

class RuntimeDiagnosticRecordStore {
  const RuntimeDiagnosticRecordStore({
    this.preferenceKey = 'magicchat.runtime-diagnostics.v1',
  });

  final String preferenceKey;
  static const _maximumRecords = 20;

  Future<void> append(RuntimeDiagnosticsSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    final records = await read();
    records.add(_record(snapshot));
    if (records.length > _maximumRecords) {
      records.removeRange(0, records.length - _maximumRecords);
    }
    await preferences.setString(preferenceKey, jsonEncode(records));
  }

  Future<List<Map<String, Object?>>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(preferenceKey);
    if (encoded == null) return [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(_validatedRecord)
          .whereType<Map<String, Object?>>()
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  Future<DiagnosticRecordStats> stats() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(preferenceKey) ?? '';
    final records = await read();
    return DiagnosticRecordStats(
      count: records.length,
      bytes: utf8.encode(encoded).length,
    );
  }

  Future<DiagnosticRecordStats> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(preferenceKey);
    return const DiagnosticRecordStats(count: 0, bytes: 0);
  }

  Map<String, Object?> _record(RuntimeDiagnosticsSnapshot snapshot) => {
        'captured_at': snapshot.capturedAt.toUtc().toIso8601String(),
        'http_state': snapshot.http.state.name,
        'http_latency_ms': snapshot.http.latencyMs,
        if (snapshot.http.statusCode != null)
          'http_status_code': snapshot.http.statusCode,
        'realtime_status': snapshot.realtimeStatus?.name ?? 'unavailable',
        'realtime_ready': snapshot.realtimeReady,
        'reconnect_attempt': snapshot.reconnectAttempt,
        'realtime_cursor': snapshot.realtimeCursor,
        'message_cache_bytes': snapshot.messageCacheBytes,
        'notification_permission': snapshot.notificationPermission.name,
      };

  Map<String, Object?>? _validatedRecord(Map<Object?, Object?> value) {
    const httpStates = {
      'reachable',
      'unauthorized',
      'serverError',
      'invalidResponse',
      'unreachable',
    };
    const realtimeStates = {
      'connected',
      'connecting',
      'disconnected',
      'reconnecting',
      'unavailable',
    };
    const permissions = {
      'granted',
      'denied',
      'notDetermined',
      'unsupported',
      'unknown',
    };
    final capturedAt = value['captured_at'];
    final httpState = value['http_state'];
    final realtimeStatus = value['realtime_status'];
    final permission = value['notification_permission'];
    if (capturedAt is! String ||
        DateTime.tryParse(capturedAt) == null ||
        httpState is! String ||
        !httpStates.contains(httpState) ||
        realtimeStatus is! String ||
        !realtimeStates.contains(realtimeStatus) ||
        permission is! String ||
        !permissions.contains(permission)) {
      return null;
    }
    int safeNumber(String key) {
      final number = value[key];
      return number is num && number.isFinite && number >= 0
          ? number.toInt()
          : 0;
    }

    return {
      'captured_at': capturedAt,
      'http_state': httpState,
      'http_latency_ms': safeNumber('http_latency_ms'),
      if (value['http_status_code'] is num)
        'http_status_code': safeNumber('http_status_code'),
      'realtime_status': realtimeStatus,
      'realtime_ready': value['realtime_ready'] == true,
      'reconnect_attempt': safeNumber('reconnect_attempt'),
      'realtime_cursor': safeNumber('realtime_cursor'),
      'message_cache_bytes': safeNumber('message_cache_bytes'),
      'notification_permission': permission,
    };
  }
}

class RuntimeDiagnosticsService implements RuntimeDiagnosticsSource {
  RuntimeDiagnosticsService({
    required this.repository,
    required String? serverUrl,
    this.realtimeSession,
    this.realtimeStore,
    this.cacheScope,
    MessageCacheStore? messageCacheStore,
    StorageService? storageService,
    LocalNotificationService? notificationService,
    RuntimeDiagnosticRecordStore? recordStore,
    this.messageSoundEnabled = true,
    this.notificationPrivacy = MessageNotificationPrivacy.preview,
    this.httpTimeout = const Duration(seconds: 10),
    String? platform,
    String? version,
    String? buildMode,
  })  : server = sanitizeDiagnosticServer(serverUrl),
        _messageCacheStore = messageCacheStore ?? MessageCacheStore(),
        _storageService = storageService ?? StorageService(),
        _notificationService =
            notificationService ?? const LocalNotificationService(),
        _recordStore = recordStore ?? const RuntimeDiagnosticRecordStore(),
        platform = platform ?? runtimeDiagnosticPlatform(),
        version = version ??
            '${UpdateService.currentVersion}+${UpdateService.currentBuild}',
        buildMode = buildMode ?? runtimeDiagnosticBuildMode();

  final MagicChatRepository repository;
  final String server;
  final RealtimeSession? realtimeSession;
  final RealtimeStore? realtimeStore;
  final MessageCacheScope? cacheScope;
  final MessageCacheStore _messageCacheStore;
  final StorageService _storageService;
  final LocalNotificationService _notificationService;
  final RuntimeDiagnosticRecordStore _recordStore;
  final bool messageSoundEnabled;
  final MessageNotificationPrivacy notificationPrivacy;
  final Duration httpTimeout;
  final String platform;
  final String version;
  final String buildMode;

  @override
  Future<RuntimeDiagnosticsView> refresh() async {
    final results = await Future.wait<Object>([
      _probeHttp(),
      _inspectStorage(),
      _notificationService.permissionStatus(),
      _notificationsEnabled(),
      _journalModes(),
    ]);
    final http = results[0] as HttpProbeResult;
    final storage = results[1] as ({bool available, StorageInfo info});
    final permission = results[2] as NotificationPermissionStatus;
    final notificationsEnabled = results[3] as bool;
    final journalModes = results[4] as Map<String, String>;
    final session = realtimeSession;
    final store = realtimeStore;
    final snapshot = RuntimeDiagnosticsSnapshot(
      capturedAt: DateTime.now().toUtc(),
      platform: platform,
      version: version,
      buildMode: buildMode,
      server: server,
      http: http,
      realtimeStatus: session?.status,
      realtimeReady: session?.ready ?? false,
      reconnectAttempt: session?.reconnectAttempt ?? 0,
      reconnectDelayMs: session?.reconnectDelayMs,
      realtimeCursor: session?.cursor ?? store?.cursor ?? 0,
      cachedConversationCount: store?.conversations.length ?? 0,
      loadedMessageCount: store?.messages.length ?? 0,
      cacheAvailable: storage.available,
      messageCacheBytes: storage.info.messageBytes,
      mediaCacheBytes: storage.info.mediaBytes,
      cacheJournalModes: journalModes,
      notificationsEnabled: notificationsEnabled,
      notificationPermission: permission,
      messageSoundEnabled: messageSoundEnabled,
      notificationPrivacy: notificationPrivacy,
    );
    try {
      await _recordStore.append(snapshot);
    } catch (_) {
      // 诊断记录属于辅助能力，持久化失败不影响当前状态检查。
    }
    final records = await _recordStore.read();
    final stats = await _recordStore.stats();
    return RuntimeDiagnosticsView(
      snapshot: snapshot,
      recordStats: stats,
      recentRecords: List.unmodifiable(records),
    );
  }

  Future<HttpProbeResult> _probeHttp() async {
    final stopwatch = Stopwatch()..start();
    try {
      await repository.currentUser().timeout(httpTimeout);
      stopwatch.stop();
      return HttpProbeResult(
        state: HttpProbeState.reachable,
        latencyMs: stopwatch.elapsedMilliseconds,
        statusCode: 200,
      );
    } on MagicChatRequestException catch (error) {
      stopwatch.stop();
      return HttpProbeResult(
        state: error.isUnauthorized
            ? HttpProbeState.unauthorized
            : HttpProbeState.serverError,
        latencyMs: stopwatch.elapsedMilliseconds,
        statusCode: error.statusCode,
      );
    } on FormatException {
      stopwatch.stop();
      return HttpProbeResult(
        state: HttpProbeState.invalidResponse,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      stopwatch.stop();
      return HttpProbeResult(
        state: HttpProbeState.unreachable,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<({bool available, StorageInfo info})> _inspectStorage() async {
    try {
      return (available: true, info: await _storageService.inspect());
    } catch (_) {
      return (
        available: false,
        info: const StorageInfo(mediaBytes: 0, messageBytes: 0),
      );
    }
  }

  Future<Map<String, String>> _journalModes() async {
    final scope = cacheScope;
    if (scope == null) return const {};
    final entries = await Future.wait(
      messageCacheConversationTypes.map((type) async {
        try {
          return MapEntry(
            type,
            await _messageCacheStore.journalMode(scope, conversationType: type),
          );
        } catch (_) {
          return MapEntry(type, 'unavailable');
        }
      }),
    );
    return Map.unmodifiable(Map.fromEntries(entries));
  }

  Future<bool> _notificationsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(
        'magicchat.notifications.enabled',
      ) ??
      true;

  @override
  Future<DiagnosticRecordStats> clearRecords() => _recordStore.clear();

  @override
  String buildReport(RuntimeDiagnosticsView view) =>
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'remote_telemetry_enabled': false,
        'client_evidence_boundary': '仅表示客户端本机观察结果，不能据此推断服务端未发送事件。',
        'snapshot': view.snapshot.toSanitizedJson(),
        'diagnostic_records': {
          'count': view.recordStats.count,
          'bytes': view.recordStats.bytes,
          'recent': view.recentRecords,
        },
      });
}

String sanitizeDiagnosticServer(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return '未配置';
  }
  final defaultPort = (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
  final path = uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/$'), '');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort && !defaultPort ? uri.port : null,
    path: path,
  ).toString();
}

String runtimeDiagnosticPlatform() {
  if (kIsWeb) return 'Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

String runtimeDiagnosticBuildMode() => kReleaseMode
    ? 'release'
    : kProfileMode
        ? 'profile'
        : 'debug';
