import '../../../../core/utils/result.dart';
import '../models/accomplishment_report.dart';

/// Abstract contract for the `accomplishment_reports` collection.
///
/// **Interface only** — implementation is 1.C.
abstract interface class AccomplishmentReportRepository {
  Future<Result<AccomplishmentReport>> getById(String id);

  /// The report(s) filed against a work order.
  Future<Result<List<AccomplishmentReport>>> getByWorkOrder(String workOrderId);

  Stream<Result<List<AccomplishmentReport>>> watchPendingReview();

  /// Files a completed-work report.
  ///
  /// This is the trigger for automatic inventory deduction: manuscript
  /// §3.4 states that on submission "the system automatically deducts the
  /// used quantity from the current inventory balance and records the
  /// transaction in the inventory history log". Implementations must
  /// write the accomplishment report and its `consumption` transactions
  /// **atomically** — a report saved without its deductions, or deductions
  /// without their report, leaves the ledger permanently inconsistent with
  /// stock on hand.
  ///
  /// The deduction must also be idempotent, keyed on the report's
  /// `inventoryDeducted` flag, so a retried submission cannot deduct the
  /// same materials twice.
  Future<Result<String>> submit(AccomplishmentReport report);

  /// Records an Administrator's review of a submitted report.
  Future<Result<void>> markReviewed({
    required String reportId,
    required String reviewedBy,
  });
}
