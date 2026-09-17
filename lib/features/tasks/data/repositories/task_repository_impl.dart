import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/task_status.dart';
import '../../../../core/utils/result.dart';
import '../models/maintenance_task.dart';
import 'task_repository.dart';

/// Firestore-backed [TaskRepository]. Persistence only.
///
/// Owns the only writes to the denormalized `users.activeTaskCount`, which
/// is why status changes and assignment go through transactions here
/// rather than plain updates — see [setStatus].
class TaskRepositoryImpl extends FirestoreRepository implements TaskRepository {
  const TaskRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.tasks;
  static const String _users = FirestorePaths.users;

  @override
  Future<Result<MaintenanceTask>> getById(String id) =>
      getOne(path: _path, id: id, convert: MaintenanceTask.fromFirestore);

  @override
  Stream<Result<List<MaintenanceTask>>> watchByWorkOrder(String workOrderId) =>
      watchMany(
        query: collection(_path).where('workOrderId', isEqualTo: workOrderId),
        convert: MaintenanceTask.fromFirestore,
      );

  @override
  Stream<Result<List<MaintenanceTask>>> watchByAssignee(
    String personnelId, {
    DateTime? dueOn,
    TaskStatus? status,
  }) {
    Query<Map<String, dynamic>> query = collection(_path)
        .where('assignedTo', isEqualTo: personnelId);

    if (status != null) query = query.where('status', isEqualTo: status.id);

    if (dueOn != null) {
      // Day boundaries computed in UTC to match how models store
      // timestamps (see docs/data_dictionary.md); a local-midnight range
      // would slice the day differently depending on the device.
      final startOfDay = DateTime.utc(dueOn.year, dueOn.month, dueOn.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      query = query
          .where(
            'dueDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('dueDate', isLessThan: Timestamp.fromDate(endOfDay));
    }

    return watchMany(
      query: query.orderBy('dueDate'),
      convert: MaintenanceTask.fromFirestore,
    );
  }

  @override
  Future<Result<String>> create(MaintenanceTask task) =>
      db.runTransaction<String>((transaction) async {
        final reference = collection(_path).doc();
        transaction.set(reference, task.toFirestore());

        // A newly created task that is not already complete adds to its
        // assignee's open-task count.
        if (task.status != TaskStatus.completed) {
          transaction.update(collection(_users).doc(task.assignedTo), {
            'activeTaskCount': FieldValue.increment(1),
            'updatedAt': FirestoreRepository.serverNow,
          });
        }
        return reference.id;
      });

  @override
  Future<Result<void>> update(MaintenanceTask task) => updateDoc(
    path: _path,
    id: task.id,
    data: {...task.toFirestore(), 'updatedAt': FirestoreRepository.serverNow}
      ..remove('status'),
  );

  @override
  Future<Result<void>> setStatus(String taskId, TaskStatus status) =>
      db.runTransaction<void>((transaction) async {
        final reference = collection(_path).doc(taskId);
        final snapshot = await transaction.get(reference);

        if (!snapshot.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'No task $taskId',
          );
        }

        final task = MaintenanceTask.fromFirestore(snapshot);
        if (task.status == status) return;

        // The counter tracks *open* tasks, so only crossing the
        // completed boundary changes it. Doing this in the same
        // transaction as the status write is what keeps the denormalized
        // count honest: a status change that succeeded while the
        // decrement failed would leave a technician permanently showing
        // phantom work in the Admin personnel view (Figure 17).
        final wasOpen = task.status != TaskStatus.completed;
        final isOpen = status != TaskStatus.completed;
        final delta = switch ((wasOpen, isOpen)) {
          (true, false) => -1,
          (false, true) => 1,
          _ => 0,
        };

        transaction.update(reference, {
          'status': status.id,
          'updatedAt': FirestoreRepository.serverNow,
          if (status == TaskStatus.completed)
            'completedAt': FirestoreRepository.serverNow,
        });

        if (delta != 0) {
          transaction.update(collection(_users).doc(task.assignedTo), {
            'activeTaskCount': FieldValue.increment(delta),
            'updatedAt': FirestoreRepository.serverNow,
          });
        }
      });

  @override
  Future<Result<void>> addProofPhotos({
    required String taskId,
    required List<String> photoUrls,
  }) => updateDoc(
    path: _path,
    id: taskId,
    data: {
      'proofPhotoUrls': FieldValue.arrayUnion(photoUrls),
      'updatedAt': FirestoreRepository.serverNow,
    },
  );
}
