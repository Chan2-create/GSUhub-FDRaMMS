import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../data/models/work_order.dart';
import '../work_order_detail_controller.dart';

/// Work orders are archived, never deleted (Chris, 2026-11-08): the
/// console's "delete" for a work order takes it off the board and keeps
/// everything.

extension WorkOrderArchiving on WorkOrder {
  bool get canBeArchived => !isArchived && status == WorkOrderStatus.completed;
}

/// Asks before archiving [workOrder], or restoring it, and does it. True
/// once done. Work not yet completed is refused by the database, and says
/// why.
Future<bool> confirmWorkOrderArchive(
  BuildContext context,
  WorkOrder workOrder,
) {
  final controller = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(workOrderDetailControllerProvider);
  final label = DisplayId.workOrder(workOrder.id);
  final restoring = workOrder.isArchived;
  return showConfirmDeleteDialog(
    context: context,
    title: restoring
        ? 'Restore work order $label?'
        : 'Archive work order $label?',
    message: restoring
        ? '“${workOrder.title}” goes back on the board.'
        : '“${workOrder.title}” leaves the board and goes to the archive (the '
              'Archived filter). Nothing is deleted: its status, tasks, '
              'accomplishment report and audit trail stay, the technician '
              'still sees it, and it can be restored.',
    doneMessage: restoring
        ? 'Restored work order $label.'
        : 'Archived work order $label.',
    confirmLabel: restoring ? 'Restore' : 'Archive',
    busyLabel: restoring ? 'Restoring…' : 'Archiving…',
    destructive: !restoring,
    onConfirm: () => controller.setArchived(workOrder.id, archived: !restoring),
  );
}
