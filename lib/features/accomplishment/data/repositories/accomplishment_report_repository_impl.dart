import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/accomplishment_report.dart';
import '../models/material_usage.dart';
import 'accomplishment_report_repository.dart';

/// Supabase-backed [AccomplishmentReportRepository] (Objective 1).
///
/// [submit] carries the most important invariant in the system: filing a
/// completion report and deducting the materials it consumed happen
/// together or not at all (§3.4). `submit_accomplishment` does both in one
/// transaction, the deductions as ledger entries.
class AccomplishmentReportRepositoryImpl extends SupabaseRepository
    implements AccomplishmentReportRepository {
  const AccomplishmentReportRepositoryImpl({
    required super.client,
    required super.guard,
  });

  static const String _table = 'accomplishment_reports';

  /// The longest completion note accepted.
  static const int notesLimit = 2000;

  /// Photos a report needs: §3.4 has personnel "upload photo evidence of
  /// completed maintenance", and the form takes up to five.
  static const int minPhotos = 1;
  static const int maxPhotos = 5;

  @override
  String newReportId() => SupabaseRepository.newId();

  @override
  Future<Result<AccomplishmentReport>> getById(String id) => getOne(
    table: _table,
    id: id,
    convert: AccomplishmentReport.fromFirestore,
  );

  @override
  Stream<Result<List<AccomplishmentReport>>> watchByWorkOrder(
    String workOrderId, {
    String? submittedBy,
  }) =>
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .eq('work_order_id', workOrderId),
        convert: AccomplishmentReport.fromFirestore,
      ).map(
        (result) => result.map(
          (reports) => [
            for (final report in reports)
              if (submittedBy == null || report.submittedBy == submittedBy)
                report,
          ]..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
        ),
      );

  @override
  Future<Result<void>> submit({
    required String reportId,
    required String workOrderId,
    required String completionNotes,
    required List<String> photoUrls,
    required List<MaterialUsage> materialsUsed,
    required AuditActor actor,
  }) =>
      // Safe to retry: filing again under the same id is a no-op, and
      // nothing is deducted twice.
      rpc('submit_accomplishment', {
        'id': reportId,
        'work_order_id': workOrderId,
        'completion_notes': completionNotes,
        'photo_urls': photoUrls,
        'materials': [for (final material in materialsUsed) material.toMap()],
      });

  @override
  Future<Result<void>> review({
    required String reportId,
    required bool approve,
    required AuditActor actor,
    String? note,
  }) => rpc('review_accomplishment', {
    'report_id': reportId,
    'approve': approve,
    'note': note,
  });
}
