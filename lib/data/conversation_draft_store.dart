import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'message_cache_store_types.dart';

const conversationDraftMaxAge = Duration(days: 7);

class ConversationDraft {
  const ConversationDraft({
    required this.text,
    required this.updatedAt,
    this.markdownMode = false,
    this.replyTo,
  });

  final String text;
  final int updatedAt;
  final bool markdownMode;
  final MessageReply? replyTo;

  bool get isEmpty => text.isEmpty && replyTo == null;

  String get preview {
    if (text.isNotEmpty) return text.replaceAll(RegExp(r'\s+'), ' ');
    final reply = replyTo;
    return reply == null ? '' : '回复 ${reply.author}：${reply.text}';
  }

  Map<String, dynamic> toJson() => {
        'markdown_mode': markdownMode,
        if (replyTo != null)
          'reply_to': {
            'id': replyTo!.id,
            'author': replyTo!.author,
            if (replyTo!.authorId != null) 'author_id': replyTo!.authorId,
            if (replyTo!.sequence != null) 'sequence': replyTo!.sequence,
            'text': replyTo!.text,
          },
        'text': text,
        'updated_at': updatedAt,
      };

  static ConversationDraft? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final text = json['text'];
    final updatedAt = json['updated_at'];
    final rawReply = json['reply_to'];
    if (text is! String ||
        updatedAt is! num ||
        !updatedAt.isFinite ||
        updatedAt % 1 != 0 ||
        (rawReply != null && rawReply is! Map)) {
      return null;
    }
    MessageReply? replyTo;
    try {
      replyTo = rawReply is Map
          ? MessageReply.fromJson(Map<String, dynamic>.from(rawReply))
          : null;
    } catch (_) {
      return null;
    }
    final draft = ConversationDraft(
      text: text,
      updatedAt: updatedAt.toInt(),
      markdownMode: json['markdown_mode'] == true,
      replyTo: replyTo,
    );
    return draft.isEmpty ? null : draft;
  }
}

class ConversationDraftStore extends ChangeNotifier {
  static const _storageVersion = 1;
  static const _storagePrefix = 'magicchat.conversation-drafts.v1.';
  static const _persistDelay = Duration(seconds: 1);
  static const _notificationDelay = Duration(milliseconds: 300);

  final _drafts = <String, ConversationDraft>{};
  MessageCacheScope? _scope;
  Timer? _persistTimer;
  Timer? _notificationTimer;
  int _loadGeneration = 0;
  int _revision = 0;
  int _persistedRevision = 0;

  ConversationDraft? draftFor(String conversationId) => _drafts[conversationId];

  Future<void> load(MessageCacheScope? scope, {DateTime? now}) async {
    if (_scope == scope) return;
    await flush();
    final generation = ++_loadGeneration;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _scope = scope;
    _drafts.clear();
    _revision = 0;
    _persistedRevision = 0;
    if (scope == null) {
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (generation != _loadGeneration || _scope != scope) return;
    final key = _storageKey(scope);
    final raw = prefs.getString(key);
    var normalized = false;
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map || decoded['version'] != _storageVersion) {
          normalized = true;
        } else {
          final values = decoded['drafts'];
          if (values is! Map) {
            normalized = true;
          } else {
            final cutoff = (now ?? DateTime.now())
                .subtract(conversationDraftMaxAge)
                .millisecondsSinceEpoch;
            for (final entry in values.entries) {
              final id = entry.key;
              final draft = ConversationDraft.fromJson(entry.value);
              if (id is String &&
                  id.isNotEmpty &&
                  draft != null &&
                  draft.updatedAt >= cutoff) {
                _drafts[id] = draft;
              } else {
                normalized = true;
              }
            }
          }
        }
      } catch (_) {
        normalized = true;
      }
    }
    if (normalized) {
      _revision += 1;
      await flush();
    }
    if (generation == _loadGeneration && _scope == scope) notifyListeners();
  }

  void update(
    String conversationId, {
    required String text,
    required bool markdownMode,
    MessageReply? replyTo,
    DateTime? now,
  }) {
    if (_scope == null || conversationId.isEmpty) return;
    final draft = ConversationDraft(
      text: text,
      updatedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
      markdownMode: markdownMode,
      replyTo: replyTo,
    );
    if (draft.isEmpty) {
      if (_drafts.remove(conversationId) == null) return;
      _schedulePersist();
      flushNotifications(force: true);
      return;
    } else {
      _drafts[conversationId] = draft;
    }
    _schedulePersist();
    _scheduleNotification();
  }

  void clear(String conversationId) {
    if (_drafts.remove(conversationId) == null) return;
    _schedulePersist();
    flushNotifications(force: true);
  }

  void _schedulePersist() {
    _revision += 1;
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDelay, () => unawaited(flush()));
  }

  void _scheduleNotification() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer(_notificationDelay, flushNotifications);
  }

  void flushNotifications({bool force = false}) {
    if (_notificationTimer == null && !force) return;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    notifyListeners();
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    final scope = _scope;
    final revision = _revision;
    if (revision == _persistedRevision || scope == null) return;
    final payload = jsonEncode({
      'version': _storageVersion,
      'drafts': {
        for (final entry in _drafts.entries) entry.key: entry.value.toJson(),
      },
    });
    final prefs = await SharedPreferences.getInstance();
    if (_scope != scope) return;
    final key = _storageKey(scope);
    final persisted = _drafts.isEmpty
        ? await prefs.remove(key)
        : await prefs.setString(key, payload);
    if (persisted && _scope == scope) _persistedRevision = revision;
  }

  static String _storageKey(MessageCacheScope scope) {
    String encode(String value) =>
        base64Url.encode(utf8.encode(value.trim())).replaceAll('=', '');
    return '$_storagePrefix${encode(scope.serverUrl)}.${encode(scope.userId)}';
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    unawaited(flush());
    super.dispose();
  }
}
