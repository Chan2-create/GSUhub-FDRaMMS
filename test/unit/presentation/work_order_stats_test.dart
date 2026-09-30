import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/presentation/work_order_providers.dart';

/// The OVERDUE card counts days, not instants: the target completion date
/// comes from a date picker, so it names a day, and a job is late only
/// once that day has ended.
void main() {
  WorkOrder scheduled(
    DateTime? target, {
    WorkOrderStatus status = WorkOrderStatus.pending,
  }) => WorkOrder(
    id: 'wo-1',
    reportIds: const ['rep-1'],
    title: 'Window Gasket',
    description: 'Seeded for test.',
    category: DamageCategory.electrical,
    priority: PriorityLevel.medium,
    status: status,
    assignedPersonnelIds: const ['p1'],
    scheduledFor: target?.toUtc(),
    createdBy: 'admin-1',
    createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    updatedAt: DateTime.now().toUtc(),
  );

  /// Midnight local, which is what `showDatePicker` returns.
  DateTime day(int daysFromToday) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + daysFromToday);
  }

  group('overdue', () {
    test('a job due today is not overdue', () {
      final stats = WorkOrderStats.from([scheduled(day(0))]);

      expect(stats.overdue, 0);
    });

    test('a job due tomorrow is not overdue', () {
      final stats = WorkOrderStats.from([scheduled(day(1))]);

      expect(stats.overdue, 0);
    });

    test('a job due yesterday is overdue', () {
      final stats = WorkOrderStats.from([scheduled(day(-1))]);

      expect(stats.overdue, 1);
    });

    test('a completed job is never overdue', () {
      final stats = WorkOrderStats.from([
        scheduled(day(-5), status: WorkOrderStatus.completed),
      ]);

      expect(stats.overdue, 0);
    });

    test('a job with no target date is never overdue', () {
      final stats = WorkOrderStats.from([scheduled(null)]);

      expect(stats.overdue, 0);
    });
  });
}
