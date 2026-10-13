import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/tool.dart';
import '../models/tool_draft.dart';
import '../models/tool_loan.dart';

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

  /// Issues a tool to a technician.
  ///
  /// Writes the `tool_loans` record and flips the tool to
  /// [ToolStatus.borrowed] with its holder atomically — a tool marked
  /// available while physically out, or out with no recorded custodian,
  /// defeats the accountability requirement (§1.5).
  ///
  /// Fails if the tool is not [ToolStatus.available].
  ///
  /// [issuedBy] is the administrator checking it out to [borrower] from
  /// the console (Figure 15's Check Out); null when the technician
  /// borrows it themselves.
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required AuditActor borrower,
    AuditActor? issuedBy,
    String? workOrderId,
    DateTime? expectedReturnAt,
  });

  /// Closes out a loan.
  ///
  /// [conditionOnReturn] is required — condition monitoring is half the
  /// point of the loan record. Implementations write the return, update
  /// the tool's condition, and clear its holder atomically, setting the
  /// tool to [ToolStatus.inRepair] rather than available when it comes
  /// back in [ItemCondition.poor].
  Future<Result<void>> returnTool({
    required String loanId,
    required ItemCondition conditionOnReturn,
    required AuditActor actor,
    String? notes,
  });

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
