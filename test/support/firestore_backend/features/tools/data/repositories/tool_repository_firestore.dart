import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/display_id.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/tools/data/models/tool.dart';
import 'package:gsuhub/features/tools/data/models/tool_draft.dart';
import 'package:gsuhub/features/tools/data/models/tool_loan.dart';
import 'package:gsuhub/features/tools/data/repositories/tool_repository.dart';

import '../../../../core/data/firestore_repository.dart';
import '../../../../core/data/qr_codes.dart';
import '../../../audit/data/repositories/audit_writes.dart';

/// Firestore-backed [ToolRepository].
///
/// Borrow and return are transactional because a tool's status and its
/// loan record must never disagree: a tool marked available while
/// physically in someone's bag, or out with no recorded custodian,
/// defeats the accountability requirement in manuscript §1.5.
/// Objective 1 moved this data to Supabase; the app uses [ToolRepositoryImpl]. This
/// Firestore version stays only as the backend of the widget-test harnesses
/// (test/support) until they are converted, and is not wired into the app.
class FirestoreToolRepository extends FirestoreRepository
    implements ToolRepository {
  const FirestoreToolRepository({required super.db, required super.guard});

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
  Stream<Result<Tool>> watchTool(String id) =>
      watchOne(path: _tools, id: id, convert: Tool.fromFirestore);

  @override
  Future<Result<String>> createTool({
    required ToolDraft draft,
    required AuditActor actor,
  }) async {
    if (draft.problem case final problem?) {
      return Result.failure(ValidationFailure(problem));
    }
    final clean = draft.normalized();
    if (await _taken(clean) case final failure?) return Result.failure(failure);

    return db.runTransaction<String>((transaction) async {
      final toolRef = collection(_tools).doc();
      transaction.set(toolRef, {
        ...clean.toFields(),
        'status': ToolStatus.available.id,
        'currentHolderId': null,
        'currentLoanId': null,
        'createdAt': FirestoreRepository.serverNow,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _tools,
        entityId: toolRef.id,
        description: 'Added ${clean.name} (${clean.toolCode}) to the tools',
      );
      return toolRef.id;
    });
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
    final clean = draft.normalized();
    if (await _taken(clean, exceptId: toolId) case final failure?) {
      return Result.failure(failure);
    }

    return db.runTransaction<void>((transaction) async {
      final toolRef = collection(_tools).doc(toolId);
      final snapshot = await transaction.get(toolRef);
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound('No tool $toolId');
      }
      final tool = Tool.fromFirestore(snapshot);
      final fields = clean.toFields();
      // A tool out on loan keeps the condition it left in; its return
      // records what it comes back in.
      if (tool.status == ToolStatus.borrowed) {
        fields['condition'] = tool.condition.id;
      }
      final before = snapshot.data() ?? const <String, dynamic>{};
      final changes = <String, dynamic>{
        for (final MapEntry(:key, :value) in fields.entries)
          if (before[key] != value) key: {'from': before[key], 'to': value},
      };
      if (changes.isEmpty) return;

      transaction.update(toolRef, {
        ...fields,
        'updatedAt': FirestoreRepository.serverNow,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.updated,
        entityType: _tools,
        entityId: toolId,
        description: 'Updated ${clean.name} (${clean.toolCode})',
        changes: changes,
      );
    });
  }

  @override
  Future<Result<void>> setToolStatus({
    required String toolId,
    required ToolStatus status,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final toolRef = collection(_tools).doc(toolId);
    final snapshot = await transaction.get(toolRef);
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('No tool $toolId');
    }
    final tool = Tool.fromFirestore(snapshot);
    if (tool.status == status) return;
    if (status == ToolStatus.borrowed) {
      throw FirestoreRepository.precondition('Check a tool out to lend it.');
    }
    if (tool.status == ToolStatus.borrowed) {
      throw FirestoreRepository.precondition(
        '${tool.name} is out with a technician; check it in first.',
      );
    }
    if (tool.status == ToolStatus.retired) {
      throw FirestoreRepository.precondition('${tool.name} is retired.');
    }

    transaction.update(toolRef, {
      'status': status.id,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: _tools,
      entityId: toolId,
      description: switch (status) {
        ToolStatus.inRepair => 'Sent ${tool.name} to repair',
        ToolStatus.retired => 'Retired ${tool.name}',
        _ => 'Brought ${tool.name} back from repair',
      },
      changes: {
        'status': {'from': tool.status.id, 'to': status.id},
      },
    );
  });

  /// A failure saying the draft's tool ID or code is taken, or null.
  Future<Failure?> _taken(ToolDraft draft, {String? exceptId}) async {
    final clash = await guard.call(() async {
      final sameId = await collection(_tools)
          .where('toolCode', isEqualTo: draft.toolCode)
          .limit(2)
          .get();
      if (sameId.docs.any((doc) => doc.id != exceptId)) {
        return 'Another tool already has the ID ${draft.toolCode}.';
      }
      final owner = await qrCodeOwner(db.raw, draft.qrCode, exceptId: exceptId);
      return owner == null
          ? null
          : 'The code ${draft.qrCode} is already on $owner.';
    });
    return clash.fold(
      (message) => message == null ? null : ValidationFailure(message),
      (failure) => failure,
    );
  }

  @override
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required AuditActor borrower,
    AuditActor? issuedBy,
    String? workOrderId,
    DateTime? expectedReturnAt,
  }) => db.runTransaction<ToolLoan>((transaction) async {
    final borrowedBy = borrower.id;
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
            '${tool.name} cannot be borrowed: it is '
            '${tool.status.label.toLowerCase()}.',
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
    final forWork = workOrderId == null
        ? ''
        : ' for ${DisplayId.workOrder(workOrderId)}';
    stageAuditEntry(
      transaction,
      db.raw,
      actor: issuedBy ?? borrower,
      action: AuditAction.created,
      entityType: _loans,
      entityId: loanRef.id,
      description: issuedBy == null
          ? 'Borrowed ${tool.name}$forWork'
          : 'Checked out ${tool.name} to ${borrower.name}$forWork',
      changes: {
        'toolId': toolId,
        'condition': tool.condition.id,
        'workOrderId': ?workOrderId,
      },
    );

    return loan;
  });

  @override
  Future<Result<void>> returnTool({
    required String loanId,
    required ItemCondition conditionOnReturn,
    required AuditActor actor,
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
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.updated,
      entityType: _loans,
      entityId: loanId,
      description:
          'Returned ${loan.toolName} in '
          '${conditionOnReturn.label.toLowerCase()} condition',
      changes: {
        'toolId': loan.toolId,
        'conditionOnBorrow': loan.conditionOnBorrow.id,
        'conditionOnReturn': conditionOnReturn.id,
      },
    );
  });

  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoansFor(String personnelId) =>
      // Two equality filters and a sort here: served without a composite
      // index on the live project.
      watchMany(
        query: collection(_loans)
            .where('borrowedBy', isEqualTo: personnelId)
            .where('returnedAt', isNull: true),
        convert: ToolLoan.fromFirestore,
      ).map((result) => result.map(_newestFirst));

  @override
  Stream<Result<List<ToolLoan>>> watchLoansForWorkOrder(String workOrderId) =>
      watchMany(
        query: collection(_loans).where('workOrderId', isEqualTo: workOrderId),
        convert: ToolLoan.fromFirestore,
      ).map((result) => result.map(_newestFirst));

  static List<ToolLoan> _newestFirst(List<ToolLoan> loans) =>
      [...loans]..sort((a, b) => b.borrowedAt.compareTo(a.borrowedAt));

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
  Stream<Result<List<ToolLoan>>> watchLoanHistory(String toolId) => watchMany(
    query: collection(_loans).where('toolId', isEqualTo: toolId),
    convert: ToolLoan.fromFirestore,
  ).map((result) => result.map(_newestFirst));

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
