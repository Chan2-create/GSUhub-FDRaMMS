import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../models/tool.dart';
import '../models/tool_loan.dart';
import 'tool_repository.dart';

/// Firestore-backed [ToolRepository].
///
/// Borrow and return are transactional because a tool's status and its
/// loan record must never disagree: a tool marked available while
/// physically in someone's bag, or out with no recorded custodian,
/// defeats the accountability requirement in manuscript §1.5.
class ToolRepositoryImpl extends FirestoreRepository implements ToolRepository {
  const ToolRepositoryImpl({required super.db, required super.guard});

  static const String _tools = FirestorePaths.tools;
  static const String _loans = FirestorePaths.toolLoans;

  @override
  Future<Result<Tool>> getToolById(String id) =>
      getOne(path: _tools, id: id, convert: Tool.fromFirestore);

  @override
  Future<Result<Tool>> getToolByQrCode(String qrCode) async {
    final matches = await getMany(
      query: collection(_tools).where('qrCode', isEqualTo: qrCode).limit(1),
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
  Stream<Result<List<Tool>>> watchTools({ToolStatus? status}) {
    Query<Map<String, dynamic>> query = collection(_tools);
    if (status != null) query = query.where('status', isEqualTo: status.id);
    return watchMany(
      query: query.orderBy('toolCode'),
      convert: Tool.fromFirestore,
    );
  }

  @override
  Future<Result<String>> createTool(Tool tool) =>
      add(path: _tools, data: tool.toFirestore());

  @override
  Future<Result<void>> updateTool(Tool tool) => updateDoc(
    path: _tools,
    id: tool.id,
    data: {...tool.toFirestore(), 'updatedAt': FirestoreRepository.serverNow},
  );

  @override
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required String borrowedBy,
    String? workOrderId,
    DateTime? expectedReturnAt,
  }) => db.runTransaction<ToolLoan>((transaction) async {
    final toolRef = collection(_tools).doc(toolId);
    final snapshot = await transaction.get(toolRef);

    if (!snapshot.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'No tool $toolId',
      );
    }

    final tool = Tool.fromFirestore(snapshot);
    if (!tool.status.isIssuable) {
      throw FirebaseException(
        plugin: 'gsuhub',
        code: 'failed-precondition',
        message:
            '${tool.name} cannot be issued: it is currently '
            '${tool.status.id}.',
      );
    }

    final borrowedAt = DateTime.now().toUtc();
    final loanRef = collection(_loans).doc();

    final loan = ToolLoan(
      id: loanRef.id,
      toolId: toolId,
      toolName: tool.name,
      borrowedBy: borrowedBy,
      workOrderId: workOrderId,
      borrowedAt: borrowedAt,
      expectedReturnAt: expectedReturnAt,
      conditionOnBorrow: tool.condition,
    );

    transaction.set(loanRef, loan.toFirestore());
    transaction.update(toolRef, {
      'status': ToolStatus.borrowed.id,
      'currentHolderId': borrowedBy,
      'currentLoanId': loanRef.id,
      'updatedAt': FirestoreRepository.serverNow,
    });

    return loan;
  });

  @override
  Future<Result<void>> returnTool({
    required String loanId,
    required ItemCondition conditionOnReturn,
    String? notes,
  }) => db.runTransaction<void>((transaction) async {
    final loanRef = collection(_loans).doc(loanId);
    final loanSnapshot = await transaction.get(loanRef);

    if (!loanSnapshot.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'No tool loan $loanId',
      );
    }

    final loan = ToolLoan.fromFirestore(loanSnapshot);
    if (loan.isReturned) {
      throw FirebaseException(
        plugin: 'gsuhub',
        code: 'failed-precondition',
        message: '${loan.toolName} has already been returned.',
      );
    }

    final toolRef = collection(_tools).doc(loan.toolId);
    // Read before any write, per Firestore's transaction rules.
    await transaction.get(toolRef);

    transaction.update(loanRef, {
      'returnedAt': FirestoreRepository.serverNow,
      'conditionOnReturn': conditionOnReturn.id,
      'notes': ?notes,
    });

    // A tool that comes back in poor condition goes to repair rather than
    // straight back onto the available shelf — otherwise the next
    // technician is issued something known to be broken.
    transaction.update(toolRef, {
      'status': conditionOnReturn == ItemCondition.poor
          ? ToolStatus.inRepair.id
          : ToolStatus.available.id,
      'condition': conditionOnReturn.id,
      'currentHolderId': null,
      'currentLoanId': null,
      'updatedAt': FirestoreRepository.serverNow,
    });
  });

  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoans() => watchMany(
    query: collection(_loans)
        .where('returnedAt', isNull: true)
        .orderBy('borrowedAt', descending: true),
    convert: ToolLoan.fromFirestore,
  );

  @override
  Future<Result<List<ToolLoan>>> getOpenLoansForPersonnel(String personnelId) =>
      getMany(
        query: collection(_loans)
            .where('borrowedBy', isEqualTo: personnelId)
            .where('returnedAt', isNull: true)
            .orderBy('borrowedAt', descending: true),
        convert: ToolLoan.fromFirestore,
      );

  @override
  Future<Result<List<ToolLoan>>> getLoanHistory(
    String toolId, {
    int limit = 50,
  }) => getMany(
    query: collection(_loans)
        .where('toolId', isEqualTo: toolId)
        .orderBy('borrowedAt', descending: true)
        .limit(limit),
    convert: ToolLoan.fromFirestore,
  );
}
