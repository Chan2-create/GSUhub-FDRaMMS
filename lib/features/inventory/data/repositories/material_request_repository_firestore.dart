import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/audit_action.dart';
import '../../../../core/enums/material_request_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/quantity_format.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../notifications/data/models/personnel_notice.dart';
import '../../../notifications/data/repositories/notification_writes.dart';
import '../models/allocated_material.dart';
import '../models/inventory_item.dart';
import '../models/material_line.dart';
import '../models/material_request.dart';
import 'material_allocation_repository_firestore.dart';
import 'material_request_repository.dart';

/// Firestore-backed [MaterialRequestRepository].
/// Objective 1 moved this data to Supabase; the app uses [MaterialRequestRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreMaterialRequestRepository extends FirestoreRepository
    implements MaterialRequestRepository {
  const FirestoreMaterialRequestRepository({
    required super.db,
    required super.guard,
  });

  static const String _requests = FirestorePaths.materialRequests;

  /// The longest note either side may write.
  static const int noteLimit = 300;

  /// The most materials one request may ask for.
  static const int itemLimit = 20;

  @override
  String newRequestId() => collection(_requests).doc().id;

  @override
  Stream<Result<List<MaterialRequest>>> watchForWorkOrder(
    String workOrderId, {
    String? requestedBy,
  }) {
    // Equality filters only, sorted here: no composite index needed.
    Query<Map<String, dynamic>> query = collection(_requests)
        .where('workOrderId', isEqualTo: workOrderId);
    if (requestedBy != null) {
      query = query.where('requestedBy', isEqualTo: requestedBy);
    }
    return watchMany(
      query: query,
      convert: MaterialRequest.fromFirestore,
    ).map((result) => result.map(_newestFirst));
  }

  @override
  Stream<Result<List<MaterialRequest>>> watchRecent({int limit = 50}) =>
      watchMany(
        query: collection(_requests)
            .orderBy('createdAt', descending: true)
            .limit(limit),
        convert: MaterialRequest.fromFirestore,
      );

  static List<MaterialRequest> _newestFirst(List<MaterialRequest> requests) =>
      [...requests]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<Result<void>> submit({
    required String requestId,
    required String workOrderId,
    required List<MaterialLine> items,
    required AuditActor actor,
    String? note,
  }) async {
    final wanted = <String, double>{};
    for (final item in items) {
      wanted.update(
        item.inventoryItemId,
        (total) => total + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    if (wanted.isEmpty) {
      return const Result.failure(
        ValidationFailure('Add the materials you need.'),
      );
    }
    if (wanted.length > itemLimit) {
      return const Result.failure(
        ValidationFailure('Ask for at most $itemLimit materials at a time.'),
      );
    }
    final words = _orNull(note);
    if ((words?.length ?? 0) > noteLimit) {
      return const Result.failure(
        ValidationFailure('Keep the note to $noteLimit characters.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      final requestRef = collection(_requests).doc(requestId);
      // A retry of a request that went through: nothing more to do.
      if ((await transaction.get(requestRef)).exists) return;

      final workOrder =
          await FirestoreMaterialAllocationRepository.readOpenWorkOrder(
            transaction,
            db.raw,
            workOrderId,
          );
      if (!workOrder.assignedPersonnelIds.contains(actor.id)) {
        throw FirestoreRepository.precondition(
          'This work order is not assigned to you.',
        );
      }

      final lines = <MaterialLine>[];
      for (final MapEntry(key: itemId, value: quantity) in wanted.entries) {
        final snapshot = await transaction.get(
          collection(FirestorePaths.inventoryItems).doc(itemId),
        );
        if (!snapshot.exists) {
          throw FirestoreRepository.notFound(
            'A material you picked is no longer in the inventory.',
          );
        }
        final item = InventoryItem.fromFirestore(snapshot);
        lines.add(
          MaterialLine(
            inventoryItemId: itemId,
            itemName: item.name,
            quantity: quantity,
            unitOfMeasurement: item.unitOfMeasurement,
          ),
        );
      }

      transaction.set(requestRef, {
        'workOrderId': workOrderId,
        'requestedBy': actor.id,
        'requestedByName': actor.name,
        'items': [for (final line in lines) line.toMap()],
        'status': MaterialRequestStatus.pending.id,
        'note': words,
        'adminNote': null,
        'reviewedBy': null,
        'reviewedAt': null,
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _requests,
        entityId: requestId,
        description:
            'Requested ${_summary(lines)} for '
            '${DisplayId.workOrder(workOrderId)}',
      );
    });
  }

  @override
  Future<Result<void>> approve({
    required String requestId,
    required AuditActor actor,
    String? note,
  }) async {
    final words = _orNull(note);
    if ((words?.length ?? 0) > noteLimit) {
      return const Result.failure(
        ValidationFailure('Keep the note to $noteLimit characters.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      final request = await _readPending(transaction, requestId);
      final workOrder =
          await FirestoreMaterialAllocationRepository.readOpenWorkOrder(
            transaction,
            db.raw,
            request.workOrderId,
          );
      final allocated =
          FirestoreMaterialAllocationRepository.allocatedMaterials(
            db.raw,
            request.workOrderId,
          );

      // Every read before the first write.
      final items = <String, InventoryItem>{};
      final already = <String, double>{};
      for (final line in request.items) {
        final snapshot = await transaction.get(
          collection(FirestorePaths.inventoryItems).doc(line.inventoryItemId),
        );
        if (!snapshot.exists) {
          throw FirestoreRepository.notFound(
            '${line.itemName} is no longer in the inventory.',
          );
        }
        final item = InventoryItem.fromFirestore(snapshot);
        if (line.quantity > item.quantityAvailable) {
          throw FirestoreRepository.precondition(
            'Only ${QuantityFormat.withUnit(item.quantityAvailable, item.unitOfMeasurement)} '
            'of ${item.name} in stock.',
          );
        }
        items[line.inventoryItemId] = item;
        final current = await transaction.get(
          allocated.doc(line.inventoryItemId),
        );
        already[line.inventoryItemId] = current.exists
            ? AllocatedMaterial.fromFirestore(current).line.quantity
            : 0;
      }

      for (final line in request.items) {
        final item = items[line.inventoryItemId]!;
        transaction.set(
          allocated.doc(line.inventoryItemId),
          AllocatedMaterial(
            line: MaterialLine(
              inventoryItemId: line.inventoryItemId,
              itemName: item.name,
              quantity: already[line.inventoryItemId]! + line.quantity,
              unitOfMeasurement: item.unitOfMeasurement,
            ),
            allocatedBy: actor.id,
            allocatedAt: DateTime.now().toUtc(),
          ).toFirestore()..['allocatedAt'] = FirestoreRepository.serverNow,
        );
      }
      _stageReview(
        transaction,
        request,
        status: MaterialRequestStatus.approved,
        actor: actor,
        note: words,
      );
      stagePersonnelNotice(
        transaction,
        db.raw,
        recipientId: request.requestedBy,
        workOrderId: request.workOrderId,
        notice: PersonnelNotice.materialsApproved(
          requestNumber: DisplayId.materialRequest(requestId),
          workOrderTitle: workOrder.title,
          adminNote: words,
        ),
      );
    });
  }

  @override
  Future<Result<void>> decline({
    required String requestId,
    required AuditActor actor,
    required String note,
  }) async {
    final words = _orNull(note);
    if (words == null) {
      return const Result.failure(
        ValidationFailure('Say why the request is declined.'),
      );
    }
    if (words.length > noteLimit) {
      return const Result.failure(
        ValidationFailure('Keep the note to $noteLimit characters.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      final request = await _readPending(transaction, requestId);
      final workOrderSnapshot = await transaction.get(
        collection(FirestorePaths.workOrders).doc(request.workOrderId),
      );
      final title =
          workOrderSnapshot.data()?['title'] as String? ??
          DisplayId.workOrder(request.workOrderId);

      _stageReview(
        transaction,
        request,
        status: MaterialRequestStatus.declined,
        actor: actor,
        note: words,
      );
      stagePersonnelNotice(
        transaction,
        db.raw,
        recipientId: request.requestedBy,
        workOrderId: request.workOrderId,
        notice: PersonnelNotice.materialsDeclined(
          requestNumber: DisplayId.materialRequest(requestId),
          workOrderTitle: title,
          adminNote: words,
        ),
      );
    });
  }

  Future<MaterialRequest> _readPending(
    Transaction transaction,
    String requestId,
  ) async {
    final snapshot = await transaction.get(
      collection(_requests).doc(requestId),
    );
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No material request $requestId');
    }
    final request = MaterialRequest.fromFirestore(snapshot);
    if (!request.isPending) {
      throw FirestoreRepository.precondition(
        '${DisplayId.materialRequest(requestId)} was already '
        '${request.status.label.toLowerCase()}.',
      );
    }
    return request;
  }

  void _stageReview(
    Transaction transaction,
    MaterialRequest request, {
    required MaterialRequestStatus status,
    required AuditActor actor,
    required String? note,
  }) {
    transaction.update(collection(_requests).doc(request.id), {
      'status': status.id,
      'adminNote': note,
      'reviewedBy': actor.id,
      'reviewedAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: _requests,
      entityId: request.id,
      description:
          '${status == MaterialRequestStatus.approved ? 'Approved' : 'Declined'} '
          '${DisplayId.materialRequest(request.id)} '
          '(${_summary(request.items)}) for '
          '${DisplayId.workOrder(request.workOrderId)}',
      changes: {'status': status.id, 'adminNote': ?note},
    );
  }

  static String _summary(List<MaterialLine> lines) => lines
      .map(
        (line) =>
            '${QuantityFormat.withUnit(line.quantity, line.unitOfMeasurement)} '
            'of ${line.itemName}',
      )
      .join(', ');

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
