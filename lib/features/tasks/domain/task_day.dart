import '../../../core/enums/task_status.dart';
import '../data/models/maintenance_task.dart';

/// Which of a technician's tasks belong to their day (Objective 5.A,
/// Figure 24). Pure, so the rule is tested on its own.
///
/// DERIVED: the frame shows "Today's To-Do" with open and finished tasks
/// together, and the manuscript speaks of "daily task lists". A day's list
/// is what is due by today and not done — overdue work does not drop off —
/// and what was done today, so the day's progress shows. A task with no
/// due date is always due. Tasks of a work order that is no longer open
/// (submitted or signed off) are left out: nothing more can be done on
/// them.
abstract final class TaskDay {
  /// Today's to-do, at [now], among [tasks] of the open work orders
  /// [openWorkOrderIds]: open ones first, soonest due first, then the
  /// ones done today.
  static List<MaintenanceTask> today(
    Iterable<MaintenanceTask> tasks, {
    required Set<String> openWorkOrderIds,
    required DateTime now,
  }) {
    final open = <MaintenanceTask>[];
    final done = <MaintenanceTask>[];
    for (final task in tasks) {
      if (task.status == TaskStatus.completed) {
        final at = task.completedAt;
        if (at != null && isSameDay(at, now)) done.add(task);
        continue;
      }
      if (!openWorkOrderIds.contains(task.workOrderId)) continue;
      if (isDueBy(task, now)) open.add(task);
    }
    return [...open, ...done];
  }

  /// Open tasks of open work orders that fall due after today.
  static List<MaintenanceTask> upcoming(
    Iterable<MaintenanceTask> tasks, {
    required Set<String> openWorkOrderIds,
    required DateTime now,
  }) => [
    for (final task in tasks)
      if (task.status != TaskStatus.completed &&
          openWorkOrderIds.contains(task.workOrderId) &&
          !isDueBy(task, now))
        task,
  ];

  /// Due today or earlier — or undated, which is always due.
  static bool isDueBy(MaintenanceTask task, DateTime now) {
    final due = task.dueDate;
    if (due == null) return true;
    final local = due.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    return !DateTime(local.year, local.month, local.day).isAfter(today);
  }

  /// Due before today, and not done.
  static bool isOverdue(MaintenanceTask task, DateTime now) {
    final due = task.dueDate;
    if (due == null || task.status == TaskStatus.completed) return false;
    final local = due.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day,
    ).isBefore(DateTime(now.year, now.month, now.day));
  }

  static bool isSameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}
