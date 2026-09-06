import '../domain/models.dart';
import 'chat_preferences.dart';
import 'desktop_system_tray_types.dart';

class DesktopSystemTray implements DesktopSystemTrayController {
  DesktopSystemTray({Object? windowController, Object? platform});

  @override
  Future<bool> initialize({
    required void Function(String conversationId) onOpenConversation,
  }) async =>
      false;

  @override
  Future<void> update({
    required int unreadCount,
    required Iterable<ChatConversation> conversations,
    required MessageNotificationPrivacy privacy,
    Map<String, Contact> contacts = const {},
  }) async {}

  @override
  Future<void> handleMenuAction(String? key) async {}

  @override
  Future<void> dispose() async {}
}
