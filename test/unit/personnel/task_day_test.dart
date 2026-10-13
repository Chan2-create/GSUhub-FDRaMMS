import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/features/tasks/data/models/maintenance_task.dart';
import 'package:gsuhub/features/tasks/domain/task_day.dart';

/// Which tasks belong to a technician's day (Objective 5.A).
void main() {
  final now = DateTime(2026, 10, 12, 10);

  MaintenanceTask task(
    String id, {
    DateTime? due,
    TaskStatus status = TaskStatus.pending,
    DateTime? completedAt,
    String workOrderId = 'w1',
  }) => MaintenanceTask(
    id: id,
    workOrderId: workOrderId,
    title: 'Task $id',
    assignedTo: 'p1',
    status: status,
    dueDate: due,
    completedAt: completedAt,
    createdAt: DateTime(2026, 10),
    updatedAt: DateTime(2026, 10),
  );

  List<String> today(List<MaintenanceTask> tasks, {Set<String>? open}) => [
    for (final t in TaskDay.today(
      tasks,
      openWorkOrderIds: open ?? {'w1'},
      now: now,
    ))
      t.id,
  ];

  test("today's to-do: due today, overdue and undated, open ones first, "
      'then those done today', () {
    expect(
      today([
        task(
          'done-today',
          status: TaskStatus.completed,
          completedAt: DateTime(2026, 10, 12, 8),
        ),
        task('due-today', due: DateTime(2026, 10, 12, 15)),
        task('overdue', due: DateTime(2026, 10, 10, 12)),
        task('undated'),
        task('tomorrow', due: DateTime(2026, 10, 13, 9)),
        task(
          'done-yesterday',
          status: TaskStatus.completed,
          completedAt: DateTime(2026, 10, 11, 17),
        ),
      ]),
      ['due-today', 'overdue', 'undated', 'done-today'],
    );
  });

  test('leaves out the open tasks of work no longer open', () {
    expect(
      today([
        task('submitted', due: DateTime(2026, 10, 12, 9), workOrderId: 'w2'),
        task('mine', due: DateTime(2026, 10, 12, 9)),
      ]),
      ['mine'],
    );
  });

  test('upcoming: open tasks due after today', () {
    final upcoming = TaskDay.upcoming(
      [
        task('tomorrow', due: DateTime(2026, 10, 13, 9)),
        task('today', due: DateTime(2026, 10, 12, 18)),
        task(
          'done-later',
          due: DateTime(2026, 10, 14),
          status: TaskStatus.completed,
        ),
      ],
      openWorkOrderIds: {'w1'},
      now: now,
    );

    expect(upcoming.map((t) => t.id), ['tomorrow']);
  });

  test('overdue: due before today and not done', () {
    expect(
      TaskDay.isOverdue(task('a', due: DateTime(2026, 10, 11, 23)), now),
      isTrue,
    );
    expect(
      TaskDay.isOverdue(task('b', due: DateTime(2026, 10, 12, 1)), now),
      isFalse,
    );
    expect(TaskDay.isOverdue(task('c'), now), isFalse);
    expect(
      TaskDay.isOverdue(
        task('d', due: DateTime(2026, 10, 2), status: TaskStatus.completed),
        now,
      ),
      isFalse,
    );
  });
}
