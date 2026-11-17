import '../../../../core/data/row_record.dart';
import '../../../../core/data/supabase_repository.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/tool.dart';
import '../models/tool_draft.dart';
import '../models/tool_loan.dart';
import '../models/tool_request.dart';
import 'tool_repository.dart';

/// Supabase-backed [ToolRepository] (Objective 1).
///
/// A tool's status and its loan record never disagree (§1.5): the tool
/// functions borrow and return in one transaction each, and a tool that
/// comes back in poor condition goes to repair.
class ToolRepositoryImpl extends SupabaseRepository implements ToolRepository {
  const ToolRepositoryImpl({
    required super.client,
    required super.guard,
    super.live,
  });

  static const String _tools = 'tools';
  static const String _loans = 'tool_loans';
  static const String _requests = 'tool_requests';

  @override
  Future<Result<Tool>> getToolById(String id) async =>
      _present(await getOne(table: _tools, id: id, convert: Tool.fromRecord));

  @override
  Future<Result<Tool>> getToolByQrCode(String qrCode) async {
    final matches = await getMany(
      // A deleted tool's code may be on a tool added since.
      query: client
          .from(_tools)
          .select()
          .eq('qr_code', qrCode)
          .isFilter('deleted_at', null)
          .limit(1),
      convert: Tool.fromRecord,
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
      // Filtered here, as it was under the Realtime stream, which could
      // not filter on a status that changes or on an empty deleted_at.
      watchMany(
        stream: liveRows(
          _tools,
          (rows) => rows.order('tool_code', ascending: true),
        ),
        convert: Tool.fromRecord,
      ).map(
        (result) => result.map(
          (tools) => [
            for (final tool in tools)
              if (!tool.isDeleted && (status == null || tool.status == status))
                tool,
          ],
        ),
      );

  @override
  Stream<Result<Tool>> watchTool(String id) =>
      watchOne(table: _tools, id: id, convert: Tool.fromRecord).map(_present);

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
  Future<Result<void>> deleteTool({
    required String toolId,
    required AuditActor actor,
  }) => rpc('delete_tool', {'id': toolId});

  /// A deleted tool reads as gone.
  static Result<Tool> _present(Result<Tool> result) => switch (result) {
    Success(:final value) when value.isDeleted => const Result.failure(
      NotFoundFailure('This tool is no longer in the inventory.'),
    ),
    _ => result,
  };

  @override
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required String scannedCode,
    required AuditActor borrower,
    String? workOrderId,
  }) => rpcRow(
    'borrow_tool_by_scan',
    {
      'tool_id': toolId,
      'scanned_code': scannedCode,
      'work_order_id': workOrderId,
    },
    convert: ToolLoan.fromRecord,
    // Once: a retry after a loan that landed is refused ("borrowed") and
    // would hide that it worked.
    once: true,
  );

  @override
  Future<Result<void>> returnTool({
    required String loanId,
    required String scannedCode,
    required ItemCondition conditionOnReturn,
    required AuditActor actor,
    String? notes,
  }) => rpcOnce<void>('confirm_tool_return', {
    'loan_id': loanId,
    'scanned_code': scannedCode,
    'condition': conditionOnReturn.id,
    'notes': notes,
  });

  // Every request call is made once: a retry after one that landed is
  // refused ("already confirmed", "already requested") and would hide
  // that it worked.

  @override
  Future<Result<String>> requestCheckOut({
    required String toolId,
    required String personnelId,
    required DateTime checkoutAt,
    required String purpose,
    required AuditActor actor,
    DateTime? dueAt,
    String? message,
    String? workOrderId,
  }) => rpcOnce<String>('request_tool_checkout', {
    'tool_id': toolId,
    'personnel_id': personnelId,
    'checkout_at': SupabaseRepository.time(checkoutAt),
    'due_at': SupabaseRepository.time(dueAt),
    'purpose': purpose,
    'message': message,
    'work_order_id': workOrderId,
  });

  @override
  Future<Result<ToolLoan>> confirmCheckOut({
    required String requestId,
    required String scannedCode,
    required AuditActor actor,
  }) => rpcRow(
    'confirm_tool_checkout',
    {'request_id': requestId, 'scanned_code': scannedCode},
    convert: ToolLoan.fromRecord,
    once: true,
  );

  @override
  Future<Result<String>> requestReturn({
    required String loanId,
    required DateTime dueAt,
    required AuditActor actor,
    String? message,
  }) => rpcOnce<String>('request_tool_return', {
    'loan_id': loanId,
    'due_at': SupabaseRepository.time(dueAt),
    'message': message,
  });

  @override
  Future<Result<void>> cancelRequest({
    required String requestId,
    required AuditActor actor,
  }) => rpcOnce<void>('cancel_tool_request', {'request_id': requestId});

  /// Filtered here, as loans are, and as it was under the Realtime
  /// stream, which could not filter on a status that changes.
  @override
  Stream<Result<List<ToolRequest>>> watchOpenRequests() =>
      _watchRequests(liveRows(_requests), pendingOnly: true);

  @override
  Stream<Result<List<ToolRequest>>> watchRequestsFor(String personnelId) =>
      _watchRequests(
        liveRows(_requests, (rows) => rows.eq('personnel_id', personnelId)),
      );

  @override
  Stream<Result<List<ToolRequest>>> watchRequestHistory(String toolId) =>
      _watchRequests(liveRows(_requests, (rows) => rows.eq('tool_id', toolId)));

  /// Requests, newest first.
  Stream<Result<List<ToolRequest>>> _watchRequests(
    Stream<List<Map<String, dynamic>>> stream, {
    bool pendingOnly = false,
  }) => watchMany(stream: stream, convert: ToolRequest.fromRecord).map(
    (result) => result.map(
      (requests) => [
        for (final request in requests)
          if (!pendingOnly || request.isPending) request,
      ]..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
    ),
  );

  /// Filtered on the borrower, and open loans picked here, as it was
  /// under the Realtime stream, which could not filter on the return.
  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoansFor(String personnelId) =>
      _watchLoans(
        liveRows(_loans, (rows) => rows.eq('borrowed_by', personnelId)),
        openOnly: true,
      );

  @override
  Stream<Result<List<ToolLoan>>> watchLoansForWorkOrder(String workOrderId) =>
      _watchLoans(
        liveRows(_loans, (rows) => rows.eq('work_order_id', workOrderId)),
      );

  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoans() =>
      _watchLoans(liveRows(_loans), openOnly: true);

  @override
  Future<Result<List<ToolLoan>>> getOpenLoansForPersonnel(String personnelId) =>
      getMany(
        query: client
            .from(_loans)
            .select()
            .eq('borrowed_by', personnelId)
            .isFilter('returned_at', null)
            .order('borrowed_at'),
        convert: ToolLoan.fromRecord,
      );

  @override
  Stream<Result<List<ToolLoan>>> watchLoanHistory(String toolId) =>
      _watchLoans(liveRows(_loans, (rows) => rows.eq('tool_id', toolId)));

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
    convert: ToolLoan.fromRecord,
  );

  /// Loans, newest first.
  Stream<Result<List<ToolLoan>>> _watchLoans(
    Stream<List<Map<String, dynamic>>> stream, {
    bool openOnly = false,
  }) => watchMany(stream: stream, convert: ToolLoan.fromRecord).map(
    (result) => result.map(
      (loans) => [
        for (final loan in loans)
          if (!openOnly || !loan.isReturned) loan,
      ]..sort((a, b) => b.borrowedAt.compareTo(a.borrowedAt)),
    ),
  );

  static Map<String, Object?> _fields(ToolDraft draft) => {
    for (final MapEntry(:key, :value) in draft.toFields().entries)
      RowRecord.columnFor(key): value,
  };
}
