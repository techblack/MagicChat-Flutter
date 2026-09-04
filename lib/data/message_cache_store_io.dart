import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'message_cache_store_types.dart';

/// SQLite-backed message cache for Android, iOS, macOS, Windows and Linux.
///
/// Each account/server scope owns one WAL database per conversation type. This
/// keeps busy group histories independent from direct, app and topic traffic.
class MessageCacheStore {
  MessageCacheStore({String? databaseDirectory})
      : _databaseDirectory = databaseDirectory;

  static const keyPrefix = 'magicchat.message-cache.v1.';
  static const legacyKeyPrefix = 'magicchat.messages.';
  static const _databasePrefix = 'magicchat_messages_';

  static final _databases = <String, _DatabaseEntry>{};

  final String? _databaseDirectory;
  final Object _owner = Object();
  final _ownedPaths = <String>{};

  String key(MessageCacheScope scope, String conversationId,
          {String conversationType = 'direct'}) =>
      messageCachePreferenceKey(scope, conversationId, conversationType);

  Future<List<Map<String, dynamic>>> read(
    MessageCacheScope scope,
    String conversationId, {
    String conversationType = 'direct',
    int? beforeSequence,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) return const [];
    final type = normalizeMessageCacheConversationType(conversationType);
    final database = await _database(scope, type);
    var rows = _readRows(database, conversationId,
        beforeSequence: beforeSequence, limit: limit);
    if (rows.isEmpty) {
      await _migratePreference(scope, conversationId, type);
      rows = _readRows(database, conversationId,
          beforeSequence: beforeSequence, limit: limit);
    }
    return rows;
  }

  Future<void> write(
    MessageCacheScope scope,
    String conversationId,
    List<Map<String, dynamic>> messages, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final database = await _database(scope, type);
    _transaction(database, () {
      database.execute(
          'DELETE FROM messages WHERE conversation_id = ?', [conversationId]);
      for (final message in messages) {
        _writeRecord(database, conversationId, message);
      }
    });
    await _removePreference(scope, conversationId, type);
  }

  Future<void> upsert(
    MessageCacheScope scope,
    String conversationId,
    Map<String, dynamic> message, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final database = await _database(scope, type);
    _writeRecord(database, conversationId, message);
    await _removePreference(scope, conversationId, type);
  }

  Future<void> upsertAll(
    MessageCacheScope scope,
    String conversationId,
    Iterable<Map<String, dynamic>> messages, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final database = await _database(scope, type);
    _transaction(database, () {
      for (final message in messages) {
        _writeRecord(database, conversationId, message);
      }
    });
    await _removePreference(scope, conversationId, type);
  }

  Future<List<Map<String, dynamic>>> search(
    MessageCacheScope scope,
    String? conversationId, {
    String keyword = '',
    String? senderId,
    DateTime? from,
    DateTime? to,
    Iterable<String> contentTypes = const [],
    String conversationType = 'direct',
    int limit = 100,
  }) async {
    if (limit <= 0) return const [];
    final database = await _database(
        scope, normalizeMessageCacheConversationType(conversationType));
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (conversationId != null && conversationId.isNotEmpty) {
      clauses.add('conversation_id = ?');
      arguments.add(conversationId);
    }
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isNotEmpty) {
      clauses.add("searchable_text LIKE ? ESCAPE '\\'");
      arguments.add('%${_escapeLike(normalizedKeyword)}%');
    }
    final normalizedSender = senderId?.trim();
    if (normalizedSender != null && normalizedSender.isNotEmpty) {
      clauses.add('sender_id = ?');
      arguments.add(normalizedSender);
    }
    if (from != null) {
      clauses.add('created_at_ms >= ?');
      arguments.add(from.toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      clauses.add('created_at_ms <= ?');
      arguments.add(to.toUtc().millisecondsSinceEpoch);
    }
    final types = contentTypes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (types.isNotEmpty) {
      clauses
          .add('content_type IN (${List.filled(types.length, '?').join(',')})');
      arguments.addAll(types);
    }
    arguments.add(limit);
    final result = database.select(
      'SELECT payload_json FROM messages '
      '${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')} '} '
      'ORDER BY CASE WHEN sequence IS NULL THEN 1 ELSE 0 END, '
      'sequence DESC, created_at_ms DESC, message_id DESC LIMIT ?',
      arguments,
    );
    return _decodeRows(result);
  }

  Future<void> clear(
    MessageCacheScope scope,
    String conversationId, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final database = await _database(scope, type);
    database.execute(
        'DELETE FROM messages WHERE conversation_id = ?', [conversationId]);
    await _removePreference(scope, conversationId, type);
  }

  Future<void> clearScope(MessageCacheScope scope) async {
    for (final type in messageCacheConversationTypes) {
      final path = await databasePath(scope, conversationType: type);
      await _closePath(path);
      await _deleteDatabaseFiles(path);
    }
    await _clearPreferences(scope: scope);
  }

  Future<void> clearAll() async {
    final directory = await _directory();
    for (final path in _databases.keys.toList(growable: false)) {
      await _closePath(path);
    }
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File &&
            p.basename(entity.path).startsWith(_databasePrefix) &&
            await entity.exists()) {
          await entity.delete();
        }
      }
    }
    await _clearPreferences();
  }

  Future<String> journalMode(MessageCacheScope scope,
      {String conversationType = 'direct'}) async {
    final database = await _database(
        scope, normalizeMessageCacheConversationType(conversationType));
    return '${database.select('PRAGMA journal_mode').single['journal_mode']}'
        .toLowerCase();
  }

  Future<String> databasePath(MessageCacheScope scope,
      {String conversationType = 'direct'}) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final directory = await _directory();
    final identity = sha256
        .convert(utf8
            .encode('${scope.serverUrl.trim()}\u0000${scope.userId.trim()}'))
        .toString()
        .substring(0, 32);
    return p.join(directory.path, '$_databasePrefix${identity}_$type.sqlite3');
  }

  Future<void> close() async {
    for (final path in _ownedPaths.toList(growable: false)) {
      final entry = _databases[path];
      if (entry == null) continue;
      entry.owners.remove(_owner);
      if (entry.owners.isEmpty) await _closePath(path);
    }
    _ownedPaths.clear();
  }

  Future<Directory> _directory() async {
    final configured = _databaseDirectory;
    final directory = configured == null
        ? Directory(p.join(
            (await getApplicationSupportDirectory()).path, 'message-cache'))
        : Directory(configured);
    await directory.create(recursive: true);
    return directory;
  }

  Future<Database> _database(
      MessageCacheScope scope, String conversationType) async {
    final path = await databasePath(scope, conversationType: conversationType);
    final existing = _databases[path];
    if (existing != null) {
      existing.owners.add(_owner);
      _ownedPaths.add(path);
      return existing.database;
    }
    final database = sqlite3.open(path);
    try {
      database.execute('PRAGMA journal_mode = WAL');
      database.execute('PRAGMA synchronous = NORMAL');
      database.execute('PRAGMA foreign_keys = ON');
      database.execute('PRAGMA busy_timeout = 5000');
      database.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          conversation_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          sequence INTEGER,
          created_at_ms INTEGER,
          sender_id TEXT,
          content_type TEXT NOT NULL,
          searchable_text TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          PRIMARY KEY (conversation_id, message_id)
        )
      ''');
      database.execute('''
        CREATE INDEX IF NOT EXISTS messages_conversation_sequence
        ON messages (conversation_id, sequence DESC)
      ''');
      database.execute('''
        CREATE INDEX IF NOT EXISTS messages_search_filters
        ON messages (conversation_id, sender_id, content_type, created_at_ms)
      ''');
      database.execute('PRAGMA user_version = 1');
    } catch (_) {
      database.dispose();
      rethrow;
    }
    _databases[path] = _DatabaseEntry(database, {_owner});
    _ownedPaths.add(path);
    return database;
  }

  List<Map<String, dynamic>> _readRows(Database database, String conversationId,
      {int? beforeSequence, int? limit}) {
    final clauses = <String>['conversation_id = ?'];
    final arguments = <Object?>[conversationId];
    if (beforeSequence != null) {
      clauses.add('sequence < ?');
      arguments.add(beforeSequence);
    }
    final limitClause = limit == null ? '' : 'LIMIT ?';
    if (limit != null) arguments.add(limit);
    final result = database.select('''
      SELECT payload_json FROM (
        SELECT payload_json, sequence, created_at_ms, message_id
        FROM messages
        WHERE ${clauses.join(' AND ')}
        ORDER BY CASE WHEN sequence IS NULL THEN 1 ELSE 0 END,
                 sequence DESC, created_at_ms DESC, message_id DESC
        $limitClause
      )
      ORDER BY CASE WHEN sequence IS NULL THEN 1 ELSE 0 END,
               sequence ASC, created_at_ms ASC, message_id ASC
    ''', arguments);
    return _decodeRows(result);
  }

  List<Map<String, dynamic>> _decodeRows(ResultSet rows) => rows
      .map((row) {
        final value = jsonDecode(row['payload_json'] as String);
        return value is Map
            ? Map<String, dynamic>.from(value)
            : <String, dynamic>{};
      })
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  void _writeRecord(
      Database database, String conversationId, Map<String, dynamic> message) {
    final messageId = message['id'];
    if (messageId is! String || messageId.trim().isEmpty) {
      throw ArgumentError.value(messageId, 'message.id', '消息 ID 不能为空');
    }
    final normalized = Map<String, dynamic>.from(message);
    final recordConversation = normalized['conversation_id'];
    if (recordConversation is! String || recordConversation.isEmpty) {
      normalized['conversation_id'] = conversationId;
    }
    final sequence = normalized['sequence'] ?? normalized['seq'];
    final createdAt = normalized['created_at'];
    final senderId = normalized['author_id'];
    final contentType = '${normalized['content_type'] ?? 'text'}';
    final text = '${normalized['text'] ?? ''}';
    final author = '${normalized['author'] ?? ''}';
    final createdAtMs = createdAt is String
        ? DateTime.tryParse(createdAt)?.toUtc().millisecondsSinceEpoch
        : null;
    database.execute('''
      INSERT INTO messages (
        conversation_id, message_id, sequence, created_at_ms, sender_id,
        content_type, searchable_text, payload_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(conversation_id, message_id) DO UPDATE SET
        sequence = excluded.sequence,
        created_at_ms = excluded.created_at_ms,
        sender_id = excluded.sender_id,
        content_type = excluded.content_type,
        searchable_text = excluded.searchable_text,
        payload_json = excluded.payload_json
    ''', [
      conversationId,
      messageId,
      sequence is num ? sequence.toInt() : null,
      createdAtMs,
      senderId is String ? senderId : null,
      contentType,
      '$author\n$text'.toLowerCase(),
      jsonEncode(normalized),
    ]);
  }

  void _transaction(Database database, void Function() operation) {
    database.execute('BEGIN IMMEDIATE');
    try {
      operation();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> _migratePreference(MessageCacheScope scope,
      String conversationId, String conversationType) async {
    final preferences = await SharedPreferences.getInstance();
    final candidates = {
      key(scope, conversationId, conversationType: conversationType),
      legacyMessageCachePreferenceKey(scope, conversationId),
    };
    for (final cacheKey in candidates) {
      final encoded = preferences.getString(cacheKey);
      if (encoded == null) continue;
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) {
          await upsertAll(
              scope,
              conversationId,
              decoded
                  .whereType<Map>()
                  .map((value) => Map<String, dynamic>.from(value)),
              conversationType: conversationType);
        }
      } catch (_) {
        // A malformed legacy blob is discarded and must not block SQLite reads.
      } finally {
        await preferences.remove(cacheKey);
      }
      break;
    }
  }

  Future<void> _removePreference(MessageCacheScope scope, String conversationId,
      String conversationType) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences
        .remove(key(scope, conversationId, conversationType: conversationType));
    if (conversationType != 'direct') {
      await preferences
          .remove(legacyMessageCachePreferenceKey(scope, conversationId));
    }
  }

  Future<void> _clearPreferences({MessageCacheScope? scope}) async {
    final preferences = await SharedPreferences.getInstance();
    final scopePrefix = scope == null
        ? keyPrefix
        : '$keyPrefix${[
            scope.serverUrl.trim(),
            scope.userId.trim(),
          ].map((value) => base64Url.encode(utf8.encode(value)).replaceAll('=', '')).join('.')}.';
    final keys = preferences
        .getKeys()
        .where((value) =>
            value.startsWith(scopePrefix) ||
            (scope == null && value.startsWith(legacyKeyPrefix)))
        .toList(growable: false);
    for (final value in keys) {
      await preferences.remove(value);
    }
  }

  Future<void> _closePath(String path) async {
    final entry = _databases.remove(path);
    if (entry != null) entry.database.dispose();
    _ownedPaths.remove(path);
  }

  Future<void> _deleteDatabaseFiles(String path) async {
    for (final candidate in [path, '$path-wal', '$path-shm']) {
      final file = File(candidate);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

class _DatabaseEntry {
  _DatabaseEntry(this.database, this.owners);

  final Database database;
  final Set<Object> owners;
}
