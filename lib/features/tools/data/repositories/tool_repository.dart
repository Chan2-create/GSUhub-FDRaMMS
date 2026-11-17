import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/tool.dart';
import '../models/tool_draft.dart';
import '../models/tool_loan.dart';
import '../models/tool_request.dart';

/// Abstract contract for the `tools` collection and its `tool_loans`
/// borrow history (manuscript §1.5 tool and equipment tracking).
///
/// Durable equipment, kept separate from consumable `inventory_items`: a
/// tool is checked out and checked back in, a consumable is deducted and
/// gone.
abstract interface class ToolRepository {
  Future<Result<Tool>> getToolById(String id);

  Future<Result<Tool>> getToolByQrCode(String qrCode);

  Stream<Result<List<Tool>>> watchTools({ToolStatus? status});

  /// One tool, live: its row's details, holder and actions.
  Stream<Result<Tool>> watchTool(String id);

  /// Registers a tool, on the shelf (Objective 6.B). Refused when its tool
  /// ID is taken, or another material, tool, room or piece of equipment
  /// carries its code.
  Future<Result<String>> createTool({
    required ToolDraft draft,
    required AuditActor actor,
  });

  /// Saves a tool's details. Its condition is kept as it is while it is
  /// out: the return records the condition it comes back in.
  Future<Result<void>> updateToolDetails({
    required String toolId,
    required ToolDraft draft,
    required AuditActor actor,
  });

  /// Sends a tool on the shelf to repair, brings one back from repair, or
  /// retires one (Objective 6.B). Never for a tool that is out: it comes
  /// back through a return. A retired tool stays retired.
  Future<Result<void>> setToolStatus({
    required String toolId,
    required ToolStatus status,
    required AuditActor actor,
  });

  /// Takes a tool out of the inventory (2026-11-08). Its loans keep it, so
  /// it is marked deleted: never listed or found again, its tool ID and
  /// code free. Refused while it is out on loan.
  Future<Result<void>> deleteTool({
    required String toolId,
    required AuditActor actor,
  });

  /// A technician takes a tool off the shelf for themselves, confirmed
  /// with [scannedCode], the code read from the tool (2026-11-16).
  ///
  /// Writes the `tool_loans` record and flips the tool to
  /// [ToolStatus.borrowed] with its holder atomically — a tool marked
  /// available while physically out, or out with no recorded custodian,
  /// defeats the accountability requirement (§1.5).
  ///
  /// Refused unless the code is the tool's own, and unless the tool is
  /// [ToolStatus.available]: one [ToolStatus.reserved] is someone's to
  /// collect through their checkout request.
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required String scannedCode,
    required AuditActor borrower,
    String? workOrderId,
  });

  /// The technician holding a tool hands it back, confirmed with
  /// [scannedCode], the code read from the tool (2026-11-16). Closes the
  /// return request for it, if GSU asked for it back.
  ///
  /// [conditionOnReturn] is required — condition monitoring is half the
  /// point of the loan record. Implementations write the return, update
  /// the tool's condition, and clear its holder atomically, setting the
  /// tool to [ToolStatus.inRepair] rather than available when it comes
  /// back in [ItemCondition.poor].
  Future<Result<void>> returnTool({
    required String loanId,
    required String scannedCode,
    required ItemCondition conditionOnReturn,
    required AuditActor actor,
    String? notes,
  });

  // --- requests (2026-11-16): an administrator asks, the technician
  // confirms by scanning the tool.

  /// Check-Out: asks [personnelId] to collect a tool on the shelf at
  /// [checkoutAt], for [purpose]. The tool is reserved for them until
  /// they confirm by scanning it, an administrator cancels, or the
  /// request lapses a day after [checkoutAt]. The technician is told.
  /// Returns the request's id.
  Future<Result<String>> requestCheckOut({
    required String toolId,
    required String personnelId,
    required DateTime checkoutAt,
    required String purpose,
    required AuditActor actor,
    DateTime? dueAt,
    String? message,
    String? workOrderId,
  });

  /// The technician a checkout was asked of confirms they have the tool,
  /// with [scannedCode] read from it. Opens the loan; the administrators
  /// are told. Refused for anyone else, for the wrong tool, and twice.
  Future<Result<ToolLoan>> confirmCheckOut({
    required String requestId,
    required String scannedCode,
    required AuditActor actor,
  });

  /// Check-In: asks the technician holding the tool on [loanId] to
  /// return it by [dueAt]. Nothing moves until they scan it back with
  /// [returnTool]. The technician is told. Returns the request's id.
  Future<Result<String>> requestReturn({
    required String loanId,
    required DateTime dueAt,
    required AuditActor actor,
    String? message,
  });

  /// Withdraws a request still waiting; a reserved tool goes back on the
  /// shelf. The technician is told.
  Future<Result<void>> cancelRequest({
    required String requestId,
    required AuditActor actor,
  });

  /// Requests still waiting for a technician, newest first: what the
  /// console's Tools tab monitors.
  Stream<Result<List<ToolRequest>>> watchOpenRequests();

  /// One technician's requests, newest first, live.
  Stream<Result<List<ToolRequest>>> watchRequestsFor(String personnelId);

  /// One tool's requests, newest first, live: its transaction history.
  Stream<Result<List<ToolRequest>>> watchRequestHistory(String toolId);

  /// Loans not yet returned, for the Admin "Active Tool Loans" tile
  /// (Figure 15).
  Stream<Result<List<ToolLoan>>> watchOpenLoans();

  /// One technician's outstanding loans, live, newest first — what the
  /// personnel app's Materials tab shows them holding (Objective 5.C).
  Stream<Result<List<ToolLoan>>> watchOpenLoansFor(String personnelId);

  /// Every loan made for one work order, newest first.
  Stream<Result<List<ToolLoan>>> watchLoansForWorkOrder(String workOrderId);

  /// One technician's outstanding loans — what they are personally
  /// accountable for right now.
  Future<Result<List<ToolLoan>>> getOpenLoansForPersonnel(String personnelId);

  /// One tool's loans, newest first, live.
  Stream<Result<List<ToolLoan>>> watchLoanHistory(String toolId);

  /// Full borrow history for one tool.
  Future<Result<List<ToolLoan>>> getLoanHistory(
    String toolId, {
    int limit = 50,
  });
}
