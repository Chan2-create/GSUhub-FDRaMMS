import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/utils/result.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../models/tool.dart';
import '../models/tool_loan.dart';

/// Abstract contract for the `tools` collection and its `tool_loans`
/// borrow history (manuscript §1.5 tool and equipment tracking).
///
/// Durable equipment, kept separate from consumable `inventory_items`: a
/// tool is checked out and checked back in, a consumable is deducted and
/// gone.
///
/// **Interface only** — implementation is 1.C.
abstract interface class ToolRepository {
  Future<Result<Tool>> getToolById(String id);

  Future<Result<Tool>> getToolByQrCode(String qrCode);

  Stream<Result<List<Tool>>> watchTools({ToolStatus? status});

  Future<Result<String>> createTool(Tool tool);

  Future<Result<void>> updateTool(Tool tool);

  /// Issues a tool to a technician.
  ///
  /// Writes the `tool_loans` record and flips the tool to
  /// [ToolStatus.borrowed] with its holder atomically — a tool marked
  /// available while physically out, or out with no recorded custodian,
  /// defeats the accountability requirement (§1.5).
  ///
  /// Fails if the tool is not [ToolStatus.available].
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required AuditActor borrower,
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

  /// Full borrow history for one tool.
  Future<Result<List<ToolLoan>>> getLoanHistory(
    String toolId, {
    int limit = 50,
  });
}
