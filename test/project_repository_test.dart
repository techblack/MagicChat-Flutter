import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/session_store.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('会话解析已关联项目并使用会话项目绑定路由', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/client/conversations') {
            return _jsonResponse({
              'data': {
                'conversations': [
                  {
                    'id': 'group-1',
                    'name': '工程群',
                    'type': 'group',
                    'projects': [
                      {
                        'id': 'project-1',
                        'name': '客户端迭代',
                        'description': '跨端功能复刻',
                      }
                    ],
                  }
                ]
              }
            });
          }
          return _jsonResponse({'data': {}});
        }));

    final conversation = (await repository.conversations()).single;
    await repository.bindConversationProject('group-1', 'project-2');
    await repository.unbindConversationProject('group-1', 'project-1');

    expect(conversation.projects.single.name, '客户端迭代');
    expect(requests[1].method, 'PUT');
    expect(requests[1].url.path,
        '/api/client/conversations/group-1/projects/project-2');
    expect(requests[2].method, 'DELETE');
    expect(requests[2].url.path,
        '/api/client/conversations/group-1/projects/project-1');
  });

  test('浏览器 Cookie 会话不发送占位 Bearer 头', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: SessionStore.cookieSessionToken,
        client: MockClient((request) async {
          requests.add(request);
          return _jsonResponse({
            'data': {
              'user': {
                'id': 'u1',
                'name': '浏览器用户',
                'email': 'web@example.com',
              }
            }
          });
        }));

    await repository.currentUser();

    expect(requests.single.headers.containsKey('Authorization'), isFalse);
  });

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

  test('创建任务透传完整字段', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((value) async {
          if (value.url.path == '/api/client/users/resolve') {
            return _jsonResponse({
              'data': {
                'users': [
                  {
                    'id': 'member-1',
                    'name': '项目成员',
                    'nickname': '小明',
                    'avatar': '/avatars/member.webp',
                  }
                ]
              }
            });
          }
          request = value;
          return _jsonResponse({
            'data': {
              'id': 'task-1',
              'project_id': 'project-1',
              'title': '发布检查',
              'description': '**核对清单**',
              'status': 'todo',
              'priority': 3,
              'start_date': '2026-09-01',
              'due_date': '2026-09-02',
              'labels': ['发布', '冒烟'],
              'assignee': {'id': 'member-1'},
              'reminder': {
                'mode': 'once',
                'timezone': 'Asia/Shanghai',
                'at': '2026-09-01T01:30:00Z'
              }
            }
          });
        }));

    final task = await repository.createTask('project-1', '发布检查',
        description: '**核对清单**',
        priority: 3,
        startDate: '2026-09-01',
        dueDate: '2026-09-02',
        labels: ['发布', '冒烟'],
        assigneeUserId: 'member-1',
        reminder: {
          'mode': 'once',
          'timezone': 'Asia/Shanghai',
          'at': '2026-09-01T09:30:00+08:00'
        });

    expect(request.method, 'POST');
    expect(request.url.path, '/api/client/projects/project-1/tasks');
    expect(jsonDecode(request.body), {
      'title': '发布检查',
      'description': '**核对清单**',
      'status': 'todo',
      'priority': 3,
      'start_date': '2026-09-01',
      'due_date': '2026-09-02',
      'labels': ['发布', '冒烟'],
      'assignee_user_id': 'member-1',
      'reminder': {
        'mode': 'once',
        'timezone': 'Asia/Shanghai',
        'at': '2026-09-01T09:30:00+08:00'
      }
    });
    expect(task.assigneeUserId, 'member-1');
    expect(task.assignee?.displayName, '小明');
    expect(task.assignee?.avatar, '/avatars/member.webp');
    expect(task.labels, ['发布', '冒烟']);
  });

  test('任务分页按筛选条件请求并解析游标', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((value) async {
          request = value;
          return _jsonResponse({
            'data': {
              'tasks': [
                {
                  'id': 'task-1',
                  'project_id': 'project-1',
                  'title': '发布检查',
                  'status': 'in_progress',
                  'priority': 1,
                  'labels': ['release'],
                }
              ],
              'next_cursor': ' next-2 ',
            }
          });
        }));

    final page = await repository.projectTaskPage('project-1',
        cursor: ' cursor-1 ',
        limit: 20,
        keyword: ' 发布 ',
        statuses: ['todo', 'in_progress'],
        priorities: [1, 3]);

    expect(request.method, 'GET');
    expect(request.url.path, '/api/client/projects/project-1/tasks');
    expect(request.url.queryParameters, {
      'cursor': 'cursor-1',
      'keyword': '发布',
      'limit': '20',
      'priority': '1,3',
      'status': 'todo,in_progress',
    });
    expect(page.tasks.single.title, '发布检查');
    expect(page.nextCursor, 'next-2');
  });

  test('消息分页保留服务端历史窗口元数据', () async {
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'test-token',
        client: MockClient((_) async => _jsonResponse({
              'data': {
                'messages': [
                  {
                    'id': 'message-1',
                    'seq': 10,
                    'sender': {'id': 'user-1', 'name': 'Alice'},
                    'body': {'type': 'text', 'content': 'hello'},
                  }
                ],
                'page': {
                  'has_more_before': false,
                  'has_more_after': true,
                  'limit': 20,
                  'newest_seq': 10,
                  'oldest_seq': 10,
                }
              }
            })));

    final messages = await repository.messages('conversation-1');

    expect(messages, isA<MessagePage>());
    final page = messages as MessagePage;
    expect(page.hasMoreBefore, isFalse);
    expect(page.hasMoreAfter, isTrue);
    expect(page.limit, 20);
    expect(page.newestSeq, 10);
    expect(page.oldestSeq, 10);
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
