import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../../../../core/data/firestore_repository.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../reporting/data/repositories/status_history_writes.dart';

/// A work order's move to another status, with every report it carries
/// moving beside it — prepared in a transaction's read phase, staged in
/// its write phase.
///
/// The administrator's Kanban moves (2.B), a technician starting work and
/// submitting it (5.B), and the administrator's sign-off all move a work
/// order, inside transactions that write other things too. Firestore
/// wants every read before any write, so the move is split in two:
/// [prepare] reads and checks, [stage] writes.
class WorkOrderMove {
  WorkOrderMove._({
    required this.workOrder,
    required this.to,
    required this.reportTarget,
    required this.reportsToMove,
    required this.releasedCounts,
  });

  /// The work order as it was read.
  final WorkOrder workOrder;

  final WorkOrderStatus to;

  /// Where its reports go.
  final ReportStatus reportTarget;

  /// The reports that move with it.
  final List<DamageReport> reportsToMove;

  /// On completion, each assignee's open-work count after the release.
  final Map<DocumentReference<Map<String, dynamic>>, int> releasedCounts;

  /// The report status that corresponds to each work-order status. The two
  /// lifecycles share their later stages, so the mapping is one-to-one.
  static ReportStatus reportStatusFor(WorkOrderStatus status) =>
      switch (status) {
        WorkOrderStatus.pending => ReportStatus.assigned,
        WorkOrderStatus.inProgress => ReportStatus.inProgress,
        WorkOrderStatus.forReview => ReportStatus.forReview,
        WorkOrderStatus.completed => ReportStatus.completed,
      };

  /// Reads what moving [workOrder] to [to] touches: its reports, and on
  /// completion its assignees' open-work counts.
  ///
  /// Checks the move against the current status read in the transaction,
  /// never the caller's copy: the enum's transition table (1.B) is the one
  /// definition of what is legal, and enforcing it only in a screen would
  /// let a stale page push a work order backwards.
  static Future<WorkOrderMove> prepare(
    Transaction transaction,
    FirebaseFirestore firestore, {
    required WorkOrder workOrder,
    required WorkOrderStatus to,
  }) async {
    final current = workOrder.status;
    if (!current.canTransitionTo(to)) {
      throw FirestoreRepository.precondition(
        'A work order cannot move from ${current.title} to ${to.title}.',
      );
    }

    final reportTarget = reportStatusFor(to);
    final reportsToMove = <DamageReport>[];
    for (final reportId in workOrder.reportIds) {
      final snapshot = await transaction.get(
        firestore.collection(FirestorePaths.damageReports).doc(reportId),
      );
      if (!snapshot.exists) continue;
      final linked = DamageReport.fromFirestore(snapshot);
      if (linked.status == reportTarget) continue;
      if (!linked.status.canTransitionTo(reportTarget)) {
        // The report and its work order disagree about where the job is.
        // Moving one without the other would make that worse, so refuse.
        throw FirestoreRepository.precondition(
          'Report ${snapshot.id} is ${linked.status.label} and cannot move '
          'to ${reportTarget.label} with this work order.',
        );
      }
      reportsToMove.add(linked);
    }

    // Completed is terminal, so the job stops counting against whoever did
    // it — without this the count only ever rises. Clamped at zero:
    // AppUser rejects a negative count, so one bad decrement would break
    // every screen that lists that person.
    final releasedCounts = <DocumentReference<Map<String, dynamic>>, int>{};
    if (to == WorkOrderStatus.completed) {
      for (final personnelId in workOrder.assignedPersonnelIds) {
        final personReference = firestore
            .collection(FirestorePaths.users)
            .doc(personnelId);
        final personSnapshot = await transaction.get(personReference);
        if (!personSnapshot.exists) continue;
        final count =
            (personSnapshot.data()?['activeTaskCount'] as num?)?.toInt() ?? 0;
        releasedCounts[personReference] = count > 0 ? count - 1 : 0;
      }
    }

    return WorkOrderMove._(
      workOrder: workOrder,
      to: to,
      reportTarget: reportTarget,
      reportsToMove: reportsToMove,
      releasedCounts: releasedCounts,
    );
  }

  /// Writes the move: the work order, its reports with their timeline
  /// entries and requestor notices, the released counts, and the audit
  /// entry, which names [actor].
  void stage(
    Transaction transaction,
    FirebaseFirestore firestore, {
    required AuditActor actor,
  }) {
    final from = workOrder.status;
    transaction.update(
      firestore.collection(FirestorePaths.workOrders).doc(workOrder.id),
      {
        'status': to.id,
        'updatedAt': FirestoreRepository.serverNow,
        if (to == WorkOrderStatus.inProgress && workOrder.startedAt == null)
          'startedAt': FirestoreRepository.serverNow,
        if (to == WorkOrderStatus.completed)
          'completedAt': FirestoreRepository.serverNow,
      },
    );

    for (final linked in reportsToMove) {
      transaction.update(
        firestore.collection(FirestorePaths.damageReports).doc(linked.id),
        {'status': reportTarget.id, 'updatedAt': FirestoreRepository.serverNow},
      );
      stageReportMove(
        transaction,
        firestore,
        reportId: linked.id,
        reporterId: linked.reporterId,
        reportTitle: linked.title,
        to: reportTarget,
        from: linked.status,
        changedBy: actor.id,
      );
    }

    releasedCounts.forEach((personReference, remaining) {
      transaction.update(personReference, {
        'activeTaskCount': remaining,
        'updatedAt': FirestoreRepository.serverNow,
      });
    });

    stageAuditEntry(
      transaction,
      firestore,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: FirestorePaths.workOrders,
      entityId: workOrder.id,
      description: 'Status changed from ${from.title} to ${to.title}',
      changes: {'from': from.id, 'to': to.id},
    );
  }
}
