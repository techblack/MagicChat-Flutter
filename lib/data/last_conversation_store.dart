import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'message_cache_store_types.dart';

/// 按 Server 和账号记住最近打开的会话。
class LastConversationStore {
  const LastConversationStore();

  static const _keyPrefix = 'magicchat.chat.last-conversation.v1.';
  static const _maximumConversationIdLength = 512;

  Future<String> read(MessageCacheScope? scope) async {
    if (scope == null) return '';
    final prefs = await SharedPreferences.getInstance();
    final key = _key(scope);
    final value = _normalize(prefs.getString(key));
    if (value.isEmpty && prefs.containsKey(key)) await prefs.remove(key);
    return value;
  }

  Future<void> write(MessageCacheScope? scope, String conversationId) async {
    if (scope == null) return;
    final value = _normalize(conversationId);
    if (value.isEmpty) {
      await clear(scope);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(scope), value);
  }

  Future<void> clear(MessageCacheScope? scope) async {
    if (scope == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(scope));
  }

  Future<void> clearIfMatches(
      MessageCacheScope? scope, String conversationId) async {
    if (await read(scope) == conversationId.trim()) await clear(scope);
  }

  String _key(MessageCacheScope scope) {
    final account = '${scope.serverUrl.trim()}|${scope.userId.trim()}';
    final encoded = base64Url.encode(utf8.encode(account)).replaceAll('=', '');
    return '$_keyPrefix$encoded';
  }

  String _normalize(String? value) {
    final id = value?.trim() ?? '';
    return id.isEmpty || id.length > _maximumConversationIdLength ? '' : id;
  }
}
