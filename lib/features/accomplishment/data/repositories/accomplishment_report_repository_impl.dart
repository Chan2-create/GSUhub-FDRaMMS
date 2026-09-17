import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/inventory_transaction_type.dart';
import '../../../../core/utils/result.dart';
import '../models/accomplishment_report.dart';
import 'accomplishment_report_repository.dart';

/// Firestore-backed [AccomplishmentReportRepository].
///
/// [submit] carries the most important invariant in the system: filing a
/// completion report and deducting the materials it consumed must happen
/// together or not at all (manuscript §3.4).
class AccomplishmentReportRepositoryImpl extends FirestoreRepository
    implements AccomplishmentReportRepository {
  const AccomplishmentReportRepositoryImpl({
    required super.db,
    required super.guard,
  });

  static const String _path = FirestorePaths.accomplishmentReports;
  static const String _items = FirestorePaths.inventoryItems;
  static const String _transactions = FirestorePaths.inventoryTransactions;

  @override
  Future<Result<AccomplishmentReport>> getById(String id) =>
      getOne(path: _path, id: id, convert: AccomplishmentReport.fromFirestore);

  @override
  Future<Result<List<AccomplishmentReport>>> getByWorkOrder(
    String workOrderId,
  ) => getMany(
    query: collection(_path)
        .where('workOrderId', isEqualTo: workOrderId)
        .orderBy('submittedAt', descending: true),
    convert: AccomplishmentReport.fromFirestore,
  );

  @override
  Stream<Result<List<AccomplishmentReport>>> watchPendingReview() => watchMany(
    query: collection(_path)
        .where('reviewedAt', isNull: true)
        .orderBy('submittedAt'),
    convert: AccomplishmentReport.fromFirestore,
  );

  @override
  Future<Result<String>> submit(AccomplishmentReport report) =>
      db.runTransaction<String>((transaction) async {
        final reportRef = collection(_path).doc();

        // Firestore requires every read in a transaction to happen before
        // any write, so all stock levels are read up front.
        final itemRefs = report.materialsUsed
            .map((material) => collection(_items).doc(material.inventoryItemId))
            .toList(growable: false);

        final itemSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final reference in itemRefs) {
          itemSnapshots.add(await transaction.get(reference));
        }

        // Validate everything before writing anything. A partially
        // applied deduction would leave stock and ledger permanently
        // disagreeing, which no later correction can fully unwind.
        final deductions = <_PlannedDeduction>[];
        for (var i = 0; i < report.materialsUsed.length; i++) {
          final material = report.materialsUsed[i];
          final snapshot = itemSnapshots[i];

          if (!snapshot.exists) {
            throw FirebaseException(
              plugin: 'gsuhub',
              code: 'not-found',
              message:
                  'Inventory item ${material.itemName} '
                  '(${material.inventoryItemId}) no longer exists.',
            );
          }

          final before =
              (snapshot.data()?['quantityAvailable'] as num?)?.toDouble() ?? 0;
          final after = before - material.quantityUsed;

          if (after < 0) {
            throw FirebaseException(
              plugin: 'gsuhub',
              code: 'failed-precondition',
              message:
                  'Not enough ${material.itemName} in stock: '
                  '$before available, ${material.quantityUsed} used.',
            );
          }

          deductions.add(
            _PlannedDeduction(
              itemRef: itemRefs[i],
              itemName: material.itemName,
              inventoryItemId: material.inventoryItemId,
              quantity: material.quantityUsed,
              before: before,
              after: after,
            ),
          );
        }

        transaction.set(reportRef, {
          ...report.toFirestore(),
          // Set here rather than by the caller: the flag means "the
          // deductions below were written", and only this transaction can
          // truthfully claim that.
          'inventoryDeducted': report.materialsUsed.isNotEmpty,
        });

        for (final deduction in deductions) {
          transaction.update(deduction.itemRef, {
            'quantityAvailable': deduction.after,
            'updatedAt': FirestoreRepository.serverNow,
          });

          transaction.set(collection(_transactions).doc(), {
            'inventoryItemId': deduction.inventoryItemId,
            'itemName': deduction.itemName,
            'type': InventoryTransactionType.consumption.id,
            'quantity': deduction.quantity,
            'quantityBefore': deduction.before,
            'quantityAfter': deduction.after,
            'workOrderId': report.workOrderId,
            // Doubles as the idempotency key: a retried submission
            // creates a new report id, so a duplicate deduction against
            // the same report is identifiable.
            'accomplishmentReportId': reportRef.id,
            'notes': 'Automatic deduction on accomplishment report submission',
            'performedBy': report.submittedBy,
            'performedAt': FirestoreRepository.serverNow,
          });
        }

        return reportRef.id;
      });

  @override
  Future<Result<void>> markReviewed({
    required String reportId,
    required String reviewedBy,
  }) => updateDoc(
    path: _path,
    id: reportId,
    data: {
      'reviewedBy': reviewedBy,
      'reviewedAt': FirestoreRepository.serverNow,
    },
  );
}

/// A validated deduction, held between the read and write phases of the
/// submission transaction.
class _PlannedDeduction {
  const _PlannedDeduction({
    required this.itemRef,
    required this.itemName,
    required this.inventoryItemId,
    required this.quantity,
    required this.before,
    required this.after,
  });

  final DocumentReference<Map<String, dynamic>> itemRef;
  final String itemName;
  final String inventoryItemId;
  final double quantity;
  final double before;
  final double after;
}
