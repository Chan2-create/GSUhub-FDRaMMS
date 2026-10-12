import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/accomplishment_report.dart';
import '../models/material_usage.dart';

/// Abstract contract for the `accomplishment_reports` collection: what a
/// technician files when the work is done, and the administrator's review
/// of it (Objective 5.B).
abstract interface class AccomplishmentReportRepository {
  /// A fresh id for a report about to be submitted. Reserved before the
  /// photos upload, so they are stored under it, and so a retried
  /// submission files the same report rather than a second one.
  String newReportId();

  Future<Result<AccomplishmentReport>> getById(String id);

  /// The reports filed against a work order, newest first — more than one
  /// when work was sent back and done again. A technician passes their own
  /// uid as [submittedBy]: the rules let them list only their own.
  Stream<Result<List<AccomplishmentReport>>> watchByWorkOrder(
    String workOrderId, {
    String? submittedBy,
  });

  /// Files the completed work (technician).
  ///
  /// In one transaction: the report under [reportId]; for each of
  /// [materialsUsed], its deduction from stock and a `consumption` ledger
  /// entry (manuscript §3.4: "Once the maintenance personnel submits the
  /// accomplishment report, the system automatically deducts the used
  /// quantity"); the work order's recorded-materials list cleared; and the
  /// work order with its reports moved to For Review. Refused unless
  /// [actor] is assigned and the work is in progress, or if any material
  /// is short.
  ///
  /// Idempotent: a report already filed under [reportId] is left as it is
  /// and nothing is deducted twice.
  Future<Result<void>> submit({
    required String reportId,
    required String workOrderId,
    required String completionNotes,
    required List<String> photoUrls,
    required List<MaterialUsage> materialsUsed,
    required AuditActor actor,
  });

  /// The administrator's review of a submitted report: [approve] signs the
  /// work order off as completed; otherwise it goes back to In Progress,
  /// with [note] shown to the technician at the top of the work order.
  /// Either way the report is marked reviewed and the technician told.
  Future<Result<void>> review({
    required String reportId,
    required bool approve,
    required AuditActor actor,
    String? note,
  });
}
