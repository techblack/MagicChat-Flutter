import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/project_goals_repository.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/domain/project_goal.dart';
import 'package:magicchat_client/features/projects/project_goals_view.dart';

void main() {
  test('Goals 仓储只调用真实任务 API 并保留目标标签', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((request) async {
        requests.add(request);
        final body = request.body.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        if (request.method == 'GET') {
          return _response({
            'data': {
              'tasks': [
                _taskJson(labels: const [projectGoalTaskLabel, 'release'])
              ],
              'next_cursor': null,
            }
          });
        }
        if (request.method == 'DELETE') {
          return _response({
            'data': {'task_id': 'goal-1'}
          });
        }
        return _response({
          'data': _taskJson(
            title: '${body['title'] ?? 'Ship'}',
            status: '${body['status'] ?? 'todo'}',
            labels: body['labels'] is List
                ? (body['labels'] as List).cast<String>()
                : const [projectGoalTaskLabel],
          )
        }, statusCode: request.method == 'POST' ? 201 : 200);
      }),
    );
    final goals = ProjectGoalsRepository(repository);

    final listed = await goals.list('project-1');
    final created = await goals.create(
        'project-1',
        const ProjectGoalInput(
            title: 'Launch',
            description: 'Release the client',
            status: 'todo',
            priority: 3,
            startDate: '2026-09-06',
            dueDate: '2026-09-10',
            labels: ['release']));
    final updated = await goals.update(
        created,
        const ProjectGoalInput(
            title: 'Launch stable',
            description: 'Release stable client',
            status: 'in_progress',
            priority: 3,
            startDate: '2026-09-06',
            dueDate: '2026-09-12',
            labels: ['release']));
    final completed = await goals.updateStatus(updated, 'done');
    await goals.delete(completed);

    expect(listed.single.labels, ['release']);
    expect(created.title, 'Launch');
    expect(completed.status, 'done');
    expect(requests.map((request) => request.method),
        ['GET', 'POST', 'PATCH', 'PATCH', 'DELETE']);
    expect(requests.first.url.path, '/api/client/projects/project-1/tasks');
    expect(requests.first.url.queryParameters['label'], projectGoalTaskLabel);
    expect(jsonDecode(requests[1].body)['labels'],
        [projectGoalTaskLabel, 'release']);
    expect(
        jsonDecode(requests[2].body), containsPair('title', 'Launch stable'));
    expect(jsonDecode(requests[3].body), {'status': 'done'});
    expect(
        requests.last.url.path, '/api/client/projects/project-1/tasks/goal-1');
  });

  testWidgets('Goals 页面完整支持创建、编辑、状态和确认删除', (tester) async {
    final goals = _MemoryGoalsRepository();
    await tester.binding.setSurfaceSize(const Size(850, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectGoalsView(
          repository: DemoRepository(),
          goalsRepository: goals,
          project: const Project(id: 'project-1', name: 'Release'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Existing goal'), findsOneWidget);
    await tester.tap(find.text('新建目标'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('project-goal-title')), 'New goal');
    await tester.enterText(
        find.byKey(const ValueKey('project-goal-description')), 'Acceptance');
    await tester.enterText(
        find.byKey(const ValueKey('project-goal-due-date')), '2026-09-12');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('project-goal-goal-2'));
    expect(card, findsOneWidget);
    expect(goals.values.last.title, 'New goal');

    await tester
        .tap(find.descendant(of: card, matching: find.byTooltip('更新目标状态')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已完成').last);
    await tester.pumpAndSettle();
    expect(goals.values.last.status, 'done');

    await tester
        .tap(find.descendant(of: card, matching: find.byTooltip('目标操作')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑目标'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('project-goal-title')), 'Updated goal');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(goals.values.last.title, 'Updated goal');

    await tester
        .tap(find.descendant(of: card, matching: find.byTooltip('目标操作')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除目标'));
    await tester.pumpAndSettle();
    expect(find.text('删除目标？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('Updated goal'), findsNothing);
    expect(goals.deletedIds, ['goal-2']);
  });
}

Map<String, dynamic> _taskJson({
  String title = 'Ship',
  String status = 'todo',
  List<String> labels = const [projectGoalTaskLabel],
}) =>
    {
      'id': 'goal-1',
      'project_id': 'project-1',
      'title': title,
      'description': '',
      'status': status,
      'priority': 2,
      'start_date': null,
      'due_date': null,
      'labels': labels,
      'assignee': null,
    };

http.Response _response(Object body, {int statusCode = 200}) =>
    http.Response(jsonEncode(body), statusCode,
        headers: {'content-type': 'application/json'});

class _MemoryGoalsRepository extends ProjectGoalsRepository {
  _MemoryGoalsRepository() : super(DemoRepository());

  final values = <ProjectGoal>[
    const ProjectGoal(
        id: 'goal-1',
        projectId: 'project-1',
        title: 'Existing goal',
        status: 'todo',
        priority: 2),
  ];
  final deletedIds = <String>[];

  @override
  Future<List<ProjectGoal>> list(String projectId) async => List.of(values);

  @override
  Future<ProjectGoal> create(String projectId, ProjectGoalInput input) async {
    final goal = _fromInput('goal-2', projectId, input);
    values.add(goal);
    return goal;
  }

  @override
  Future<ProjectGoal> update(ProjectGoal goal, ProjectGoalInput input) async {
    final updated = _fromInput(goal.id, goal.projectId, input);
    values[values.indexWhere((item) => item.id == goal.id)] = updated;
    return updated;
  }

  @override
  Future<ProjectGoal> updateStatus(ProjectGoal goal, String status) async {
    final updated = ProjectGoal(
        id: goal.id,
        projectId: goal.projectId,
        title: goal.title,
        description: goal.description,
        status: status,
        priority: goal.priority,
        startDate: goal.startDate,
        dueDate: goal.dueDate,
        labels: goal.labels);
    values[values.indexWhere((item) => item.id == goal.id)] = updated;
    return updated;
  }

  @override
  Future<void> delete(ProjectGoal goal) async {
    deletedIds.add(goal.id);
    values.removeWhere((item) => item.id == goal.id);
  }

  ProjectGoal _fromInput(String id, String projectId, ProjectGoalInput input) =>
      ProjectGoal(
          id: id,
          projectId: projectId,
          title: input.title,
          description: input.description,
          status: input.status,
          priority: input.priority,
          startDate: input.startDate,
          dueDate: input.dueDate,
          labels: input.labels);
}
