import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/utils/display_id.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/notifications/data/models/personnel_notice.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/tasks/data/models/maintenance_task.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/data/repositories/work_order_repository.dart';

import '../../../../core/data/firestore_records.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../notifications/data/repositories/notification_writes.dart';
import '../../../reporting/data/repositories/status_history_writes.dart';
import 'work_order_moves.dart';

/// Firestore-backed [WorkOrderRepository]. Persistence only.
/// Objective 1 moved this data to Supabase; the app uses [WorkOrderRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreWorkOrderRepository extends FirestoreRepository
    implements WorkOrderRepository {
  const FirestoreWorkOrderRepository({required super.db, required super.guard});

  static const String _path = FirestorePaths.workOrders;

  @override
  Future<Result<WorkOrder>> getById(String id) =>
      getOne(path: _path, id: id, convert: fromDoc(WorkOrder.fromRecord));

  @override
  Stream<Result<WorkOrder>> watchById(String id) =>
      watchOne(path: _path, id: id, convert: fromDoc(WorkOrder.fromRecord));

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
      convert: fromDoc(WorkOrder.fromRecord),
    );
  }

  @override
  Stream<Result<List<WorkOrder>>> watchByAssignee(String personnelId) =>
      // Sorted here rather than by the query: one technician's work orders
      // are few, and an orderBy beside array-contains would need its own
      // composite index deployed to the live project.
      watchMany(
        query: collection(_path)
            .where('assignedPersonnelIds', arrayContains: personnelId),
        convert: fromDoc(WorkOrder.fromRecord),
      ).map(
        (result) => result.map(
          (orders) =>
              [...orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        ),
      );

  @override
  Future<Result<String>> create(WorkOrder workOrder) =>
      add(path: _path, data: workOrder.toFields().forFirestore);

  @override
  Future<Result<void>> update(WorkOrder workOrder) => updateDoc(
    path: _path,
    id: workOrder.id,
    data: {
      ...workOrder.toFields().forFirestore,
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

    final report = fromDoc(DamageReport.fromRecord)(reportSnapshot);
    final person = fromDoc(AppUser.fromRecord)(personSnapshot);

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
    final priority = report.officialPriority;
    if (priority == null) {
      // §1.5: the administrator confirms or modifies the official priority
      // "before work-order assignment" (Objective 4.C). The work order
      // carries it, so it cannot be guessed from the requestor's urgency.
      throw _precondition(
        "This report's official priority has not been confirmed yet. "
        'Confirm it on the report page before assigning the work.',
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
    final taskReference = collection(FirestorePaths.tasks).doc();
    final now = DateTime.now().toUtc();

    // Built through the model so its validation and field names stay the
    // single definition, then stamped with server time.
    final workOrder = WorkOrder(
      id: workOrderReference.id,
      reportIds: [reportId],
      title: report.title,
      description: report.description,
      category: category,
      priority: priority,
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
        ...workOrder.toFields().forFirestore,
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
      })
      // Every work order starts with one task, the job itself, so the
      // technician's daily list is never empty of work they hold
      // (Objective 5.A, Chris's decision). Due on the target date, or the
      // day it is assigned.
      ..set(taskReference, {
        ...MaintenanceTask(
          id: taskReference.id,
          workOrderId: workOrderReference.id,
          title: report.title,
          description: report.locationDescription ?? report.facilityName,
          assignedTo: personnelId,
          status: TaskStatus.pending,
          dueDate: (scheduledFor ?? now).toUtc(),
          createdAt: now,
          updatedAt: now,
        ).toFields().forFirestore,
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });

    stagePersonnelNotice(
      transaction,
      db.raw,
      recipientId: personnelId,
      workOrderId: workOrderReference.id,
      notice: PersonnelNotice.workOrderAssigned(
        workOrderTitle: report.title,
        facilityName: report.facilityName,
      ),
    );

    stageReportMove(
      transaction,
      db.raw,
      reportId: reportId,
      reporterId: report.reporterId,
      reportTitle: report.title,
      to: ReportStatus.assigned,
      from: report.status,
      changedBy: actor.id,
      personnel: person,
    );

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

  /// As `app.reassign_work_order` does it
  /// (supabase/migrations/*_reassign_work_order.sql, Objective 7.A).
  @override
  Future<Result<void>> reassign({
    required String workOrderId,
    required String personnelId,
    required AuditActor actor,
  }) async {
    // Firestore transactions cannot query: the work's unfinished tasks are
    // found first, then read again inside the transaction.
    final open = await collection(FirestorePaths.tasks)
        .where('workOrderId', isEqualTo: workOrderId)
        .get();
    return db.runTransaction<void>((transaction) async {
      final reference = collection(_path).doc(workOrderId);
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw _notFound('No work order $workOrderId');
      final personSnapshot = await transaction.get(
        collection(FirestorePaths.users).doc(personnelId),
      );
      if (!personSnapshot.exists) throw _notFound('No user $personnelId');

      final workOrder = fromDoc(WorkOrder.fromRecord)(snapshot);
      final person = fromDoc(AppUser.fromRecord)(personSnapshot);
      if (workOrder.status != WorkOrderStatus.pending &&
          workOrder.status != WorkOrderStatus.inProgress) {
        throw _precondition(
          'This work order is ${workOrder.status.title}. Only work that is '
          'pending or in progress can be reassigned.',
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
      final previous = workOrder.assignedPersonnelIds;
      if (previous.length == 1 && previous.single == personnelId) {
        throw _precondition('${person.fullName} already has this work order.');
      }

      final formers = <AppUser>[];
      for (final id in previous) {
        if (id == personnelId) continue;
        final former = await transaction.get(
          collection(FirestorePaths.users).doc(id),
        );
        if (former.exists) formers.add(fromDoc(AppUser.fromRecord)(former));
      }
      final reports = <DamageReport>[];
      for (final id in workOrder.reportIds) {
        final report = await transaction.get(
          collection(FirestorePaths.damageReports).doc(id),
        );
        if (report.exists) {
          reports.add(fromDoc(DamageReport.fromRecord)(report));
        }
      }
      final tasks = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final task in open.docs) {
        tasks.add(await transaction.get(task.reference));
      }

      for (final former in formers) {
        transaction.update(collection(FirestorePaths.users).doc(former.id), {
          'activeTaskCount': former.activeTaskCount > 0
              ? former.activeTaskCount - 1
              : 0,
          'updatedAt': FirestoreRepository.serverNow,
        });
      }
      if (!previous.contains(personnelId)) {
        transaction.update(collection(FirestorePaths.users).doc(personnelId), {
          'activeTaskCount': FieldValue.increment(1),
          'updatedAt': FirestoreRepository.serverNow,
        });
      }
      transaction.update(reference, {
        'assignedPersonnelIds': [personnelId],
        'updatedAt': FirestoreRepository.serverNow,
      });
      for (final task in tasks) {
        final data = task.data() ?? const <String, dynamic>{};
        if (data['status'] == TaskStatus.completed.id ||
            data['assignedTo'] == personnelId) {
          continue;
        }
        transaction.update(task.reference, {
          'assignedTo': personnelId,
          'updatedAt': FirestoreRepository.serverNow,
        });
      }

      for (final report in reports) {
        stageStatusChange(
          transaction,
          db.raw,
          reportId: report.id,
          status: report.status,
          changedBy: actor.id,
          note: 'Reassigned to ${person.fullName}.',
          personnel: person,
        );
        stageNotification(
          transaction,
          db.raw,
          recipientId: report.reporterId,
          type: NotificationType.statusUpdate,
          title: 'New technician assigned',
          body: 'Your report "${report.title}" is now with ${person.fullName}.',
          relatedEntityType: FirestorePaths.damageReports,
          relatedEntityId: report.id,
        );
      }
      stagePersonnelNotice(
        transaction,
        db.raw,
        recipientId: personnelId,
        workOrderId: workOrderId,
        notice: PersonnelNotice.workOrderAssigned(
          workOrderTitle: workOrder.title,
          facilityName: workOrder.facilityName,
        ),
      );
      for (final former in formers) {
        stageNotification(
          transaction,
          db.raw,
          recipientId: former.id,
          type: NotificationType.statusUpdate,
          title: 'Work reassigned',
          body:
              '${DisplayId.workOrder(workOrderId)} ("${workOrder.title}") was '
              'reassigned to ${person.fullName}. It is off your list.',
          relatedEntityType: FirestorePaths.workOrders,
          relatedEntityId: workOrderId,
        );
      }

      final formerNames = [for (final former in formers) former.fullName]
        ..sort();
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.assigned,
        entityType: FirestorePaths.workOrders,
        entityId: workOrderId,
        description:
            'Reassigned to ${person.fullName}'
            '${formerNames.isEmpty ? '' : ' (was ${formerNames.join(', ')})'}',
        changes: {
          'from': previous,
          'to': [personnelId],
        },
      );
    });
  }

  /// Any legal move. The database refuses For Review, Completed and
  /// sending work back here (Objective 7.B,
  /// supabase/migrations/*_work_order_signoff.sql, proven by its pgTAP
  /// tests); this in-memory stand-in still makes them, so the lifecycle
  /// tests can drive work through every state without accomplishment
  /// reports.
  @override
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status, {
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final snapshot = await transaction.get(collection(_path).doc(workOrderId));
    if (!snapshot.exists) throw _notFound('No work order $workOrderId');

    final workOrder = fromDoc(WorkOrder.fromRecord)(snapshot);
    if (workOrder.status == status) return;

    final move = await WorkOrderMove.prepare(
      transaction,
      db.raw,
      workOrder: workOrder,
      to: status,
    );
    move.stage(transaction, db.raw, actor: actor);
  });

  @override
  Future<Result<void>> updateAdminNotes({
    required String workOrderId,
    required String? notes,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(workOrderId);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw _notFound('No work order $workOrderId');

    final trimmed = notes?.trim();
    final note = trimmed == null || trimmed.isEmpty ? null : trimmed;
    transaction.update(reference, {
      'adminNotes': note,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.updated,
      entityType: FirestorePaths.workOrders,
      entityId: workOrderId,
      description: note == null
          ? 'Note to the technician removed'
          : 'Note to the technician: "${note.length > 80 ? '${note.substring(0, 80)}…' : note}"',
      changes: {'adminNotes': note},
    );
  });

  /// As set_work_order_archived: only a completed work order is archived.
  @override
  Future<Result<void>> setArchived({
    required String workOrderId,
    required bool archived,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(workOrderId);
    final snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw _notFound('No work order $workOrderId');
    final order = fromDoc(WorkOrder.fromRecord)(snapshot);
    if (order.isArchived == archived) return;
    final label = DisplayId.workOrder(workOrderId);
    if (archived && order.status != WorkOrderStatus.completed) {
      throw FirestoreRepository.precondition(
        '$label is ${order.status.title}. Only a completed work order can be '
        'archived.',
      );
    }
    transaction.update(reference, {
      'archivedAt': archived ? FirestoreRepository.serverNow : null,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.updated,
      entityType: FirestorePaths.workOrders,
      entityId: workOrderId,
      description: archived
          ? 'Archived work order $label'
          : 'Restored work order $label from the archive',
      changes: {
        'archived': {'from': !archived, 'to': archived},
      },
    );
  });

  /// The report status that corresponds to each Kanban column.
  static ReportStatus reportStatusFor(WorkOrderStatus status) =>
      WorkOrderMove.reportStatusFor(status);

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
}
