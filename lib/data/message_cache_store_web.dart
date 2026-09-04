import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'message_cache_store_types.dart';

/// Browser persistence fallback. Records retain the same API and shard keys as
/// native SQLite while SharedPreferences uses IndexedDB/local storage beneath
/// Flutter Web.
class MessageCacheStore {
  MessageCacheStore({String? databaseDirectory});

  static const keyPrefix = 'magicchat.message-cache.v1.';
  static const legacyKeyPrefix = 'magicchat.messages.';
  static final _queues = <String, Future<void>>{};

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
    final cacheKey = key(scope, conversationId, conversationType: type);
    await _queues[cacheKey];
    final preferences = await SharedPreferences.getInstance();
    var encoded = preferences.getString(cacheKey);
    if (encoded == null && type != 'direct') {
      final legacyKey = legacyMessageCachePreferenceKey(scope, conversationId);
      encoded = preferences.getString(legacyKey);
      if (encoded != null) {
        await preferences.setString(cacheKey, encoded);
        await preferences.remove(legacyKey);
      }
    }
    if (encoded == null) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) throw const FormatException('message cache list');
      final records = decoded
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where((value) {
        final sequence = _sequence(value);
        return beforeSequence == null ||
            (sequence != null && sequence < beforeSequence);
      }).toList()
        ..sort(_ascending);
      if (limit != null && records.length > limit) {
        return records.sublist(records.length - limit);
      }
      return records;
    } catch (_) {
      await preferences.remove(cacheKey);
      return const [];
    }
  }

  Future<void> write(
    MessageCacheScope scope,
    String conversationId,
    List<Map<String, dynamic>> messages, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final cacheKey = key(scope, conversationId, conversationType: type);
    await _serialized(cacheKey, () async {
      final preferences = await SharedPreferences.getInstance();
      final records = messages
          .map((message) => _normalized(conversationId, message))
          .toList()
        ..sort(_ascending);
      await preferences.setString(cacheKey, jsonEncode(records));
      if (type != 'direct') {
        await preferences
            .remove(legacyMessageCachePreferenceKey(scope, conversationId));
      }
    });
  }

  Future<void> upsert(
    MessageCacheScope scope,
    String conversationId,
    Map<String, dynamic> message, {
    String conversationType = 'direct',
  }) =>
      upsertAll(scope, conversationId, [message],
          conversationType: conversationType);

  Future<void> upsertAll(
    MessageCacheScope scope,
    String conversationId,
    Iterable<Map<String, dynamic>> messages, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final cacheKey = key(scope, conversationId, conversationType: type);
    await _serialized(cacheKey, () async {
      final preferences = await SharedPreferences.getInstance();
      final existing = _decode(preferences.getString(cacheKey));
      if (existing.isEmpty && type != 'direct') {
        existing.addAll(_decode(preferences.getString(
            legacyMessageCachePreferenceKey(scope, conversationId))));
      }
      final byId = <String, Map<String, dynamic>>{
        for (final record in existing)
          if (record['id'] is String) record['id'] as String: record,
      };
      for (final message in messages) {
        final record = _normalized(conversationId, message);
        byId[record['id'] as String] = record;
      }
      final records = byId.values.toList()..sort(_ascending);
      await preferences.setString(cacheKey, jsonEncode(records));
      if (type != 'direct') {
        await preferences
            .remove(legacyMessageCachePreferenceKey(scope, conversationId));
      }
    });
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
    final type = normalizeMessageCacheConversationType(conversationType);
    final preferences = await SharedPreferences.getInstance();
    final scopePrefix = messageCachePreferenceKey(scope, '', 'direct');
    final typeMarker = type == 'direct'
        ? null
        : '.${base64Url.encode(utf8.encode(type)).replaceAll('=', '')}.';
    final records = <Map<String, dynamic>>[];
    for (final cacheKey in preferences.getKeys()) {
      if (!cacheKey.startsWith(scopePrefix) ||
          (typeMarker == null
              ? messageCacheConversationTypes
                  .where((value) => value != 'direct')
                  .any((value) => cacheKey.contains(
                      '.${base64Url.encode(utf8.encode(value)).replaceAll('=', '')}.'))
              : !cacheKey.contains(typeMarker))) {
        continue;
      }
      await _queues[cacheKey];
      records.addAll(_decode(preferences.getString(cacheKey)));
    }
    final normalizedKeyword = keyword.trim().toLowerCase();
    final normalizedSender = senderId?.trim();
    final types = contentTypes
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final fromMs = from?.toUtc().millisecondsSinceEpoch;
    final toMs = to?.toUtc().millisecondsSinceEpoch;
    final filtered = records.where((record) {
      if (conversationId != null &&
          conversationId.isNotEmpty &&
          record['conversation_id'] != conversationId) {
        return false;
      }
      if (normalizedKeyword.isNotEmpty &&
          !'${record['author'] ?? ''}\n${record['text'] ?? ''}'
              .toLowerCase()
              .contains(normalizedKeyword)) {
        return false;
      }
      if (normalizedSender != null &&
          normalizedSender.isNotEmpty &&
          record['author_id'] != normalizedSender) {
        return false;
      }
      if (types.isNotEmpty && !types.contains('${record['content_type']}')) {
        return false;
      }
      final timestamp = _createdAtMs(record);
      if (fromMs != null && (timestamp == null || timestamp < fromMs)) {
        return false;
      }
      if (toMs != null && (timestamp == null || timestamp > toMs)) return false;
      return true;
    }).toList()
      ..sort(_descending);
    return filtered.take(limit).toList(growable: false);
  }

  Future<void> clear(
    MessageCacheScope scope,
    String conversationId, {
    String conversationType = 'direct',
  }) async {
    final type = normalizeMessageCacheConversationType(conversationType);
    final cacheKey = key(scope, conversationId, conversationType: type);
    await _serialized(cacheKey, () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(cacheKey);
      if (type != 'direct') {
        await preferences
            .remove(legacyMessageCachePreferenceKey(scope, conversationId));
      }
    });
  }

  Future<void> clearScope(MessageCacheScope scope) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = messageCachePreferenceKey(scope, '', 'direct');
    final keys = preferences
        .getKeys()
        .where((value) => value.startsWith(prefix))
        .toList(growable: false);
    for (final cacheKey in keys) {
      await _queues[cacheKey];
      await preferences.remove(cacheKey);
    }
  }

  Future<void> clearAll() async {
    await Future.wait(_queues.values);
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences
        .getKeys()
        .where((value) =>
            value.startsWith(keyPrefix) || value.startsWith(legacyKeyPrefix))
        .toList(growable: false);
    for (final cacheKey in keys) {
      await preferences.remove(cacheKey);
    }
  }

  Future<String> journalMode(MessageCacheScope scope,
          {String conversationType = 'direct'}) async =>
      'web-persistent-json';

  Future<String> databasePath(MessageCacheScope scope,
          {String conversationType = 'direct'}) async =>
      'shared-preferences:${normalizeMessageCacheConversationType(conversationType)}';

  Future<void> close() async {}

  List<Map<String, dynamic>> _decode(String? encoded) {
    if (encoded == null) return [];
    try {
      final decoded = jsonDecode(encoded);
      return decoded is List
          ? decoded
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _normalized(
      String conversationId, Map<String, dynamic> message) {
    final messageId = message['id'];
    if (messageId is! String || messageId.trim().isEmpty) {
      throw ArgumentError.value(messageId, 'message.id', '消息 ID 不能为空');
    }
    return {
      ...message,
      if (message['conversation_id'] is! String ||
          (message['conversation_id'] as String).isEmpty)
        'conversation_id': conversationId,
    };
  }

  Future<void> _serialized(
      String cacheKey, Future<void> Function() operation) async {
    final previous = _queues[cacheKey] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _queues[cacheKey] = next;
    try {
      await next;
    } finally {
      if (identical(_queues[cacheKey], next)) _queues.remove(cacheKey);
    }
  }

  int _ascending(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftSequence = _sequence(left);
    final rightSequence = _sequence(right);
    if (leftSequence != null || rightSequence != null) {
      if (leftSequence == null) return 1;
      if (rightSequence == null) return -1;
      final compared = leftSequence.compareTo(rightSequence);
      if (compared != 0) return compared;
    }
    final timestamp =
        (_createdAtMs(left) ?? 0).compareTo(_createdAtMs(right) ?? 0);
    if (timestamp != 0) return timestamp;
    return '${left['id']}'.compareTo('${right['id']}');
  }

  int _descending(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftSequence = _sequence(left);
    final rightSequence = _sequence(right);
    if (leftSequence != null || rightSequence != null) {
      if (leftSequence == null) return 1;
      if (rightSequence == null) return -1;
      final compared = rightSequence.compareTo(leftSequence);
      if (compared != 0) return compared;
    }
    final timestamp =
        (_createdAtMs(right) ?? 0).compareTo(_createdAtMs(left) ?? 0);
    if (timestamp != 0) return timestamp;
    return '${right['id']}'.compareTo('${left['id']}');
  }

  int? _sequence(Map<String, dynamic> value) {
    final sequence = value['sequence'] ?? value['seq'];
    return sequence is num ? sequence.toInt() : null;
  }

  int? _createdAtMs(Map<String, dynamic> value) {
    final createdAt = value['created_at'];
    return createdAt is String
        ? DateTime.tryParse(createdAt)?.toUtc().millisecondsSinceEpoch
        : null;
  }
}
