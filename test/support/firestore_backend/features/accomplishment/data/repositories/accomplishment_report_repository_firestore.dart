import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/inventory_transaction_type.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/display_id.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/accomplishment/data/models/accomplishment_report.dart';
import 'package:gsuhub/features/accomplishment/data/models/material_usage.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/accomplishment_report_repository.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/notifications/data/models/personnel_notice.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../../../../core/data/firestore_repository.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../notifications/data/repositories/notification_writes.dart';
import '../../../work_orders/data/repositories/work_order_moves.dart';

/// Firestore-backed [AccomplishmentReportRepository].
///
/// [submit] carries the most important invariant in the system: filing a
/// completion report and deducting the materials it consumed happen
/// together or not at all (manuscript §3.4).
/// Objective 1 moved this data to Supabase; the app uses [AccomplishmentReportRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreAccomplishmentReportRepository extends FirestoreRepository
    implements AccomplishmentReportRepository {
  const FirestoreAccomplishmentReportRepository({
    required super.db,
    required super.guard,
  });

  static const String _path = FirestorePaths.accomplishmentReports;
  static const String _items = FirestorePaths.inventoryItems;
  static const String _transactions = FirestorePaths.inventoryTransactions;

  /// The longest completion note accepted.
  static const int notesLimit = 2000;

  /// Photos a report needs: §3.4 has personnel "upload photo evidence of
  /// completed maintenance", and the form takes up to five.
  static const int minPhotos = 1;
  static const int maxPhotos = 5;

  @override
  String newReportId() => collection(_path).doc().id;

  @override
  Future<Result<AccomplishmentReport>> getById(String id) =>
      getOne(path: _path, id: id, convert: AccomplishmentReport.fromFirestore);

  @override
  Stream<Result<List<AccomplishmentReport>>> watchByWorkOrder(
    String workOrderId, {
    String? submittedBy,
  }) {
    var query = collection(_path).where('workOrderId', isEqualTo: workOrderId);
    if (submittedBy != null) {
      query = query.where('submittedBy', isEqualTo: submittedBy);
    }
    return watchMany(
      query: query,
      convert: AccomplishmentReport.fromFirestore,
    ).map(
      (result) => result.map(
        (reports) =>
            [...reports]
              ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
      ),
    );
  }

  @override
  Future<Result<void>> submit({
    required String reportId,
    required String workOrderId,
    required String completionNotes,
    required List<String> photoUrls,
    required List<MaterialUsage> materialsUsed,
    required AuditActor actor,
  }) async {
    final notes = completionNotes.trim();
    if (notes.isEmpty) {
      return const Result.failure(
        ValidationFailure('Describe the work that was done.'),
      );
    }
    if (notes.length > notesLimit) {
      return const Result.failure(
        ValidationFailure('Keep the notes to $notesLimit characters.'),
      );
    }
    if (photoUrls.length < minPhotos) {
      return const Result.failure(
        ValidationFailure('Add at least one photo of the finished work.'),
      );
    }
    if (photoUrls.length > maxPhotos) {
      return const Result.failure(
        ValidationFailure('Attach at most $maxPhotos photos.'),
      );
    }

    return db.runTransaction<void>((transaction) async {
      // Every read before any write.
      final reportReference = collection(_path).doc(reportId);
      if ((await transaction.get(reportReference)).exists) {
        // Filed already: the first attempt reached the server and the
        // phone retried. Nothing more to do — and nothing deducted twice.
        return;
      }

      final workOrder = await _readWorkOrder(transaction, workOrderId);
      if (!workOrder.assignedPersonnelIds.contains(actor.id)) {
        throw FirestoreRepository.precondition(
          'This work order is not assigned to you.',
        );
      }
      if (workOrder.status != WorkOrderStatus.inProgress) {
        throw FirestoreRepository.precondition(
          workOrder.status == WorkOrderStatus.pending
              ? 'Start the work before marking it complete.'
              : 'This work order is ${workOrder.status.title}, so it cannot '
                    'be submitted again.',
        );
      }

      final deductions = <_PlannedDeduction>[];
      for (final material in materialsUsed) {
        final itemReference = collection(_items).doc(material.inventoryItemId);
        final snapshot = await transaction.get(itemReference);
        if (!snapshot.exists) {
          throw FirestoreRepository.notFound(
            '${material.itemName} is no longer in the inventory. Remove it '
            'from the materials used.',
          );
        }
        final before =
            (snapshot.data()?['quantityAvailable'] as num?)?.toDouble() ?? 0;
        final after = before - material.quantityUsed;
        if (after < 0) {
          throw FirestoreRepository.precondition(
            'Not enough ${material.itemName} in stock: '
            '${_amount(before)} ${material.unitOfMeasurement} left, '
            '${_amount(material.quantityUsed)} recorded as used.',
          );
        }
        deductions.add(
          _PlannedDeduction(
            itemReference: itemReference,
            material: material,
            before: before,
            after: after,
          ),
        );
      }

      final move = await WorkOrderMove.prepare(
        transaction,
        db.raw,
        workOrder: workOrder,
        to: WorkOrderStatus.forReview,
      );

      transaction.set(reportReference, {
        ...AccomplishmentReport(
          id: reportId,
          workOrderId: workOrderId,
          submittedBy: actor.id,
          completionNotes: notes,
          photoUrls: photoUrls,
          materialsUsed: materialsUsed,
          // Set here, not by the caller: the flag means "the deductions
          // below were written", and only this transaction can say so.
          inventoryDeducted: materialsUsed.isNotEmpty,
          submittedAt: DateTime.now().toUtc(),
        ).toFirestore(),
        'submittedAt': FirestoreRepository.serverNow,
      });

      for (final deduction in deductions) {
        final material = deduction.material;
        transaction
          ..update(deduction.itemReference, {
            'quantityAvailable': deduction.after,
            'updatedAt': FirestoreRepository.serverNow,
          })
          ..set(collection(_transactions).doc(), {
            'inventoryItemId': material.inventoryItemId,
            'itemName': material.itemName,
            'type': InventoryTransactionType.consumption.id,
            'quantity': material.quantityUsed,
            'quantityBefore': deduction.before,
            'quantityAfter': deduction.after,
            'workOrderId': workOrderId,
            'accomplishmentReportId': reportId,
            'notes': 'Deducted on accomplishment report submission',
            'performedBy': actor.id,
            'performedByName': actor.name,
            'performedAt': FirestoreRepository.serverNow,
          })
          // The recorded line has done its job once deducted.
          ..delete(_recorded(workOrderId, material.inventoryItemId));
      }

      move.stage(transaction, db.raw, actor: actor);
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _path,
        entityId: reportId,
        description:
            'Accomplishment report filed for '
            '${DisplayId.workOrder(workOrderId)}',
        changes: {
          'workOrderId': workOrderId,
          'photos': photoUrls.length,
          'materials': [
            for (final material in materialsUsed)
              {
                'item': material.inventoryItemId,
                'quantity': material.quantityUsed,
              },
          ],
        },
      );
    });
  }

  @override
  Future<Result<void>> review({
    required String reportId,
    required bool approve,
    required AuditActor actor,
    String? note,
  }) => db.runTransaction<void>((transaction) async {
    final reportReference = collection(_path).doc(reportId);
    final reportSnapshot = await transaction.get(reportReference);
    if (!reportSnapshot.exists) {
      throw FirestoreRepository.notFound('No accomplishment report $reportId');
    }
    final report = AccomplishmentReport.fromFirestore(reportSnapshot);
    if (report.reviewedAt != null) {
      throw FirestoreRepository.precondition(
        'This accomplishment report was reviewed already.',
      );
    }

    final workOrder = await _readWorkOrder(transaction, report.workOrderId);
    if (workOrder.status != WorkOrderStatus.forReview) {
      throw FirestoreRepository.precondition(
        'This work order is ${workOrder.status.title}, not waiting for '
        'sign-off.',
      );
    }

    final move = await WorkOrderMove.prepare(
      transaction,
      db.raw,
      workOrder: workOrder,
      to: approve ? WorkOrderStatus.completed : WorkOrderStatus.inProgress,
    );

    final reason = note?.trim();
    transaction.update(reportReference, {
      'reviewedBy': actor.id,
      'reviewedAt': FirestoreRepository.serverNow,
    });
    if (!approve && reason != null && reason.isNotEmpty) {
      // Shown at the top of the work order on the technician's phone.
      transaction.update(
        collection(FirestorePaths.workOrders).doc(workOrder.id),
        {'adminNotes': reason},
      );
    }
    move.stage(transaction, db.raw, actor: actor);

    for (final personnelId in workOrder.assignedPersonnelIds) {
      stagePersonnelNotice(
        transaction,
        db.raw,
        recipientId: personnelId,
        workOrderId: workOrder.id,
        notice: approve
            ? PersonnelNotice.signedOff(workOrderTitle: workOrder.title)
            : PersonnelNotice.sentBack(workOrderTitle: workOrder.title),
      );
    }
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.updated,
      entityType: _path,
      entityId: reportId,
      description: approve
          ? 'Accomplishment report approved; '
                '${DisplayId.workOrder(workOrder.id)} signed off'
          : 'Accomplishment report sent back; '
                '${DisplayId.workOrder(workOrder.id)} reopened',
      changes: {
        'approved': approve,
        if (reason != null && reason.isNotEmpty) 'note': reason,
      },
    );
  });

  DocumentReference<Map<String, dynamic>> _recorded(
    String workOrderId,
    String inventoryItemId,
  ) =>
      collection(FirestorePaths.workOrders)
          .doc(workOrderId)
          .collection(FirestorePaths.materialsUsed)
          .doc(inventoryItemId);

  Future<WorkOrder> _readWorkOrder(Transaction transaction, String id) async {
    final snapshot = await transaction.get(
      collection(FirestorePaths.workOrders).doc(id),
    );
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No work order $id');
    }
    return WorkOrder.fromFirestore(snapshot);
  }

  /// 2, not 2.0; 1.5 as it is.
  static String _amount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// A validated deduction, held between the read and write phases.
class _PlannedDeduction {
  const _PlannedDeduction({
    required this.itemReference,
    required this.material,
    required this.before,
    required this.after,
  });

  final DocumentReference<Map<String, dynamic>> itemReference;
  final MaterialUsage material;
  final double before;
  final double after;
}
