import '../domain/models.dart';
import 'chat_preferences.dart';

class DesktopSystemTray {
  DesktopSystemTray({Object? windowController, Object? platform});

  Future<bool> initialize({
    required void Function(String conversationId) onOpenConversation,
  }) async =>
      false;

  Future<void> update({
    required int unreadCount,
    required Iterable<ChatConversation> conversations,
    required MessageNotificationPrivacy privacy,
    Iterable<Contact> contacts = const [],
  }) async {}

  Future<void> handleMenuAction(String? key) async {}

  Future<void> dispose() async {}
}
