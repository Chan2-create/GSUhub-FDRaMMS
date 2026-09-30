import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../reporting/data/models/damage_report.dart';
import '../../../user_management/data/models/app_user.dart';
import '../models/work_order.dart';
import 'work_order_repository.dart';

/// Firestore-backed [WorkOrderRepository]. Persistence only.
class WorkOrderRepositoryImpl extends FirestoreRepository
    implements WorkOrderRepository {
  const WorkOrderRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.workOrders;

  @override
  Future<Result<WorkOrder>> getById(String id) =>
      getOne(path: _path, id: id, convert: WorkOrder.fromFirestore);

  @override
  Stream<Result<WorkOrder>> watchById(String id) =>
      watchOne(path: _path, id: id, convert: WorkOrder.fromFirestore);

  @override
  Stream<Result<List<WorkOrder>>> watchAll({
    WorkOrderStatus? status,
    String? categoryId,
  }) {
    Query<Map<String, dynamic>> query = collection(_path);
    if (status != null) query = query.where('status', isEqualTo: status.id);
    if (categoryId != null) {
      query = query.where('category', isEqualTo: categoryId);
    }
    return watchMany(
      query: query.orderBy('createdAt', descending: true),
      convert: WorkOrder.fromFirestore,
    );
  }

  @override
  Stream<Result<List<WorkOrder>>> watchByAssignee(String personnelId) =>
      watchMany(
        query: collection(_path)
            .where('assignedPersonnelIds', arrayContains: personnelId)
            .orderBy('createdAt', descending: true),
        convert: WorkOrder.fromFirestore,
      );

  @override
  Future<Result<String>> create(WorkOrder workOrder) =>
      add(path: _path, data: workOrder.toFirestore());

  @override
  Future<Result<void>> update(WorkOrder workOrder) => updateDoc(
    path: _path,
    id: workOrder.id,
    data: {
      ...workOrder.toFirestore(),
      'updatedAt': FirestoreRepository.serverNow,
    },
  );

  @override
  Future<Result<String>> assignFromReport({
    required String reportId,
    required String personnelId,
    required AuditActor actor,
    DateTime? scheduledFor,
  }) => db.runTransaction<String>((transaction) async {
    final reportReference = collection(FirestorePaths.damageReports)
        .doc(reportId);
    final personReference = collection(FirestorePaths.users).doc(personnelId);

    // Firestore transactions require every read before any write.
    final reportSnapshot = await transaction.get(reportReference);
    final personSnapshot = await transaction.get(personReference);

    if (!reportSnapshot.exists) throw _notFound('No damage report $reportId');
    if (!personSnapshot.exists) throw _notFound('No user $personnelId');

    final report = DamageReport.fromFirestore(reportSnapshot);
    final person = AppUser.fromFirestore(personSnapshot);

    if (report.status != ReportStatus.approved) {
      throw _precondition(
        'Only approved reports can be assigned. This one is '
        '${report.status.label}.',
      );
    }
    if (report.workOrderId != null) {
      throw _precondition('This report already has a work order.');
    }
    final category = report.category;
    if (category == null) {
      // WorkOrder.category is required, and inventing one would route the
      // job to the wrong trade. Classification is decided before assignment.
      throw _precondition(
        'This report has no damage category yet, so no work order can be '
        'raised for it. It must be classified first.',
      );
    }
    if (person.role != UserRole.maintenancePersonnel) {
      throw _precondition('${person.fullName} is not maintenance personnel.');
    }
    if (person.accountStatus != AccountStatus.active) {
      throw _precondition(
        "${person.fullName}'s account is inactive and cannot take work.",
      );
    }

    final workOrderReference = collection(_path).doc();
    final now = DateTime.now().toUtc();

    // Built through the model so its validation and field names stay the
    // single definition, then stamped with server time.
    final workOrder = WorkOrder(
      id: workOrderReference.id,
      reportIds: [reportId],
      title: report.title,
      description: report.description,
      category: category,
      priority: report.effectivePriority,
      status: WorkOrderStatus.pending,
      assignedPersonnelIds: [personnelId],
      facilityId: report.facilityId,
      facilityName: report.facilityName,
      scheduledFor: scheduledFor?.toUtc(),
      createdBy: actor.id,
      createdAt: now,
      updatedAt: now,
    );

    transaction
      ..set(workOrderReference, {
        ...workOrder.toFirestore(),
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      })
      ..update(reportReference, {
        'status': ReportStatus.assigned.id,
        'workOrderId': workOrderReference.id,
        'updatedAt': FirestoreRepository.serverNow,
      })
      // An atomic increment, not read-modify-write: two administrators
      // assigning to the same person at once must both count.
      ..update(personReference, {
        'activeTaskCount': FieldValue.increment(1),
        'updatedAt': FirestoreRepository.serverNow,
      });

    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.assigned,
      entityType: FirestorePaths.damageReports,
      entityId: reportId,
      description: 'Assigned to ${person.fullName}',
      changes: {
        'from': ReportStatus.approved.id,
        'to': ReportStatus.assigned.id,
        'workOrderId': workOrderReference.id,
        'personnelId': personnelId,
      },
    );
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.created,
      entityType: FirestorePaths.workOrders,
      entityId: workOrderReference.id,
      description: 'Work order created from report $reportId',
      changes: {
        'reportId': reportId,
        'personnelId': personnelId,
        if (scheduledFor != null)
          'scheduledFor': scheduledFor.toUtc().toIso8601String(),
      },
    );

    return workOrderReference.id;
  });

  @override
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status, {
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(workOrderId);
    final snapshot = await transaction.get(reference);

    if (!snapshot.exists) throw _notFound('No work order $workOrderId');

    // Reads the current status inside the transaction and rejects illegal
    // moves, rather than trusting the caller. The enum's transition table
    // (1.B) is the single definition of what is legal; enforcing it only
    // in the UI would let a stale screen or a second admin push a work
    // order backwards through the Kanban board.
    final workOrder = WorkOrder.fromFirestore(snapshot);
    final current = workOrder.status;
    if (current == status) return;

    if (!current.canTransitionTo(status)) {
      throw _precondition(
        'A work order cannot move from ${current.title} to ${status.title}.',
      );
    }

    // Every linked report is read before anything is written.
    final reportTarget = reportStatusFor(status);
    final reportSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final reportId in workOrder.reportIds) {
      reportSnapshots.add(
        await transaction.get(
          collection(FirestorePaths.damageReports).doc(reportId),
        ),
      );
    }

    final reportsToMove = <DocumentReference<Map<String, dynamic>>>[];
    for (final reportSnapshot in reportSnapshots) {
      if (!reportSnapshot.exists) continue;
      final reportStatus = DamageReport.fromFirestore(reportSnapshot).status;
      if (reportStatus == reportTarget) continue;
      if (!reportStatus.canTransitionTo(reportTarget)) {
        // The report and its work order disagree about where the job is.
        // Moving one without the other would make that worse, so refuse.
        throw _precondition(
          'Report ${reportSnapshot.id} is ${reportStatus.label} and cannot '
          'move to ${reportTarget.label} with this work order.',
        );
      }
      reportsToMove.add(reportSnapshot.reference);
    }

    // Completed is terminal, so the job stops counting against whoever did
    // it — without this the count only ever rises. Read here, before any
    // write, and clamped at zero: AppUser rejects a negative count, so one
    // bad decrement would break every screen that lists that person. Inside
    // a transaction this read-modify-write cannot race.
    final releasedCounts = <DocumentReference<Map<String, dynamic>>, int>{};
    if (status == WorkOrderStatus.completed) {
      for (final personnelId in workOrder.assignedPersonnelIds) {
        final personReference = collection(FirestorePaths.users)
            .doc(personnelId);
        final personSnapshot = await transaction.get(personReference);
        if (!personSnapshot.exists) continue;
        final count =
            (personSnapshot.data()?['activeTaskCount'] as num?)?.toInt() ?? 0;
        releasedCounts[personReference] = count > 0 ? count - 1 : 0;
      }
    }

    transaction.update(reference, {
      'status': status.id,
      'updatedAt': FirestoreRepository.serverNow,
      if (status == WorkOrderStatus.inProgress && workOrder.startedAt == null)
        'startedAt': FirestoreRepository.serverNow,
      if (status == WorkOrderStatus.completed)
        'completedAt': FirestoreRepository.serverNow,
    });

    for (final reportReference in reportsToMove) {
      transaction.update(reportReference, {
        'status': reportTarget.id,
        'updatedAt': FirestoreRepository.serverNow,
      });
    }

    releasedCounts.forEach((personReference, remaining) {
      transaction.update(personReference, {
        'activeTaskCount': remaining,
        'updatedAt': FirestoreRepository.serverNow,
      });
    });

    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: FirestorePaths.workOrders,
      entityId: workOrderId,
      description: 'Status changed from ${current.title} to ${status.title}',
      changes: {'from': current.id, 'to': status.id},
    );
  });

  /// The report status that corresponds to each Kanban column. The two
  /// lifecycles share their later stages, so the mapping is one-to-one.
  static ReportStatus reportStatusFor(WorkOrderStatus status) =>
      switch (status) {
        WorkOrderStatus.pending => ReportStatus.assigned,
        WorkOrderStatus.inProgress => ReportStatus.inProgress,
        WorkOrderStatus.forReview => ReportStatus.forReview,
        WorkOrderStatus.completed => ReportStatus.completed,
      };

  static FirebaseException _notFound(String message) => FirebaseException(
    plugin: 'cloud_firestore',
    code: 'not-found',
    message: message,
  );

  /// Mapped by FirebaseErrorMapper to a ValidationFailure carrying
  /// [message], so it reaches the administrator verbatim.
  static FirebaseException _precondition(String message) => FirebaseException(
    plugin: 'gsuhub',
    code: 'failed-precondition',
    message: message,
  );

  @override
  Future<Result<void>> assignPersonnel({
    required String workOrderId,
    required List<String> personnelIds,
    required String assignedBy,
  }) {
    if (personnelIds.isEmpty) {
      return Future.value(
        const Result.failure(
          ValidationFailure('Assign at least one maintenance personnel.'),
        ),
      );
    }

    return updateDoc(
      path: _path,
      id: workOrderId,
      data: {
        'assignedPersonnelIds': personnelIds,
        'updatedAt': FirestoreRepository.serverNow,
      },
    );
  }
}
