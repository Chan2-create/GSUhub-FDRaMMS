import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/material_line.dart';
import '../models/material_request.dart';
import 'material_request_repository.dart';

/// Supabase-backed [MaterialRequestRepository] (Objective 1, 6.B): a
/// technician asks for materials for their open work; an administrator
/// approves, setting them aside on the work order, or declines with a
/// reason. Either way the technician is told.
class MaterialRequestRepositoryImpl extends SupabaseRepository
    implements MaterialRequestRepository {
  const MaterialRequestRepositoryImpl({
    required super.client,
    required super.guard,
  });

  static const String _table = 'material_requests';

  /// The longest note either side may write.
  static const int noteLimit = 300;

  /// The most materials one request may ask for.
  static const int itemLimit = 20;

  @override
  String newRequestId() => SupabaseRepository.newId();

  @override
  Stream<Result<List<MaterialRequest>>> watchForWorkOrder(
    String workOrderId, {
    String? requestedBy,
  }) =>
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .eq('work_order_id', workOrderId),
        convert: MaterialRequest.fromFirestore,
      ).map(
        (result) => result.map(
          (requests) => [
            for (final request in requests)
              if (requestedBy == null || request.requestedBy == requestedBy)
                request,
          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        ),
      );

  @override
  Stream<Result<List<MaterialRequest>>> watchRecent({int limit = 50}) =>
      watchMany(
        stream: client
            .from(_table)
            .stream(primaryKey: const ['id'])
            .order('created_at')
            .limit(limit),
        convert: MaterialRequest.fromFirestore,
      );

  @override
  Future<Result<void>> submit({
    required String requestId,
    required String workOrderId,
    required List<MaterialLine> items,
    required AuditActor actor,
    String? note,
  }) =>
      // Safe to retry: asking again under the same id is a no-op.
      rpc('submit_material_request', {
        'id': requestId,
        'work_order_id': workOrderId,
        'items': [for (final item in items) item.toMap()],
        'note': note,
      });

  @override
  Future<Result<void>> approve({
    required String requestId,
    required AuditActor actor,
    String? note,
  }) => rpc('approve_material_request', {'id': requestId, 'note': note});

  @override
  Future<Result<void>> decline({
    required String requestId,
    required AuditActor actor,
    required String note,
  }) => rpc('decline_material_request', {'id': requestId, 'note': note});
}
