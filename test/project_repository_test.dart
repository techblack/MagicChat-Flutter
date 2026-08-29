import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('项目列表保留个人项目属性且写接口解析直接 data', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return _jsonResponse({
              'data': {
                'personal_project': {
                  'id': 'personal-1',
                  'name': '我的项目',
                  'description': '个人工作区',
                  'avatar': '/personal.png',
                  'is_personal': true,
                  'updated_at': '2026-08-29T10:00:00Z',
                },
                'projects': [
                  {
                    'id': 'project-1',
                    'name': '客户端迭代',
                    'description': '跨端功能复刻',
                    'avatar': '',
                    'is_personal': false,
                    'updated_at': '2026-08-29T11:00:00Z',
                  }
                ],
                'next_cursor': null,
              }
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'data': {
              'id': request.method == 'POST' ? 'project-2' : 'project-1',
              'name': body['name'],
              'description': body['description'] ?? '跨端功能复刻',
              'avatar': '',
              'is_personal': false,
              'updated_at': '2026-08-29T12:00:00Z',
              'task_counts': {'total': 3},
            }
          });
        }));

    final projects = await repository.projects();
    final created = await repository.createProject('发布计划', description: '九月版本');
    final updated =
        await repository.updateProject('project-1', name: 'Flutter 客户端');

    expect(projects.first.isPersonal, isTrue);
    expect(projects.first.description, '个人工作区');
    expect(projects.last.taskCount, isNull);
    expect(created.id, 'project-2');
    expect(created.taskCount, 3);
    expect(updated.name, 'Flutter 客户端');
    final createRequest = requests.firstWhere((item) => item.method == 'POST');
    expect(jsonDecode(createRequest.body), {
      'name': '发布计划',
      'description': '九月版本',
      'group_ids': [],
    });
    expect(
        requests.every(
            (item) => item.headers['Authorization'] == 'Bearer test-token'),
        isTrue);
  });

  test('项目列表会沿 next_cursor 拉取后续页面', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          final secondPage = request.url.queryParameters['cursor'] == 'next';
          return _jsonResponse({
            'data': {
              'personal_project': secondPage
                  ? null
                  : {
                      'id': 'personal-1',
                      'name': '我的项目',
                      'is_personal': true,
                      'updated_at': '2026-08-29T10:00:00Z',
                    },
              'projects': [
                {
                  'id': secondPage ? 'project-2' : 'project-1',
                  'name': secondPage ? '第二页' : '第一页',
                  'is_personal': false,
                  'updated_at': '2026-08-29T10:00:00Z',
                }
              ],
              'next_cursor': secondPage ? null : 'next',
            }
          });
        }));

    final projects = await repository.projects();

    expect(projects.map((item) => item.id),
        ['personal-1', 'project-1', 'project-2']);
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters['cursor'], 'next');
  });

  test('任务解析嵌套负责人且显式发送清空字段', () async {
    late http.Request updateRequest;
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return _jsonResponse({
              'data': {
                'tasks': [
                  {
                    'id': 'task-1',
                    'project_id': 'project-1',
                    'title': '完成项目页',
                    'status': 'in_progress',
                    'priority': 3,
                    'assignee': {'id': 'user-alice', 'name': 'Alice'},
                  }
                ]
              }
            });
          }
          updateRequest = request;
          return _jsonResponse({
            'data': {
              'id': 'task-1',
              'project_id': 'project-1',
              'title': '完成项目页',
              'description': '',
              'status': 'done',
              'priority': 3,
              'start_date': null,
              'due_date': null,
              'labels': [],
              'assignee': null,
              'reminder': null,
            }
          });
        }));

    final task = (await repository.tasks('project-1')).single;
    await repository.updateTask(
        'project-1',
        'task-1',
        const ProjectTaskUpdate(
            title: '完成项目页',
            description: '',
            status: 'done',
            priority: 3,
            startDate: null,
            dueDate: null,
            labels: [],
            assigneeUserId: null,
            reminder: null));

    expect(task.assigneeUserId, 'user-alice');
    expect(jsonDecode(updateRequest.body), {
      'title': '完成项目页',
      'description': '',
      'status': 'done',
      'priority': 3,
      'start_date': null,
      'due_date': null,
      'labels': [],
      'assignee_user_id': null,
      'reminder': null,
    });
  });

  test('文档创建解析直接 data 且正文标题走协作接口', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/title')) {
            return _jsonResponse({
              'data': {
                'document_id': 'document-1',
                'title': '协作标题',
              }
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'data': {
              'id': request.method == 'POST' ? 'document-1' : 'folder-1',
              'project_id': 'project-1',
              'parent_id': body['parent_id'],
              'kind': request.method == 'POST' ? 'document' : 'folder',
              'document_type':
                  request.method == 'POST' ? body['document_type'] : null,
              'title': body['title'],
              'sort_order': 2,
              'schema_version': 1,
            }
          });
        }));

    final document = await repository.createDocument('project-1', '发布说明',
        documentType: 'markdown');
    final folder = await repository.updateDocument('folder-1', title: '归档');
    final title =
        await repository.updateCollaborativeDocumentTitle('document-1', '协作标题');

    expect(document.documentType, 'markdown');
    expect(document.sortOrder, 2);
    expect(folder.kind, 'folder');
    expect(title, '协作标题');
    expect(jsonDecode(requests.first.body), {
      'kind': 'document',
      'title': '发布说明',
      'parent_id': null,
      'document_type': 'markdown',
    });
    expect(requests.last.url.path,
        '/api/client/document/collaboration/document-1/title');
  });

  test('项目成员按游标拉取并保留负责人展示字段', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          final secondPage = request.url.queryParameters['cursor'] == 'next-1';
          return _jsonResponse({
            'data': {
              'members': [
                {
                  'id': secondPage ? 'user-bob' : 'user-alice',
                  'name': secondPage ? 'Bob' : 'Alice',
                  'nickname': '',
                  'email': secondPage ? 'bob@example.com' : 'alice@example.com',
                  'avatar': '',
                  'display_name': secondPage ? 'Bob' : 'Alice',
                  'role': secondPage ? 'member' : 'owner',
                  'status': 'active',
                  'source_group_ids': secondPage ? ['group-1'] : [],
                }
              ],
              'next_cursor': secondPage ? null : 'next-1',
            }
          });
        }));

    final members = await repository.projectMembers('project-1');

    expect(members.map((item) => item.displayName), ['Alice', 'Bob']);
    expect(members.last.sourceGroupIds, ['group-1']);
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters['cursor'], 'next-1');
  });

  test('项目成员资料字段隐藏时通过用户解析补齐资料', () async {
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return _jsonResponse({
              'data': {
                'users': [
                  {
                    'id': 'user-hidden',
                    'name': '真实成员',
                    'nickname': '小明',
                    'email': 'ming@example.com',
                    'avatar': '/ming.webp',
                  }
                ]
              }
            });
          }
          return _jsonResponse({
            'data': {
              'members': [
                {
                  'id': 'user-hidden',
                  'role': 'member',
                  'status': 'active',
                  'source_group_ids': [],
                }
              ],
              'next_cursor': null,
            }
          });
        }));

    final member = (await repository.projectMembers('project-1')).single;

    expect(member.displayName, '小明');
    expect(member.email, 'ming@example.com');
  });

  test('项目群组授权使用项目 groups 路由且会解析分页', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            final secondPage = request.url.queryParameters['cursor'] == 'next';
            return _jsonResponse({
              'data': {
                'groups': [
                  {
                    'id': secondPage ? 'group-2' : 'group-1',
                    'name': secondPage ? '研发群' : '产品群',
                    'member_count': secondPage ? 4 : 8,
                    'status': 'active',
                    'created_at': '2026-08-29T12:00:00Z',
                  }
                ],
                'next_cursor': secondPage ? null : 'next',
              }
            });
          }
          return _jsonResponse({'data': {}});
        }));

    final groups = await repository.projectGroups('project-1');
    await repository.bindProjectGroup('project-1', 'group-3');
    await repository.unbindProjectGroup('project-1', 'group-3');

    expect(groups.map((item) => item.name), ['产品群', '研发群']);
    expect(requests[1].method, 'GET');
    expect(requests[2].method, 'PUT');
    expect(requests[3].method, 'DELETE');
    expect(
        requests[2].url.path, '/api/client/projects/project-1/groups/group-3');
  });

  test('任务动态可加载且评论响应立即回显', () async {
    final requests = <http.Request>[];
    Map<String, dynamic> activity(String id, String type, String content) => {
          'id': id,
          'project_id': 'project-1',
          'task_id': 'task-1',
          'type': type,
          'actor': {'id': 'user-alice', 'name': 'Alice'},
          'content': content,
          'changes': type == 'updated'
              ? [
                  {'field': 'status', 'from': 'todo', 'to': 'in_progress'}
                ]
              : [],
          'created_at': '2026-08-29T12:00:00Z',
        };
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), {'content': '已完成联调'});
            return _jsonResponse(
                {'data': activity('activity-2', 'commented', '已完成联调')});
          }
          return _jsonResponse({
            'data': {
              'activities': [activity('activity-1', 'updated', '')],
              'next_cursor': null,
            }
          });
        }));

    final activities = await repository.taskActivities('project-1', 'task-1');
    final comment =
        await repository.addTaskComment('project-1', 'task-1', '已完成联调');

    expect(activities.single.actor.displayName, 'Alice');
    expect(activities.single.changes.single.to, 'in_progress');
    expect(comment.type, 'commented');
    expect(comment.content, '已完成联调');
    expect(requests.last.url.path,
        '/api/client/projects/project-1/tasks/task-1/comments');
  });
}

http.Response _jsonResponse(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
