import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';

void main() {
  group('WorkOrderStatus transitions', () {
    test('follows the Kanban column order', () {
      expect(
        WorkOrderStatus.pending.canTransitionTo(WorkOrderStatus.inProgress),
        isTrue,
      );
      expect(
        WorkOrderStatus.inProgress.canTransitionTo(WorkOrderStatus.forReview),
        isTrue,
      );
      expect(
        WorkOrderStatus.forReview.canTransitionTo(WorkOrderStatus.completed),
        isTrue,
      );
    });

    test('forReview allows a rework loop back to inProgress', () {
      expect(
        WorkOrderStatus.forReview.canTransitionTo(WorkOrderStatus.inProgress),
        isTrue,
      );
    });

    test('cannot jump straight from pending to completed', () {
      expect(
        WorkOrderStatus.pending.canTransitionTo(WorkOrderStatus.completed),
        isFalse,
      );
    });

    test('completed is terminal', () {
      expect(WorkOrderStatus.completed.isTerminal, isTrue);
      for (final other in WorkOrderStatus.values) {
        expect(WorkOrderStatus.completed.canTransitionTo(other), isFalse);
      }
    });

    test('id round-trips through fromId', () {
      for (final status in WorkOrderStatus.values) {
        expect(WorkOrderStatus.fromId(status.id), status);
      }
    });
  });
}
