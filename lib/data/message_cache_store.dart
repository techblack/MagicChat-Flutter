import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Identifies the account that owns a local conversation cache.
class MessageCacheScope {
  const MessageCacheScope({required this.serverUrl, required this.userId});

  final String serverUrl;
  final String userId;

  @override
  bool operator ==(Object other) =>
      other is MessageCacheScope &&
      other.serverUrl == serverUrl &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(serverUrl, userId);
}

/// Stores serialized message records without mixing accounts or servers.
///
/// Message decoding stays in the UI/domain layer so this store can discard a
/// malformed blob without preventing the conversation from loading remotely.
class MessageCacheStore {
  static const keyPrefix = 'magicchat.message-cache.v1.';
  static const legacyKeyPrefix = 'magicchat.messages.';

  String key(MessageCacheScope scope, String conversationId) {
    final parts = [scope.serverUrl.trim(), scope.userId.trim(), conversationId];
    return '$keyPrefix${parts.map(_encode).join('.')}';
  }

  Future<List<Map<String, dynamic>>> read(
      MessageCacheScope scope, String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = key(scope, conversationId);
    final encoded = prefs.getString(cacheKey);
    if (encoded == null) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) throw const FormatException('message cache list');
      return decoded
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false);
    } catch (_) {
      await prefs.remove(cacheKey);
      return const [];
    }
  }

  Future<void> write(MessageCacheScope scope, String conversationId,
      List<Map<String, dynamic>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key(scope, conversationId), jsonEncode(messages));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((value) =>
            value.startsWith(keyPrefix) || value.startsWith(legacyKeyPrefix))
        .toList(growable: false);
    for (final value in keys) {
      await prefs.remove(value);
    }
  }

  String _encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
