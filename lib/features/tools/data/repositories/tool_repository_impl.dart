import '../../../../core/data/row_snapshot.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/tool.dart';
import '../models/tool_draft.dart';
import '../models/tool_loan.dart';
import 'tool_repository.dart';

/// Supabase-backed [ToolRepository] (Objective 1).
///
/// A tool's status and its loan record never disagree (§1.5): the tool
/// functions borrow and return in one transaction each, and a tool that
/// comes back in poor condition goes to repair.
class ToolRepositoryImpl extends SupabaseRepository implements ToolRepository {
  const ToolRepositoryImpl({required super.client, required super.guard});

  static const String _tools = 'tools';
  static const String _loans = 'tool_loans';

  @override
  Future<Result<Tool>> getToolById(String id) =>
      getOne(table: _tools, id: id, convert: Tool.fromFirestore);

  @override
  Future<Result<Tool>> getToolByQrCode(String qrCode) async {
    final matches = await getMany(
      query: client.from(_tools).select().eq('qr_code', qrCode).limit(1),
      convert: Tool.fromFirestore,
    );
    return matches.fold(
      (list) => list.isEmpty
          ? const Result<Tool>.failure(
              NotFoundFailure('No registered tool matches that QR code.'),
            )
          : Result.success(list.first),
      Result.failure,
    );
  }

  @override
  Stream<Result<List<Tool>>> watchTools({ToolStatus? status}) =>
      // Filtered here: a tool's status changes with every loan.
      watchMany(
        stream: client
            .from(_tools)
            .stream(primaryKey: const ['id'])
            .order('tool_code', ascending: true),
        convert: Tool.fromFirestore,
      ).map(
        (result) => result.map(
          (tools) => [
            for (final tool in tools)
              if (status == null || tool.status == status) tool,
          ],
        ),
      );

  @override
  Stream<Result<Tool>> watchTool(String id) =>
      watchOne(table: _tools, id: id, convert: Tool.fromFirestore);

  @override
  Future<Result<String>> createTool({
    required ToolDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    return rpcOnce<String>('create_tool', _fields(draft));
  }

  @override
  Future<Result<void>> updateToolDetails({
    required String toolId,
    required ToolDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    return rpc('update_tool', {'id': toolId, ..._fields(draft)});
  }

  @override
  Future<Result<void>> setToolStatus({
    required String toolId,
    required ToolStatus status,
    required AuditActor actor,
  }) => rpc('set_tool_status', {'id': toolId, 'status': status.id});

  @override
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required AuditActor borrower,
    AuditActor? issuedBy,
    String? workOrderId,
    DateTime? expectedReturnAt,
  }) => rpcRow(
    'borrow_tool',
    {
      'tool_id': toolId,
      'borrower_id': borrower.id,
      'work_order_id': workOrderId,
      'expected_return_at': SupabaseRepository.time(expectedReturnAt),
    },
    convert: ToolLoan.fromFirestore,
    // Once: a retry after a loan that landed is refused ("borrowed") and
    // would hide that it worked.
    once: true,
  );

  @override
  Future<Result<void>> returnTool({
    required String loanId,
    required ItemCondition conditionOnReturn,
    required AuditActor actor,
    String? notes,
  }) => rpcOnce<void>('return_tool', {
    'loan_id': loanId,
    'condition': conditionOnReturn.id,
    'notes': notes,
  });

  /// Filtered on the borrower, which never changes, and open loans picked
  /// here: a stream filtered on the return would never hear of one.
  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoansFor(String personnelId) =>
      _watchLoans(
        client
            .from(_loans)
            .stream(primaryKey: const ['id'])
            .eq('borrowed_by', personnelId),
        openOnly: true,
      );

  @override
  Stream<Result<List<ToolLoan>>> watchLoansForWorkOrder(String workOrderId) =>
      _watchLoans(
        client
            .from(_loans)
            .stream(primaryKey: const ['id'])
            .eq('work_order_id', workOrderId),
      );

  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoans() => _watchLoans(
    client.from(_loans).stream(primaryKey: const ['id']),
    openOnly: true,
  );

  @override
  Future<Result<List<ToolLoan>>> getOpenLoansForPersonnel(String personnelId) =>
      getMany(
        query: client
            .from(_loans)
            .select()
            .eq('borrowed_by', personnelId)
            .isFilter('returned_at', null)
            .order('borrowed_at'),
        convert: ToolLoan.fromFirestore,
      );

  @override
  Stream<Result<List<ToolLoan>>> watchLoanHistory(String toolId) => _watchLoans(
    client.from(_loans).stream(primaryKey: const ['id']).eq('tool_id', toolId),
  );

  @override
  Future<Result<List<ToolLoan>>> getLoanHistory(
    String toolId, {
    int limit = 50,
  }) => getMany(
    query: client
        .from(_loans)
        .select()
        .eq('tool_id', toolId)
        .order('borrowed_at')
        .limit(limit),
    convert: ToolLoan.fromFirestore,
  );

  /// Loans, newest first.
  Stream<Result<List<ToolLoan>>> _watchLoans(
    Stream<List<Map<String, dynamic>>> stream, {
    bool openOnly = false,
  }) => watchMany(stream: stream, convert: ToolLoan.fromFirestore).map(
    (result) => result.map(
      (loans) => [
        for (final loan in loans)
          if (!openOnly || !loan.isReturned) loan,
      ]..sort((a, b) => b.borrowedAt.compareTo(a.borrowedAt)),
    ),
  );

  static Map<String, Object?> _fields(ToolDraft draft) => {
    for (final MapEntry(:key, :value) in draft.toFields().entries)
      RowSnapshot.columnFor(key): value,
  };
}
