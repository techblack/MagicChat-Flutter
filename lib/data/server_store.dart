import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'session_store.dart';

const officialServerUrl = 'https://app.jiying.chat';

class StoredServer {
  const StoredServer({
    required this.id,
    required this.name,
    required this.url,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String url;
  final bool builtIn;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'url': url,
      };
}

class ServerState {
  const ServerState({
    required this.servers,
    required this.selectedServerId,
    this.recentServerId,
  });

  final List<StoredServer> servers;
  final String selectedServerId;
  final String? recentServerId;

  StoredServer get selectedServer =>
      servers.firstWhere((server) => server.id == selectedServerId,
          orElse: () => servers.first);
}

enum SaveServerStatus { added, updated, duplicate, invalid, notFound }

class SaveServerResult {
  const SaveServerResult(this.status, {this.server});

  final SaveServerStatus status;
  final StoredServer? server;
}

class ServerStore {
  const ServerStore();

  static const storageKey = 'magicchat.servers.v1';
  static const migrationKey = 'magicchat.servers.v1.migrated';
  static const officialServerId = 'magicchat-official';

  StoredServer get officialServer => const StoredServer(
      id: officialServerId,
      name: '即应官方服务器',
      url: officialServerUrl,
      builtIn: true);

  Future<ServerState> read() async {
    final preferences = await SharedPreferences.getInstance();
    final state = _decode(preferences.getString(storageKey));
    final shouldMigrate = preferences.getBool(migrationKey) != true;
    final migrated = shouldMigrate
        ? await _migrationCandidates(preferences)
        : const <StoredServer>[];
    final servers = <StoredServer>[officialServer];
    final seenUrls = {normalizeServerUrl(officialServer.url)};
    final seenIds = {officialServerId};
    for (final server in [...state.servers.skip(1), ...migrated]) {
      final normalizedUrl = normalizeServerUrl(server.url);
      if (seenIds.add(server.id) && seenUrls.add(normalizedUrl)) {
        servers.add(StoredServer(
            id: server.id, name: server.name.trim(), url: normalizedUrl));
      }
    }
    final selectedUrl =
        shouldMigrate ? preferences.getString('magicchat.server_url') : null;
    final selected = selectedUrl == null
        ? _serverById(servers, state.selectedServerId)
        : _serverByUrl(servers, selectedUrl);
    final recent = _serverById(servers, state.recentServerId);
    final result = ServerState(
      servers: servers,
      selectedServerId: selected?.id ?? officialServerId,
      recentServerId: recent?.id,
    );
    await _write(result);
    if (shouldMigrate) await preferences.setBool(migrationKey, true);
    return result;
  }

  Future<SaveServerResult> add(String name, String url) async {
    final normalized = _normalizeInput(name, url);
    if (normalized == null) {
      return const SaveServerResult(SaveServerStatus.invalid);
    }
    final state = await read();
    if (_serverByUrl(state.servers, normalized.url) != null) {
      return const SaveServerResult(SaveServerStatus.duplicate);
    }
    final server = StoredServer(
      id: _serverId(normalized.url),
      name: normalized.name,
      url: normalized.url,
    );
    await _write(ServerState(
        servers: [...state.servers, server],
        selectedServerId: state.selectedServerId,
        recentServerId: state.recentServerId));
    return SaveServerResult(SaveServerStatus.added, server: server);
  }

  Future<SaveServerResult> update(String id, String name, String url) async {
    final normalized = _normalizeInput(name, url);
    if (normalized == null) {
      return const SaveServerResult(SaveServerStatus.invalid);
    }
    final state = await read();
    final current = _serverById(state.servers, id);
    if (current == null || current.builtIn) {
      return const SaveServerResult(SaveServerStatus.notFound);
    }
    final duplicate = _serverByUrl(state.servers, normalized.url);
    if (duplicate != null && duplicate.id != id) {
      return const SaveServerResult(SaveServerStatus.duplicate);
    }
    final server =
        StoredServer(id: id, name: normalized.name, url: normalized.url);
    await _write(ServerState(
      servers: state.servers
          .map((candidate) => candidate.id == id ? server : candidate)
          .toList(growable: false),
      selectedServerId: state.selectedServerId,
      recentServerId: state.recentServerId,
    ));
    return SaveServerResult(SaveServerStatus.updated, server: server);
  }

  Future<void> remove(String id) async {
    final state = await read();
    if (id == officialServerId) return;
    await _write(ServerState(
      servers: state.servers
          .where((server) => server.id != id)
          .toList(growable: false),
      selectedServerId: state.selectedServerId == id
          ? officialServerId
          : state.selectedServerId,
      recentServerId: state.recentServerId == id ? null : state.recentServerId,
    ));
  }

  Future<void> select(String id, {bool markRecent = false}) async {
    final state = await read();
    if (_serverById(state.servers, id) == null) return;
    await _write(ServerState(
      servers: state.servers,
      selectedServerId: id,
      recentServerId: markRecent ? id : state.recentServerId,
    ));
  }

  Future<void> rememberUrl(String url,
      {String? name, bool select = true, bool recent = false}) async {
    final normalizedUrl = normalizeServerUrl(url);
    var state = await read();
    var server = _serverByUrl(state.servers, normalizedUrl);
    if (server == null) {
      final added = await add(
          name?.trim().isNotEmpty == true ? name! : _hostName(normalizedUrl),
          normalizedUrl);
      server = added.server;
      state = await read();
    }
    if (server != null && (select || recent)) {
      await _write(ServerState(
        servers: state.servers,
        selectedServerId: select ? server.id : state.selectedServerId,
        recentServerId: recent ? server.id : state.recentServerId,
      ));
    }
  }

  Future<void> rememberAccounts(Iterable<StoredAccount> accounts) async {
    for (final account in accounts) {
      await rememberUrl(account.serverUrl, select: false);
    }
  }

  Future<void> _write(ServerState state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        storageKey,
        jsonEncode({
          'servers': state.servers
              .where((server) => !server.builtIn)
              .map((server) => server.toJson())
              .toList(growable: false),
          'selected_server_id': state.selectedServerId,
          'recent_server_id': state.recentServerId,
        }));
  }

  ServerState _decode(String? value) {
    if (value == null) {
      return ServerState(
          servers: [officialServer], selectedServerId: officialServerId);
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final servers = <StoredServer>[officialServer];
      final rawServers = decoded['servers'];
      if (rawServers is List) {
        for (final item in rawServers.whereType<Map>()) {
          final id = item['id'];
          final name = item['name'];
          final url = item['url'];
          if (id is String &&
              id.isNotEmpty &&
              id != officialServerId &&
              name is String &&
              name.trim().isNotEmpty &&
              url is String) {
            try {
              servers.add(StoredServer(
                  id: id, name: name.trim(), url: normalizeServerUrl(url)));
            } catch (_) {
              continue;
            }
          }
        }
      }
      return ServerState(
        servers: servers,
        selectedServerId: decoded['selected_server_id'] is String
            ? decoded['selected_server_id'] as String
            : officialServerId,
        recentServerId: decoded['recent_server_id'] is String
            ? decoded['recent_server_id'] as String
            : null,
      );
    } catch (_) {
      return ServerState(
          servers: [officialServer], selectedServerId: officialServerId);
    }
  }

  Future<List<StoredServer>> _migrationCandidates(
      SharedPreferences preferences) async {
    final values = <String>{
      if (preferences.getString('magicchat.server_url') case final url?) url,
    };
    return values.map((url) {
      final normalized = normalizeServerUrl(url);
      return StoredServer(
          id: _serverId(normalized),
          name: _hostName(normalized),
          url: normalized);
    }).toList(growable: false);
  }

  ({String name, String url})? _normalizeInput(String name, String url) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return null;
    try {
      return (name: normalizedName, url: normalizeServerUrl(url));
    } catch (_) {
      return null;
    }
  }

  StoredServer? _serverById(List<StoredServer> servers, String? id) {
    if (id == null) return null;
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  StoredServer? _serverByUrl(List<StoredServer> servers, String url) {
    String normalized;
    try {
      normalized = normalizeServerUrl(url);
    } catch (_) {
      return null;
    }
    for (final server in servers) {
      if (normalizeServerUrl(server.url) == normalized) return server;
    }
    return null;
  }

  String _serverId(String url) =>
      'server-${sha256.convert(utf8.encode(url)).toString().substring(0, 16)}';

  String _hostName(String url) => Uri.parse(url).host;
}
