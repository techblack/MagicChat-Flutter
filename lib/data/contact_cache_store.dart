import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'message_cache_store.dart';

/// 按账号隔离保存联系人昵称、备注和头像，避免消息首屏先显示用户 ID。
class ContactCacheStore {
  static const _keyPrefix = 'magicchat.contact-cache.v1.';
  static final _memory = <String, List<Contact>>{};

  String _scopeKey(MessageCacheScope scope) {
    final value = '${scope.serverUrl.trim()}|${scope.userId.trim()}';
    return '$_keyPrefix${base64Url.encode(utf8.encode(value)).replaceAll('=', '')}';
  }

  String _key(MessageCacheScope scope) => _scopeKey(scope);

  Future<List<Contact>> read(MessageCacheScope? scope) async {
    if (scope == null) return const [];
    final memory = _memory[_scopeKey(scope)];
    if (memory != null) return List<Contact>.unmodifiable(memory);
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key(scope));
    if (value == null) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) throw const FormatException('contact cache list');
      final contacts = decoded
          .whereType<Map>()
          .map((item) => Contact(
                id: '${item['id'] ?? ''}',
                name: '${item['name'] ?? ''}',
                nickname: '${item['nickname'] ?? ''}',
                email: '${item['email'] ?? ''}',
                phone: '${item['phone'] ?? ''}',
                avatar: '${item['avatar'] ?? ''}',
                online: item['online'] == true,
                type: item['type'] == 'app' ? 'app' : 'user',
              ))
          .where((contact) => contact.id.trim().isNotEmpty)
          .toList(growable: false);
      _memory[_scopeKey(scope)] = contacts;
      return List<Contact>.unmodifiable(contacts);
    } catch (_) {
      await prefs.remove(_key(scope));
      return const [];
    }
  }

  Future<void> write(
      MessageCacheScope? scope, Iterable<Contact> contacts) async {
    if (scope == null) return;
    final cacheKey = _scopeKey(scope);
    final previous = _memory[cacheKey] ?? await read(scope);
    final merged = <String, Contact>{
      for (final contact in previous) contact.id: contact,
    };
    for (final contact in contacts) {
      if (contact.id.trim().isEmpty) continue;
      final old = merged[contact.id];
      merged[contact.id] = old == null ? contact : _merge(old, contact);
    }
    final values = merged.values
        .where((contact) => contact.id.trim().isNotEmpty)
        .toList(growable: false);
    _memory[cacheKey] = values;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(scope),
        jsonEncode(values
            .map((contact) => {
                  'id': contact.id,
                  'name': contact.name,
                  'nickname': contact.nickname,
                  'email': contact.email,
                  'phone': contact.phone,
                  'avatar': contact.avatar,
                  'online': contact.online,
                  'type': contact.type,
                })
            .toList(growable: false)));
  }

  Contact _merge(Contact old, Contact next) => old.copyWith(
      name: next.name.trim().isNotEmpty ? next.name : null,
      nickname: next.nickname.trim().isNotEmpty ? next.nickname : null,
      email: next.email.trim().isNotEmpty ? next.email : null,
      phone: next.phone.trim().isNotEmpty ? next.phone : null,
      avatar: next.avatar.trim().isNotEmpty ? next.avatar : null,
      online: next.online,
      type: next.type,
      role: next.role,
      joined: next.joined,
      memberCount: next.memberCount,
      visibility: next.visibility);

  Future<void> remember(
      MessageCacheScope? scope, Iterable<Contact> contacts) async {
    await write(scope, contacts);
  }

  Future<void> clearAll() async {
    _memory.clear();
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs.getKeys().where((key) => key.startsWith(_keyPrefix))) {
      await prefs.remove(key);
    }
  }
}
