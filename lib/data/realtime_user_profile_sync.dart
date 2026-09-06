import '../domain/models.dart';
import 'contact_cache_store.dart';
import 'message_cache_store.dart';
import 'realtime_store.dart';
import 'repository.dart';

class RealtimeUserProfileSync {
  RealtimeUserProfileSync({
    required this.repository,
    required this.store,
    required this.cacheScope,
    ContactCacheStore? contactCacheStore,
  }) : contactCacheStore = contactCacheStore ?? ContactCacheStore();

  final MagicChatRepository repository;
  final RealtimeStore store;
  final MessageCacheScope? Function() cacheScope;
  final ContactCacheStore contactCacheStore;
  final _latestGeneration = <String, int>{};
  final _latestVersion = <String, DateTime>{};
  bool _disposed = false;

  Future<void> handle(Map<String, dynamic> event) async {
    if (_disposed || event['event'] != 'user.profile.updated') return;
    final payload = event['payload'];
    if (payload is! Map<String, dynamic>) return;
    final rawUserId = payload['user_id'];
    final rawUpdatedAt = payload['updated_at'];
    if (rawUserId is! String ||
        rawUserId.trim().isEmpty ||
        rawUpdatedAt is! String ||
        rawUpdatedAt.trim().isEmpty) return;
    final userId = rawUserId.trim();
    if (!_isKnownUser(userId)) return;
    final key = userId.toLowerCase();
    final version = DateTime.tryParse(rawUpdatedAt.trim());
    if (version == null ||
        !version.isAfter(
            _latestVersion[key] ?? DateTime.fromMillisecondsSinceEpoch(0))) {
      return;
    }
    _latestVersion[key] = version;
    final generation = (_latestGeneration[key] ?? 0) + 1;
    _latestGeneration[key] = generation;
    try {
      final profiles = await repository.resolveUsers([userId]);
      if (_disposed || _latestGeneration[key] != generation) return;
      Contact? profile;
      for (final candidate in profiles) {
        if (candidate.type == 'user' &&
            candidate.id.trim().toLowerCase() == key) {
          profile = candidate;
          break;
        }
      }
      if (profile == null) return;
      store.replaceUserProfile(profile);
      await contactCacheStore.replaceUserProfiles(cacheScope(), [profile]);
    } catch (_) {
      // 单次资料刷新失败时保留当前资料，下一次事件仍可重试。
      if (_latestGeneration[key] == generation) _latestVersion.remove(key);
    }
  }

  bool _isKnownUser(String userId) {
    final key = userId.toLowerCase();
    if ((store.currentUserId ?? '').trim().toLowerCase() == key) return true;
    if (store.contacts.keys.any((id) => id.trim().toLowerCase() == key))
      return true;
    for (final conversation in store.conversations.values) {
      if (conversation.members.any(
        (member) =>
            member.type == 'user' && member.id.trim().toLowerCase() == key,
      )) return true;
    }
    return false;
  }

  void dispose() {
    _disposed = true;
    _latestGeneration.clear();
    _latestVersion.clear();
  }
}
