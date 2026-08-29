import 'dart:typed_data';

class ChatConversation {
  const ChatConversation(
      {required this.id,
      required this.title,
      this.preview = '',
      this.announcement = '',
      this.isPublic = false,
      this.avatar = '',
      this.unread = 0,
      this.pinned = false,
      this.muted = false,
      this.lastMessageSeq = 0,
      this.type = 'direct',
      this.members = const []});
  final String id;
  final String title;
  final String preview;
  final String announcement;
  final bool isPublic;
  final String avatar;
  final int unread;
  final bool pinned;
  final bool muted;
  final int lastMessageSeq;
  final String type;
  final List<Contact> members;
}

class ChatMessage {
  const ChatMessage(
      {required this.id,
      required this.text,
      required this.author,
      this.authorId,
      this.conversationId,
      this.sequence,
      this.contentType = 'text',
      this.rawBody = const {},
      this.mine = false,
      this.reactions = const []});
  final String id;
  final String? conversationId;
  final int? sequence;
  final String contentType;
  final Map<String, dynamic> rawBody;
  final String text;
  final String author;
  final String? authorId;
  final bool mine;
  final List<MessageReaction> reactions;
}

class MessageSearchResult {
  const MessageSearchResult(
      {required this.conversationId,
      required this.conversationName,
      required this.message});
  final String conversationId;
  final String conversationName;
  final ChatMessage message;
}

class AttachmentUpload {
  const AttachmentUpload(
      {required this.path,
      required this.name,
      required this.mimeType,
      this.bytes});
  final String path;
  final String name;
  final String mimeType;
  final Uint8List? bytes;
}

class MessageReaction {
  const MessageReaction(
      {required this.text, required this.count, required this.reactedByMe});
  final String text;
  final int count;
  final bool reactedByMe;
}

class Contact {
  const Contact(
      {required this.id,
      required this.name,
      this.online = false,
      this.type = 'user',
      this.role = 'member',
      this.nickname = '',
      this.email = '',
      this.phone = '',
      this.avatar = ''});
  final String id;
  final String name;
  final bool online;
  final String type;
  final String role;
  final String nickname;
  final String email;
  final String phone;
  final String avatar;

  String get displayName => nickname.isEmpty ? name : nickname;
}

class ContactDirectory {
  const ContactDirectory({required this.contacts, required this.mode});
  final List<Contact> contacts;
  final String mode;

  bool get supportsFriendManagement => mode == 'friends';
}

class FriendRequest {
  const FriendRequest(
      {required this.id, required this.userId, required this.status});
  final String id;
  final String userId;
  final String status;
}

class Project {
  const Project(
      {required this.id,
      required this.name,
      this.taskCount,
      this.description = '',
      this.avatar = '',
      this.isPersonal = false,
      this.updatedAt = ''});
  final String id;
  final String name;
  final int? taskCount;
  final String description;
  final String avatar;
  final bool isPersonal;
  final String updatedAt;
}

class ProjectPage {
  const ProjectPage(
      {required this.projects, this.personalProject, this.nextCursor});

  final List<Project> projects;
  final Project? personalProject;
  final String? nextCursor;
}

class ProjectGroup {
  const ProjectGroup(
      {required this.id,
      required this.name,
      this.avatar = '',
      this.status = '',
      this.memberCount = 0,
      this.createdAt = ''});

  final String id;
  final String name;
  final String avatar;
  final String status;
  final int memberCount;
  final String createdAt;
}

class ProjectTask {
  const ProjectTask(
      {required this.id,
      required this.projectId,
      required this.title,
      required this.status,
      this.priority = 2,
      this.description = '',
      this.startDate,
      this.dueDate,
      this.labels = const [],
      this.assignee,
      this.reminder});
  final String id;
  final String projectId;
  final String title;
  final String status;
  final int priority;
  final String description;
  final String? startDate;
  final String? dueDate;
  final List<String> labels;
  final ProjectUser? assignee;
  final Map<String, dynamic>? reminder;
  String? get assigneeUserId => assignee?.id;
}

class ProjectUser {
  const ProjectUser(
      {required this.id, this.name = '', this.nickname = '', this.avatar = ''});

  final String id;
  final String name;
  final String nickname;
  final String avatar;

  String get displayName => nickname.isNotEmpty
      ? nickname
      : name.isNotEmpty
          ? name
          : id;
}

class ProjectMember extends ProjectUser {
  const ProjectMember(
      {required super.id,
      super.name,
      super.nickname,
      super.avatar,
      this.email = '',
      this.displayNameOverride = '',
      this.role = 'member',
      this.status = '',
      this.sourceGroupIds = const []});

  final String email;
  final String displayNameOverride;
  final String role;
  final String status;
  final List<String> sourceGroupIds;

  @override
  String get displayName =>
      displayNameOverride.isNotEmpty ? displayNameOverride : super.displayName;
}

class ProjectTaskActivityChange {
  const ProjectTaskActivityChange(
      {required this.field, required this.from, required this.to});
  final String field;
  final Object? from;
  final Object? to;
}

class ProjectTaskActivity {
  const ProjectTaskActivity(
      {required this.id,
      required this.projectId,
      required this.taskId,
      required this.type,
      required this.actor,
      required this.createdAt,
      this.content = '',
      this.changes = const []});

  final String id;
  final String projectId;
  final String taskId;
  final String type;
  final ProjectUser actor;
  final String content;
  final List<ProjectTaskActivityChange> changes;
  final String createdAt;
}

class ProjectTaskUpdate {
  const ProjectTaskUpdate(
      {required this.title,
      required this.description,
      required this.status,
      required this.priority,
      required this.startDate,
      required this.dueDate,
      required this.labels,
      required this.assigneeUserId,
      required this.reminder});

  final String title;
  final String description;
  final String status;
  final int priority;
  final String? startDate;
  final String? dueDate;
  final List<String> labels;
  final String? assigneeUserId;
  final Map<String, dynamic>? reminder;
}

class ProjectDocument {
  const ProjectDocument(
      {required this.id,
      required this.projectId,
      required this.title,
      this.kind = 'document',
      this.parentId,
      this.documentType,
      this.sortOrder = 0,
      this.schemaVersion = 1});
  final String id;
  final String projectId;
  final String title;
  final String kind;
  final String? parentId;
  final String? documentType;
  final int sortOrder;
  final int schemaVersion;
}

class CurrentUser {
  const CurrentUser(
      {required this.id,
      required this.name,
      required this.email,
      this.nickname = '',
      this.avatar = '',
      this.phone = ''});
  final String id;
  final String name;
  final String email;
  final String nickname;
  final String avatar;
  final String phone;
  String get displayName => nickname.isNotEmpty ? nickname : name;
}
