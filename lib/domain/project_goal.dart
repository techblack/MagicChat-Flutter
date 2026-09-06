import 'models.dart';

const projectGoalTaskLabel = 'magicchat-goal';
const projectGoalStatuses = <String>{
  'todo',
  'in_progress',
  'done',
  'canceled',
};

class ProjectGoal {
  const ProjectGoal({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.priority,
    this.description = '',
    this.startDate,
    this.dueDate,
    this.labels = const [],
    this.assignee,
    this.reminder,
  });

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

  factory ProjectGoal.fromTask(ProjectTask task) => ProjectGoal(
        id: task.id,
        projectId: task.projectId,
        title: task.title,
        description: task.description,
        status: task.status,
        priority: task.priority,
        startDate: task.startDate,
        dueDate: task.dueDate,
        labels: task.labels
            .where((label) => label != projectGoalTaskLabel)
            .toList(growable: false),
        assignee: task.assignee,
        reminder: task.reminder,
      );
}

class ProjectGoalInput {
  const ProjectGoalInput({
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.startDate,
    required this.dueDate,
    required this.labels,
  });

  final String title;
  final String description;
  final String status;
  final int priority;
  final String? startDate;
  final String? dueDate;
  final List<String> labels;

  factory ProjectGoalInput.fromGoal(ProjectGoal goal) => ProjectGoalInput(
        title: goal.title,
        description: goal.description,
        status: goal.status,
        priority: goal.priority,
        startDate: goal.startDate,
        dueDate: goal.dueDate,
        labels: goal.labels,
      );
}
