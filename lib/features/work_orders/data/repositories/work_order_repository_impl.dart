import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
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
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status,
  ) async {
    // Reads the current status inside a transaction and rejects illegal
    // moves, rather than trusting the caller. The enum's transition table
    // (1.B) is the single definition of what is legal; enforcing it only
    // in the UI would let a stale screen or a second admin push a work
    // order backwards through the Kanban board.
    final result = await db.runTransaction<void>((transaction) async {
      final reference = collection(_path).doc(workOrderId);
      final snapshot = await transaction.get(reference);

      if (!snapshot.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'No work order $workOrderId',
        );
      }

      final current = WorkOrder.fromFirestore(snapshot).status;
      if (current == status) return;

      if (!current.canTransitionTo(status)) {
        throw FirebaseException(
          plugin: 'gsuhub',
          code: 'failed-precondition',
          message:
              'A work order cannot move from ${current.id} to ${status.id}.',
        );
      }

      transaction.update(reference, {
        'status': status.id,
        'updatedAt': FirestoreRepository.serverNow,
        if (status == WorkOrderStatus.inProgress &&
            snapshot.data()?['startedAt'] == null)
          'startedAt': FirestoreRepository.serverNow,
        if (status == WorkOrderStatus.completed)
          'completedAt': FirestoreRepository.serverNow,
      });
    });

    return result;
  }

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
