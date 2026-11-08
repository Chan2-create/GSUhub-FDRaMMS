import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/widgets/confirm_delete_dialog.dart';
import '../../data/models/damage_report.dart';
import '../report_review_controller.dart';

/// Reports are archived, never deleted (Chris, 2026-11-08): the console's
/// "delete" for a report takes it out of the lists and keeps everything.

/// The statuses a report can be archived in: it is finished.
const Set<ReportStatus> archivableReportStatuses = {
  ReportStatus.closed,
  ReportStatus.merged,
  ReportStatus.rejected,
  ReportStatus.archived,
};

extension ReportArchiving on DamageReport {
  bool get canBeArchived =>
      !isArchived && archivableReportStatuses.contains(status);
}

/// Asks before archiving [report], or restoring it, and does it. True once
/// done. One not yet finished is refused by the database, and says why.
Future<bool> confirmReportArchive(BuildContext context, DamageReport report) {
  final controller = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(reportReviewControllerProvider);
  final label = DisplayId.report(report.id);
  final restoring = report.isArchived;
  return showConfirmDeleteDialog(
    context: context,
    title: restoring ? 'Restore report $label?' : 'Archive report $label?',
    message: restoring
        ? '“${report.title}” goes back into the Damage Reports list.'
        : '“${report.title}” leaves the Damage Reports list and goes to the '
              'archive (the Archived filter). Nothing is deleted: its status, '
              'timeline and audit trail stay, the requestor still sees it, '
              'and it can be restored.',
    doneMessage: restoring
        ? 'Restored report $label.'
        : 'Archived report $label.',
    confirmLabel: restoring ? 'Restore' : 'Archive',
    busyLabel: restoring ? 'Restoring…' : 'Archiving…',
    destructive: !restoring,
    onConfirm: () => controller.setArchived(report.id, archived: !restoring),
  );
}
