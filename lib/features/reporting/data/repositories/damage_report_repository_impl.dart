import 'package:supabase/supabase.dart' show CountOption;

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/damage_report.dart';
import '../models/report_assessment.dart';
import '../models/report_submission.dart';
import '../models/status_change.dart';
import 'damage_report_repository.dart';

/// Supabase-backed [DamageReportRepository] (Objective 1). Persistence
/// only: the classification, scoring and duplicate rules (Objective 4)
/// live in `features/classification/domain`, and this stores what they
/// decide.
///
/// Every move goes through a report function
/// (supabase/migrations/*_report_functions.sql), which checks the stored
/// report, writes the timeline entry and the requestor's notice, and
/// audits the change, all in one transaction.
class DamageReportRepositoryImpl extends SupabaseRepository
    implements DamageReportRepository {
  const DamageReportRepositoryImpl({
    required super.client,
    required super.guard,
  });

  static const String _table = 'damage_reports';

  static const int statusHistoryLimit = 50;

  @override
  Future<Result<DamageReport>> getById(String id) =>
      getOne(table: _table, id: id, convert: DamageReport.fromFirestore);

  @override
  Stream<Result<DamageReport>> watchById(String id) =>
      watchOne(table: _table, id: id, convert: DamageReport.fromFirestore);

  @override
  Stream<Result<List<StatusChange>>> watchStatusHistory(String reportId) =>
      watchMany(
        stream: client
            .from('report_status_history')
            .stream(primaryKey: const ['id'])
            .eq('report_id', reportId)
            .order('changed_at', ascending: true)
            // Far beyond any real report's history; a bound all the same.
            .limit(statusHistoryLimit),
        convert: StatusChange.fromFirestore,
      );

  @override
  Stream<Result<List<DamageReport>>> watchByReporter(String reporterId) =>
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .eq('reporter_id', reporterId)
            .order('submitted_at')
            .limit(DamageReportRepository.reporterQueryLimit),
        convert: DamageReport.fromFirestore,
      );

  @override
  Stream<Result<List<DamageReport>>> watchAll({
    ReportStatus? status,
    PriorityLevel? priority,
    String? categoryId,
    bool excludeDuplicates = true,
  }) =>
      // Filtered here rather than by the stream: status, priority and
      // category all change, and Realtime never tells a stream filtered on
      // a column about a row that has left it.
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .order('submitted_at'),
        convert: DamageReport.fromFirestore,
      ).map(
        (result) => result.map(
          (reports) => [
            for (final report in reports)
              if ((!excludeDuplicates || report.duplicateOf == null) &&
                  (status == null || report.status == status) &&
                  (priority == null || report.officialPriority == priority) &&
                  (categoryId == null || report.category?.id == categoryId))
                report,
          ],
        ),
      );

  @override
  Future<Result<String>> create(DamageReport report) =>
      SupabaseRepository.unsupported('DamageReportRepository.create');

  @override
  String newReportId() => SupabaseRepository.newId();

  @override
  Future<Result<void>> submit({
    required String reportId,
    required ReportSubmission submission,
  }) =>
      // Safe to retry: filing again under the same id is a no-op.
      rpc('submit_report', {
        'id': reportId,
        'title': submission.title,
        'description': submission.description,
        'requestor_priority': submission.requestorPriority.id,
        'requestor_category': submission.requestorCategory?.id,
        // The keyword classifier's match, made on the filing phone (4.A).
        'category': submission.classifiedCategory?.id,
        'facility_id': submission.facilityId,
        'facility_name': submission.facilityName,
        'location_description': submission.locationDescription,
        'asset_id': submission.assetId,
        'latitude': submission.coordinates?.latitude,
        'longitude': submission.coordinates?.longitude,
        'photo_urls': submission.photoUrls,
      });

  @override
  Future<Result<void>> update(DamageReport report) =>
      SupabaseRepository.unsupported('DamageReportRepository.update');

  @override
  Future<Result<void>> recordAssessment({
    required String reportId,
    required ReportAssessment assessment,
    required AuditActor actor,
  }) => rpc('record_assessment', {
    'report_id': reportId,
    'category': assessment.category.id,
    'classified_automatically': assessment.classifiedAutomatically,
    'severity_rating': assessment.severityRating,
    'safety_risk_rating': assessment.safetyRiskRating,
    'frequency_rating': assessment.frequencyRating,
    'location_importance_rating': assessment.locationImportanceRating,
    'priority_score': assessment.priorityScore,
    'recommended_priority': assessment.recommendedPriority.id,
    'official_priority': assessment.officialPriority.id,
  });

  @override
  Future<Result<int>> countSimilarReports({
    required String facilityId,
    required DamageCategory category,
    required DateTime since,
  }) => guard.call(() async {
    // A count, not a read of the reports: the hint needs a number.
    final response = await client
        .from(_table)
        .select('id')
        .eq('facility_id', facilityId)
        .eq('category', category.id)
        .gte('submitted_at', SupabaseRepository.time(since)!)
        .count(CountOption.exact);
    return response.count;
  });

  @override
  Future<Result<void>> transitionStatus({
    required String reportId,
    required ReportStatus to,
    required AuditActor actor,
    String? reason,
  }) => rpc('transition_report', {
    'report_id': reportId,
    'to_status': to.id,
    'reason': reason,
  });

  @override
  Future<Result<void>> mergeDuplicates({
    required String parentReportId,
    required List<String> duplicateReportIds,
    required AuditActor actor,
  }) => rpc('merge_duplicates', {
    'parent_id': parentReportId,
    'duplicate_ids': duplicateReportIds,
  });

  @override
  Future<Result<void>> keepSeparate({
    required String reportId,
    required String otherReportId,
    required AuditActor actor,
  }) => rpc('keep_separate', {
    'report_id': reportId,
    'other_report_id': otherReportId,
  });
}
