import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/display_id.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/notifications/data/models/personnel_notice.dart';
import 'package:gsuhub/features/tasks/data/models/maintenance_task.dart';
import 'package:gsuhub/features/tasks/data/repositories/task_repository.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../../../../core/data/firestore_repository.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../notifications/data/repositories/notification_writes.dart';
import '../../../work_orders/data/repositories/work_order_moves.dart';

/// Firestore-backed [TaskRepository] (Objective 5.A).
///
/// Every write reads the task's work order in the same transaction: tasks
/// only change while the work is open, and the first one a technician
/// touches starts the work order, its reports and the requestor's
/// timeline with it.
/// Objective 1 moved this data to Supabase; the app uses [TaskRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreTaskRepository extends FirestoreRepository
    implements TaskRepository {
  const FirestoreTaskRepository({required super.db, required super.guard});

  static const String _path = FirestorePaths.tasks;

  /// Longest task title and description accepted.
  static const int titleLimit = 120;
  static const int descriptionLimit = 500;

  /// Soonest due first; tasks with no due date last; then oldest first.
  static List<MaintenanceTask> sorted(List<MaintenanceTask> tasks) =>
      [...tasks]..sort((a, b) {
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad != null && bd != null) {
          final byDue = ad.compareTo(bd);
          if (byDue != 0) return byDue;
        } else if (ad != null) {
          return -1;
        } else if (bd != null) {
          return 1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });

  @override
  Future<Result<MaintenanceTask>> getById(String id) =>
      getOne(path: _path, id: id, convert: MaintenanceTask.fromFirestore);

  // Both lists are sorted here rather than by the query: they are short,
  // and an orderBy would need a composite index on the live project.
  @override
  Stream<Result<List<MaintenanceTask>>> watchByWorkOrder(String workOrderId) =>
      watchMany(
        query: collection(_path).where('workOrderId', isEqualTo: workOrderId),
        convert: MaintenanceTask.fromFirestore,
      ).map((result) => result.map(sorted));

  @override
  Stream<Result<List<MaintenanceTask>>> watchByAssignee(String personnelId) =>
      watchMany(
        query: collection(_path).where('assignedTo', isEqualTo: personnelId),
        convert: MaintenanceTask.fromFirestore,
      ).map((result) => result.map(sorted));

  @override
  Future<Result<String>> addTask({
    required String workOrderId,
    required String title,
    required AuditActor actor,
    String? description,
    DateTime? dueDate,
  }) async {
    final name = title.trim();
    final details = description?.trim();
    if (name.isEmpty) {
      return const Result.failure(ValidationFailure('Give the task a title.'));
    }
    if (name.length > titleLimit) {
      return const Result.failure(
        ValidationFailure('Keep the title to $titleLimit characters.'),
      );
    }
    if (details != null && details.length > descriptionLimit) {
      return const Result.failure(
        ValidationFailure(
          'Keep the description to $descriptionLimit characters.',
        ),
      );
    }

    return db.runTransaction<String>((transaction) async {
      final workOrder = await _readWorkOrder(transaction, workOrderId);
      if (!_isOpen(workOrder.status)) {
        throw FirestoreRepository.precondition(
          'This work order is ${workOrder.status.title}, so no task can be '
          'added to it.',
        );
      }
      if (workOrder.assignedPersonnelIds.isEmpty) {
        throw FirestoreRepository.precondition(
          'Nobody is assigned to this work order yet.',
        );
      }

      final assignee = workOrder.assignedPersonnelIds.first;
      final reference = collection(_path).doc();
      final now = DateTime.now().toUtc();
      transaction.set(reference, {
        ...MaintenanceTask(
          id: reference.id,
          workOrderId: workOrderId,
          title: name,
          description: details == null || details.isEmpty ? null : details,
          assignedTo: assignee,
          status: TaskStatus.pending,
          dueDate: dueDate?.toUtc(),
          createdAt: now,
          updatedAt: now,
        ).toFirestore(),
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });

      stagePersonnelNotice(
        transaction,
        db.raw,
        recipientId: assignee,
        workOrderId: workOrderId,
        notice: PersonnelNotice.taskAssigned(
          taskTitle: name,
          workOrderTitle: workOrder.title,
        ),
      );
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _path,
        entityId: reference.id,
        description:
            'Task "$name" added to ${DisplayId.workOrder(workOrderId)}',
        changes: {
          'workOrderId': workOrderId,
          'assignedTo': assignee,
          if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
        },
      );
      return reference.id;
    });
  }

  @override
  Future<Result<void>> deleteTask({
    required String taskId,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final reference = collection(_path).doc(taskId);
    final task = await _readTask(transaction, taskId);
    if (task.status == TaskStatus.completed) {
      throw FirestoreRepository.precondition(
        'A task that is done stays on the record.',
      );
    }

    transaction.delete(reference);
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.deleted,
      entityType: _path,
      entityId: taskId,
      description:
          'Task "${task.title}" removed from '
          '${DisplayId.workOrder(task.workOrderId)}',
      changes: {'workOrderId': task.workOrderId},
    );
  });

  @override
  Future<Result<void>> setStatus({
    required String taskId,
    required TaskStatus status,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final task = await _readTask(transaction, taskId);
    final workOrder = await _readWorkOrder(transaction, task.workOrderId);
    _requireOpen(workOrder);
    if (task.status == status) return;
    final start = await _startIfPending(transaction, workOrder, status);

    transaction.update(collection(_path).doc(taskId), {
      'status': status.id,
      'completedAt': status == TaskStatus.completed
          ? FirestoreRepository.serverNow
          : null,
      'updatedAt': FirestoreRepository.serverNow,
    });
    start?.stage(transaction, db.raw, actor: actor);
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: _path,
      entityId: taskId,
      description:
          'Task "${task.title}" changed from ${task.status.label} to '
          '${status.label}',
      changes: {
        'from': task.status.id,
        'to': status.id,
        'workOrderId': task.workOrderId,
      },
    );
  });

  @override
  Future<Result<void>> addProofPhotos({
    required String taskId,
    required List<String> photoUrls,
    required AuditActor actor,
  }) async {
    if (photoUrls.isEmpty) {
      return const Result.failure(ValidationFailure('Add a photo first.'));
    }
    return db.runTransaction<void>((transaction) async {
      final task = await _readTask(transaction, taskId);
      final workOrder = await _readWorkOrder(transaction, task.workOrderId);
      _requireOpen(workOrder);
      // Proof on a task not yet begun means it is under way.
      final moves = task.status == TaskStatus.pending;
      final start = moves
          ? await _startIfPending(transaction, workOrder, TaskStatus.inProgress)
          : null;

      transaction.update(collection(_path).doc(taskId), {
        'proofPhotoUrls': FieldValue.arrayUnion(photoUrls),
        if (moves) 'status': TaskStatus.inProgress.id,
        'updatedAt': FirestoreRepository.serverNow,
      });
      start?.stage(transaction, db.raw, actor: actor);
    });
  }

  Future<MaintenanceTask> _readTask(Transaction transaction, String id) async {
    final snapshot = await transaction.get(collection(_path).doc(id));
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No task $id');
    }
    return MaintenanceTask.fromFirestore(snapshot);
  }

  Future<WorkOrder> _readWorkOrder(Transaction transaction, String id) async {
    final snapshot = await transaction.get(
      collection(FirestorePaths.workOrders).doc(id),
    );
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No work order $id');
    }
    return WorkOrder.fromFirestore(snapshot);
  }

  static bool _isOpen(WorkOrderStatus status) =>
      status == WorkOrderStatus.pending || status == WorkOrderStatus.inProgress;

  static void _requireOpen(WorkOrder workOrder) {
    if (_isOpen(workOrder.status)) return;
    throw FirestoreRepository.precondition(
      'This work order is ${workOrder.status.title}, so its tasks can no '
      'longer change.',
    );
  }

  /// The move that starts [workOrder] when a task of it is touched while
  /// it is still pending, or null.
  Future<WorkOrderMove?> _startIfPending(
    Transaction transaction,
    WorkOrder workOrder,
    TaskStatus taskStatus,
  ) async {
    if (workOrder.status != WorkOrderStatus.pending ||
        taskStatus == TaskStatus.pending) {
      return null;
    }
    return WorkOrderMove.prepare(
      transaction,
      db.raw,
      workOrder: workOrder,
      to: WorkOrderStatus.inProgress,
    );
  }
}
