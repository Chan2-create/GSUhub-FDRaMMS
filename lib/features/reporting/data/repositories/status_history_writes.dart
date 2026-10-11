import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/report_status.dart';
import '../../../notifications/data/models/report_notice.dart';
import '../../../notifications/data/repositories/notification_writes.dart';
import '../../../user_management/data/models/app_user.dart';
import '../models/status_change.dart';

/// Stages everything a report's move writes beside the report itself
/// (Objective 3.B): its status history entry and, for the moves the
/// requestor hears about, their notification. Every repository method
/// that moves a report calls this, so neither can be forgotten.
///
/// [reporterId] and [reportTitle] address and word the notice; [from] is
/// the status the report is leaving; [note], [personnel] and [mergedInto]
/// carry what the timeline and the notice say about the move.
void stageReportMove(
  Transaction transaction,
  FirebaseFirestore firestore, {
  required String reportId,
  required String reporterId,
  required String reportTitle,
  required ReportStatus to,
  required String changedBy,
  ReportStatus? from,
  String? note,
  AppUser? personnel,
  String? mergedInto,
}) {
  stageStatusChange(
    transaction,
    firestore,
    reportId: reportId,
    status: to,
    changedBy: changedBy,
    note: note,
    personnel: personnel,
  );

  final notice = ReportNotice.forMove(
    to: to,
    reportTitle: reportTitle,
    from: from,
    personnelName: personnel?.fullName,
    reason: note,
    mergedInto: mergedInto,
  );
  if (notice != null) {
    stageReportNotice(
      transaction,
      firestore,
      recipientId: reporterId,
      reportId: reportId,
      notice: notice,
    );
  }
}

/// Stages an entry of a report's status history inside the transaction
/// that changes its status (Objective 3.B).
///
/// Reached through [stageReportMove], beside the report's own update, so
/// the requestor's timeline gains an entry exactly when the status
/// changes — never for a move that failed, and never missing one that
/// succeeded. The entry is built through [StatusChange] so its field
/// names stay the single definition, then stamped with server time.
///
/// [personnel] is given for `assigned`, so the timeline can name who will
/// do the work.
void stageStatusChange(
  Transaction transaction,
  FirebaseFirestore firestore, {
  required String reportId,
  required ReportStatus status,
  required String changedBy,
  String? note,
  AppUser? personnel,
}) {
  final entry = StatusChange(
    id: 'pending',
    status: status,
    changedAt: DateTime.now().toUtc(),
    changedBy: changedBy,
    note: note,
    personnelName: personnel?.fullName,
    personnelSpecialization: personnel?.specialization,
  );

  transaction.set(
    firestore
        .collection(FirestorePaths.damageReports)
        .doc(reportId)
        .collection(FirestorePaths.statusHistory)
        .doc(),
    {...entry.toFirestore(), 'changedAt': FirestoreRepository.serverNow},
  );
}
