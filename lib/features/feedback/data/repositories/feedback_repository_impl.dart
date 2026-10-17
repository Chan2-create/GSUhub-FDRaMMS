import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/service_feedback.dart';
import 'feedback_repository.dart';

/// Supabase-backed [FeedbackRepository] (Objective 1). Persistence only —
/// no averaging of the three ratings, which stay independent by design
/// (§1.5). Row level security shows a rating to an administrator and to
/// the requestor who gave it, never to the technician rated.
class FeedbackRepositoryImpl extends SupabaseRepository
    implements FeedbackRepository {
  const FeedbackRepositoryImpl({required super.client, required super.guard});

  static const String _table = 'feedback';

  @override
  Future<Result<ServiceFeedback>> getById(String id) =>
      getOne(table: _table, id: id, convert: ServiceFeedback.fromFirestore);

  @override
  Future<Result<ServiceFeedback?>> getByWorkOrder(String workOrderId) async {
    final matches = await getMany(
      query: client
          .from(_table)
          .select()
          .eq('work_order_id', workOrderId)
          .limit(1),
      convert: ServiceFeedback.fromFirestore,
    );
    // Absence is normal: rating is optional (Figure 23 offers "Skip").
    return matches.map((list) => list.isEmpty ? null : list.first);
  }

  @override
  Future<Result<List<ServiceFeedback>>> getByRequestor(String requestorId) =>
      getMany(
        query: client
            .from(_table)
            .select()
            .eq('submitted_by', requestorId)
            .order('submitted_at'),
        convert: ServiceFeedback.fromFirestore,
      );

  @override
  Future<Result<List<ServiceFeedback>>> getInRange({
    required DateTime from,
    required DateTime to,
  }) => getMany(
    query: client
        .from(_table)
        .select()
        .gte('submitted_at', SupabaseRepository.time(from)!)
        .lte('submitted_at', SupabaseRepository.time(to)!)
        .order('submitted_at'),
    convert: ServiceFeedback.fromFirestore,
  );

  @override
  Stream<Result<ServiceFeedback?>> watchForReport(String reportId) =>
      guard.stream(
        client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .eq('id', reportId)
            .map(
              (rows) => rows.isEmpty
                  ? null
                  : ServiceFeedback.fromFirestore(
                      RowSnapshot.fromRow(rows.first),
                    ),
            ),
      );

  @override
  Future<Result<void>> rate({
    required String reportId,
    required AuditActor rater,
    required int responseTime,
    required int serviceQuality,
    required int overallSatisfaction,
    String? comments,
  }) =>
      // Safe to retry: a rating that already landed makes it a no-op.
      rpc('rate_service', {
        'report_id': reportId,
        'response_time': responseTime,
        'service_quality': serviceQuality,
        'overall_satisfaction': overallSatisfaction,
        'comments': comments,
      });
}
