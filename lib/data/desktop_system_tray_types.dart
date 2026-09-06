import '../domain/models.dart';
import 'chat_preferences.dart';

abstract interface class DesktopSystemTrayController {
  Future<bool> initialize({
    required void Function(String conversationId) onOpenConversation,
  });

  Future<void> update({
    required int unreadCount,
    required Iterable<ChatConversation> conversations,
    required MessageNotificationPrivacy privacy,
    Iterable<Contact> contacts = const [],
  });

  Future<void> handleMenuAction(String? key);

  Future<void> dispose();
}
