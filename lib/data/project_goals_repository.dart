import '../domain/models.dart';
import '../domain/project_goal.dart';
import 'repository.dart';

/// 独立 Goals API 尚不存在时，使用服务端任务 API 的标签筛选能力承载目标。
/// 这保证目标在其他客户端仍是可见、可编辑的真实项目任务。
class ProjectGoalsRepository {
  const ProjectGoalsRepository(this.repository);

  final MagicChatRepository repository;

  Future<List<ProjectGoal>> list(String projectId) async {
    final goals = <ProjectGoal>[];
    String? cursor;
    do {
      final page = await repository.projectTaskPage(projectId,
          cursor: cursor, limit: 100, label: projectGoalTaskLabel);
      goals.addAll(page.tasks
          .where((task) => task.labels.contains(projectGoalTaskLabel))
          .map(ProjectGoal.fromTask));
      final next = page.nextCursor;
      if (next == null || next.isEmpty || next == cursor) break;
      cursor = next;
    } while (true);
    return goals;
  }

  Future<ProjectGoal> create(String projectId, ProjectGoalInput input) async {
    final task = await repository.createTask(projectId, input.title.trim(),
        description: input.description.trim(),
        status: _status(input.status),
        priority: input.priority,
        startDate: input.startDate,
        dueDate: input.dueDate,
        labels: _labels(input.labels));
    return ProjectGoal.fromTask(task);
  }

  Future<ProjectGoal> update(ProjectGoal goal, ProjectGoalInput input) async {
    final task = await repository.updateTask(
      goal.projectId,
      goal.id,
      ProjectTaskUpdate(
        title: input.title.trim(),
        description: input.description.trim(),
        status: _status(input.status),
        priority: input.priority,
        startDate: input.startDate,
        dueDate: input.dueDate,
        labels: _labels(input.labels),
        assigneeUserId: goal.assigneeUserId,
        reminder: goal.reminder,
      ),
    );
    return ProjectGoal.fromTask(task);
  }

  Future<ProjectGoal> updateStatus(ProjectGoal goal, String status) async =>
      ProjectGoal.fromTask(await repository.updateTaskStatus(
          goal.projectId, goal.id, _status(status)));

  Future<void> delete(ProjectGoal goal) =>
      repository.deleteTask(goal.projectId, goal.id);

  String _status(String value) {
    if (!projectGoalStatuses.contains(value)) {
      throw ArgumentError.value(value, 'status', '不支持的目标状态');
    }
    return value;
  }

  List<String> _labels(Iterable<String> values) => {
        projectGoalTaskLabel,
        ...values.map((value) => value.trim()).where(
            (value) => value.isNotEmpty && value != projectGoalTaskLabel),
      }.toList(growable: false);
}
