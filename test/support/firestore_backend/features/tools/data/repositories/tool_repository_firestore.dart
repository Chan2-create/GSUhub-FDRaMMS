import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/table_names.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/display_id.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/tools/data/models/tool.dart';
import 'package:gsuhub/features/tools/data/models/tool_draft.dart';
import 'package:gsuhub/features/tools/data/models/tool_loan.dart';
import 'package:gsuhub/features/tools/data/models/tool_request.dart';
import 'package:gsuhub/features/tools/data/repositories/tool_repository.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/firestore_records.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/data/qr_codes.dart';
import '../../../audit/data/repositories/audit_writes.dart';
import '../../../notifications/data/repositories/notification_writes.dart';

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

  static const String _tools = TableNames.tools;
  static const String _loans = TableNames.toolLoans;
  static const String _requests = TableNames.toolRequests;

  @override
  Future<Result<Tool>> getToolById(String id) async => _present(
    await getOne(path: _tools, id: id, convert: fromDoc(Tool.fromRecord)),
  );

  @override
  Future<Result<Tool>> getToolByQrCode(String qrCode) async {
    final matches = await getMany(
      query: collection(_tools).where('qrCode', isEqualTo: qrCode),
      convert: fromDoc(Tool.fromRecord),
    );

    return matches.fold(
      (list) => switch (list.where((tool) => !tool.isDeleted)) {
        final present when present.isNotEmpty => Result.success(present.first),
        _ => const Result<Tool>.failure(
          NotFoundFailure('No registered tool matches that QR code.'),
        ),
      },
      Result.failure,
    );
  }

  @override
  Stream<Result<List<Tool>>> watchTools({ToolStatus? status}) {
    Query<Map<String, dynamic>> query = collection(_tools);
    if (status != null) query = query.where('status', isEqualTo: status.id);
    return watchMany(
      query: query.orderBy('toolCode'),
      convert: fromDoc(Tool.fromRecord),
    ).map(
      (result) =>
          result.map((tools) => tools.where((t) => !t.isDeleted).toList()),
    );
  }

  @override
  Stream<Result<Tool>> watchTool(String id) => watchOne(
    path: _tools,
    id: id,
    convert: fromDoc(Tool.fromRecord),
  ).map(_present);

  /// As delete_tool: refused while the tool is out on loan.
  @override
  Future<Result<void>> deleteTool({
    required String toolId,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final toolRef = collection(_tools).doc(toolId);
    final snapshot = await transaction.get(toolRef);
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound(
        'This tool is no longer in the inventory.',
      );
    }
    final tool = fromDoc(Tool.fromRecord)(snapshot);
    if (tool.isDeleted) return;
    if (tool.status == ToolStatus.borrowed) {
      throw FirestoreRepository.precondition(
        '${tool.name} is on loan. Check it in first.',
      );
    }

    transaction.update(toolRef, {
      'deletedAt': FirestoreRepository.serverNow,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.deleted,
      entityType: _tools,
      entityId: toolId,
      description: 'Deleted ${tool.name} (${tool.toolCode}) from the tools',
    );
  });

  /// A deleted tool reads as gone.
  static Result<Tool> _present(Result<Tool> result) => switch (result) {
    Success(:final value) when value.isDeleted => const Result.failure(
      NotFoundFailure('This tool is no longer in the inventory.'),
    ),
    _ => result,
  };

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
      final tool = fromDoc(Tool.fromRecord)(snapshot);
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
    final tool = fromDoc(Tool.fromRecord)(snapshot);
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

  // --- hand-overs, confirmed with the code scanned from the tool
  // (2026-11-16). The refusals read as the database's do.

  /// The tool a scanned code is on, read before a transaction (which
  /// cannot query): to say which tool was scanned when it is the wrong one.
  Future<Tool?> _toolByCode(String scannedCode) async {
    final code = scannedCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final found = await collection(_tools)
        .where('qrCode', isEqualTo: code)
        .get();
    for (final doc in found.docs) {
      final tool = fromDoc(Tool.fromRecord)(doc);
      if (!tool.isDeleted) return tool;
    }
    return null;
  }

  static void _requireScanned(Tool tool, String scannedCode, Tool? scanned) {
    final code = scannedCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw FirestoreRepository.precondition(
        'Scan the QR code on ${tool.name} (${tool.toolCode}).',
      );
    }
    if (code == tool.qrCode.toUpperCase()) return;
    if (scanned != null) {
      throw FirestoreRepository.precondition(
        'That is ${scanned.name} (${scanned.toolCode}), not ${tool.name} '
        '(${tool.toolCode}). Scan the QR code on ${tool.name}.',
      );
    }
    throw FirestoreRepository.precondition(
      'That code is not on ${tool.name} (${tool.toolCode}). Scan the QR code '
      'on ${tool.name}.',
    );
  }

  static FirebaseException _denied(String message) => FirebaseException(
    plugin: 'gsuhub',
    code: 'permission-denied',
    message: message,
  );

  /// The active administrators, to tell (read before a transaction).
  Future<List<String>> _admins() async {
    final found = await db.raw
        .collection(TableNames.users)
        .where('role', isEqualTo: 'admin')
        .get();
    return [
      for (final doc in found.docs)
        if (doc.data()['accountStatus'] == 'active') doc.id,
    ];
  }

  static String _when(DateTime at) =>
      DateFormat('MMM d, y h:mm a').format(at.toLocal());

  Future<String> _nameOf(Transaction transaction, String userId) async {
    final user = await transaction.get(
      db.raw.collection(TableNames.users).doc(userId),
    );
    return (user.data()?['fullName'] as String?) ?? 'A technician';
  }

  /// The request waiting on [toolId], if any.
  Future<ToolRequest?> _pendingFor(String toolId) async {
    final found = await collection(_requests)
        .where('toolId', isEqualTo: toolId)
        .where('status', isEqualTo: ToolRequestStatus.pending.id)
        .get();
    return found.docs.isEmpty
        ? null
        : fromDoc(ToolRequest.fromRecord)(found.docs.first);
  }

  @override
  Future<Result<ToolLoan>> borrowTool({
    required String toolId,
    required String scannedCode,
    required AuditActor borrower,
    String? workOrderId,
  }) async {
    final scanned = await _toolByCode(scannedCode);
    final pending = await _pendingFor(toolId);
    return db.runTransaction<ToolLoan>((transaction) async {
      final borrowedBy = borrower.id;
      final toolRef = collection(_tools).doc(toolId);
      final snapshot = await transaction.get(toolRef);

      if (!snapshot.exists) {
        throw FirestoreRepository.notFound('No tool $toolId');
      }

      final tool = fromDoc(Tool.fromRecord)(snapshot);
      if (tool.isDeleted) {
        throw FirestoreRepository.notFound('${tool.name} has been deleted.');
      }
      _requireScanned(tool, scannedCode, scanned);
      if (tool.status == ToolStatus.reserved) {
        if (pending?.personnelId == borrowedBy) {
          throw FirestoreRepository.precondition(
            'GSU has checked ${tool.name} out to you. Confirm that request '
            'instead.',
          );
        }
        throw FirestoreRepository.precondition(
          '${tool.name} is reserved for another technician.',
        );
      }
      if (!tool.status.isIssuable) {
        throw FirestoreRepository.precondition(
          '${tool.name} cannot be borrowed: it is '
          '${tool.status.label.toLowerCase()}.',
        );
      }

      final loanRef = collection(_loans).doc();
      final loan = ToolLoan(
        id: loanRef.id,
        toolId: toolId,
        toolName: tool.name,
        borrowedBy: borrowedBy,
        workOrderId: workOrderId,
        borrowedAt: DateTime.now().toUtc(),
        conditionOnBorrow: tool.condition,
      );

      transaction.set(loanRef, loan.toFields().forFirestore);
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
        actor: borrower,
        action: AuditAction.created,
        entityType: _loans,
        entityId: loanRef.id,
        description: 'Borrowed ${tool.name}$forWork, confirmed by scanning it',
        changes: {
          'toolId': toolId,
          'condition': tool.condition.id,
          'workOrderId': ?workOrderId,
        },
      );

      return loan;
    });
  }

  @override
  Future<Result<void>> returnTool({
    required String loanId,
    required String scannedCode,
    required ItemCondition conditionOnReturn,
    required AuditActor actor,
    String? notes,
  }) async {
    final loanDoc = await collection(_loans).doc(loanId).get();
    final toolId = loanDoc.data()?['toolId'] as String?;
    final scanned = await _toolByCode(scannedCode);
    final request = toolId == null ? null : await _pendingFor(toolId);
    final admins = await _admins();
    return db.runTransaction<void>((transaction) async {
      final loanRef = collection(_loans).doc(loanId);
      final loanSnapshot = await transaction.get(loanRef);

      if (!loanSnapshot.exists) {
        throw FirestoreRepository.notFound('No tool loan $loanId');
      }

      final loan = fromDoc(ToolLoan.fromRecord)(loanSnapshot);
      if (loan.borrowedBy != actor.id) {
        throw _denied(
          'This tool is on loan to another technician; only they can return '
          'it.',
        );
      }
      if (loan.isReturned) {
        throw FirestoreRepository.precondition(
          '${loan.toolName} has already been returned.',
        );
      }

      final toolRef = collection(_tools).doc(loan.toolId);
      final tool = fromDoc(Tool.fromRecord)(await transaction.get(toolRef));
      _requireScanned(tool, scannedCode, scanned);
      final returnRequest =
          request != null &&
              request.kind == ToolRequestKind.checkIn &&
              request.loanId == loanId
          ? request
          : null;
      final name = await _nameOf(transaction, actor.id);

      transaction.update(loanRef, {
        'returnedAt': FirestoreRepository.serverNow,
        'conditionOnReturn': conditionOnReturn.id,
        'notes': ?notes,
      });

      // A tool that comes back in poor condition goes to repair rather
      // than straight back onto the available shelf — otherwise the next
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
      if (returnRequest != null) {
        transaction.update(collection(_requests).doc(returnRequest.id), {
          'status': ToolRequestStatus.confirmed.id,
          'confirmedAt': Timestamp.fromDate(DateTime.now().toUtc()),
        });
      }
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.updated,
        entityType: _loans,
        entityId: loanId,
        description:
            'Returned ${loan.toolName} in '
            '${conditionOnReturn.label.toLowerCase()} condition, confirmed '
            'by scanning it',
        changes: {
          'toolId': loan.toolId,
          'conditionOnBorrow': loan.conditionOnBorrow.id,
          'conditionOnReturn': conditionOnReturn.id,
        },
      );
      for (final admin in admins) {
        stageNotification(
          transaction,
          db.raw,
          recipientId: admin,
          type: NotificationType.toolReturned,
          title: '$name returned ${tool.name}',
          body:
              '$name scanned ${tool.name} (${tool.toolCode}) and confirmed '
              'returning it, in ${conditionOnReturn.label.toLowerCase()} '
              'condition.',
          relatedEntityType: returnRequest == null ? _loans : _requests,
          relatedEntityId: returnRequest?.id ?? loanId,
        );
      }
    });
  }

  // --- requests (2026-11-16)

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
  }) => db.runTransaction<String>((transaction) async {
    if (purpose.trim().isEmpty) {
      throw FirestoreRepository.precondition('Say what the tool is for.');
    }
    if (dueAt != null && !dueAt.isAfter(checkoutAt)) {
      throw FirestoreRepository.precondition(
        'The expected return must be after the checkout.',
      );
    }
    final toolRef = collection(_tools).doc(toolId);
    final snapshot = await transaction.get(toolRef);
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound(
        'This tool is no longer in the inventory.',
      );
    }
    final tool = fromDoc(Tool.fromRecord)(snapshot);
    if (tool.status != ToolStatus.available) {
      throw FirestoreRepository.precondition(
        '${tool.name} cannot be checked out: it is '
        '${tool.status.label.toLowerCase()}.',
      );
    }
    final name = await _nameOf(transaction, personnelId);
    final requestRef = collection(_requests).doc();
    final day = checkoutAt.add(const Duration(hours: 24));
    final trimmed = message?.trim();
    final request = ToolRequest(
      id: requestRef.id,
      kind: ToolRequestKind.checkOut,
      toolId: toolId,
      toolName: tool.name,
      toolCode: tool.toolCode,
      qrCode: tool.qrCode,
      personnelId: personnelId,
      requestedBy: actor.id,
      requestedAt: DateTime.now().toUtc(),
      status: ToolRequestStatus.pending,
      checkoutAt: checkoutAt.toUtc(),
      dueAt: dueAt?.toUtc(),
      expiresAt: (dueAt != null && dueAt.isBefore(day) ? dueAt : day).toUtc(),
      purpose: purpose.trim(),
      message: (trimmed?.isEmpty ?? true) ? null : trimmed,
      workOrderId: workOrderId,
    );
    transaction.set(requestRef, request.toFields().forFirestore);
    transaction.update(toolRef, {
      'status': ToolStatus.reserved.id,
      'updatedAt': FirestoreRepository.serverNow,
    });
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.created,
      entityType: _requests,
      entityId: requestRef.id,
      description: 'Asked $name to collect ${tool.name} (${tool.toolCode})',
      changes: {
        'toolId': toolId,
        'kind': 'checkOut',
        'personnelId': personnelId,
      },
    );
    stageNotification(
      transaction,
      db.raw,
      recipientId: personnelId,
      type: NotificationType.toolCheckoutRequested,
      title: 'Collect ${tool.name} (${tool.toolCode})',
      body: [
        'GSU has checked out ${tool.name} (${tool.toolCode}) to you.',
        'Collect it on ${_when(checkoutAt)}.',
        'Purpose: ${purpose.trim()}.',
        ?request.message,
        'When you have it, scan its QR code in GSUhub to confirm.',
      ].join(' '),
      relatedEntityType: _requests,
      relatedEntityId: requestRef.id,
    );
    return requestRef.id;
  });

  @override
  Future<Result<ToolLoan>> confirmCheckOut({
    required String requestId,
    required String scannedCode,
    required AuditActor actor,
  }) async {
    final scanned = await _toolByCode(scannedCode);
    final admins = await _admins();
    return db.runTransaction<ToolLoan>((transaction) async {
      final requestRef = collection(_requests).doc(requestId);
      final snapshot = await transaction.get(requestRef);
      if (!snapshot.exists) {
        throw FirestoreRepository.notFound(
          'This checkout request is no longer there.',
        );
      }
      final request = fromDoc(ToolRequest.fromRecord)(snapshot);
      if (request.personnelId != actor.id) {
        throw _denied(
          'This checkout is for another technician; only they can confirm '
          'it.',
        );
      }
      switch (request.statusAt(DateTime.now().toUtc())) {
        case ToolTransactionStatus.borrowed:
          throw FirestoreRepository.precondition(
            'You have already confirmed receiving ${request.toolName}.',
          );
        case ToolTransactionStatus.cancelled:
          throw FirestoreRepository.precondition(
            'GSU cancelled this checkout of ${request.toolName}.',
          );
        case ToolTransactionStatus.expired:
          throw FirestoreRepository.precondition(
            'This checkout of ${request.toolName} has lapsed. Ask GSU to '
            'send it again.',
          );
        default:
      }
      final toolRef = collection(_tools).doc(request.toolId);
      final tool = fromDoc(Tool.fromRecord)(await transaction.get(toolRef));
      _requireScanned(tool, scannedCode, scanned);
      final name = await _nameOf(transaction, actor.id);

      final loanRef = collection(_loans).doc();
      final loan = ToolLoan(
        id: loanRef.id,
        toolId: tool.id,
        toolName: tool.name,
        borrowedBy: actor.id,
        workOrderId: request.workOrderId,
        borrowedAt: DateTime.now().toUtc(),
        expectedReturnAt: request.dueAt,
        conditionOnBorrow: tool.condition,
      );
      transaction.set(loanRef, loan.toFields().forFirestore);
      transaction.update(toolRef, {
        'status': ToolStatus.borrowed.id,
        'currentHolderId': actor.id,
        'currentLoanId': loanRef.id,
        'updatedAt': FirestoreRepository.serverNow,
      });
      transaction.update(requestRef, {
        'status': ToolRequestStatus.confirmed.id,
        'confirmedAt': Timestamp.fromDate(DateTime.now().toUtc()),
        'loanId': loanRef.id,
      });
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _loans,
        entityId: loanRef.id,
        description:
            'Received ${tool.name} (${tool.toolCode}), confirmed by scanning '
            'it',
        changes: {'toolId': tool.id, 'requestId': requestId},
      );
      for (final admin in admins) {
        stageNotification(
          transaction,
          db.raw,
          recipientId: admin,
          type: NotificationType.toolCheckoutConfirmed,
          title: '$name received ${tool.name}',
          body:
              '$name scanned ${tool.name} (${tool.toolCode}) and confirmed '
              'receiving it.',
          relatedEntityType: _requests,
          relatedEntityId: requestId,
        );
      }
      return loan;
    });
  }

  @override
  Future<Result<String>> requestReturn({
    required String loanId,
    required DateTime dueAt,
    required AuditActor actor,
    String? message,
  }) async {
    final loanDoc = await collection(_loans).doc(loanId).get();
    final toolId = loanDoc.data()?['toolId'] as String?;
    final pending = toolId == null ? null : await _pendingFor(toolId);
    return db.runTransaction<String>((transaction) async {
      final loanSnapshot = await transaction.get(
        collection(_loans).doc(loanId),
      );
      if (!loanSnapshot.exists) {
        throw FirestoreRepository.notFound('No tool loan $loanId');
      }
      final loan = fromDoc(ToolLoan.fromRecord)(loanSnapshot);
      if (loan.isReturned) {
        throw FirestoreRepository.precondition(
          '${loan.toolName} has already been returned.',
        );
      }
      if (!dueAt.isAfter(DateTime.now())) {
        throw FirestoreRepository.precondition(
          'Pick a return date and time that has not passed.',
        );
      }
      if (pending != null) {
        throw FirestoreRepository.precondition(
          'A return of ${loan.toolName} is already requested.',
        );
      }
      final tool = fromDoc(Tool.fromRecord)(
        await transaction.get(collection(_tools).doc(loan.toolId)),
      );
      final name = await _nameOf(transaction, loan.borrowedBy);
      final requestRef = collection(_requests).doc();
      final trimmed = message?.trim();
      final request = ToolRequest(
        id: requestRef.id,
        kind: ToolRequestKind.checkIn,
        toolId: tool.id,
        toolName: tool.name,
        toolCode: tool.toolCode,
        qrCode: tool.qrCode,
        personnelId: loan.borrowedBy,
        requestedBy: actor.id,
        requestedAt: DateTime.now().toUtc(),
        status: ToolRequestStatus.pending,
        dueAt: dueAt.toUtc(),
        message: (trimmed?.isEmpty ?? true) ? null : trimmed,
        workOrderId: loan.workOrderId,
        loanId: loanId,
      );
      transaction.set(requestRef, request.toFields().forFirestore);
      stageAuditEntry(
        transaction,
        db.raw,
        actor: actor,
        action: AuditAction.created,
        entityType: _requests,
        entityId: requestRef.id,
        description:
            'Asked $name to return ${tool.name} (${tool.toolCode}) by '
            '${_when(dueAt)}',
        changes: {'toolId': tool.id, 'kind': 'checkIn', 'loanId': loanId},
      );
      stageNotification(
        transaction,
        db.raw,
        recipientId: loan.borrowedBy,
        type: NotificationType.toolReturnRequested,
        title: 'Return ${tool.name} (${tool.toolCode})',
        body: [
          'GSU asks you to return ${tool.name} (${tool.toolCode}) by '
              '${_when(dueAt)}.',
          ?request.message,
          'When you hand it back, scan its QR code in GSUhub to confirm the '
              'return.',
        ].join(' '),
        relatedEntityType: _requests,
        relatedEntityId: requestRef.id,
      );
      return requestRef.id;
    });
  }

  @override
  Future<Result<void>> cancelRequest({
    required String requestId,
    required AuditActor actor,
  }) => db.runTransaction<void>((transaction) async {
    final requestRef = collection(_requests).doc(requestId);
    final snapshot = await transaction.get(requestRef);
    if (!snapshot.exists) {
      throw FirestoreRepository.notFound('This request is no longer there.');
    }
    final request = fromDoc(ToolRequest.fromRecord)(snapshot);
    if (!request.isPending) {
      final state = switch (request.status) {
        ToolRequestStatus.confirmed => 'confirmed',
        ToolRequestStatus.cancelled => 'cancelled',
        _ => 'lapsed',
      };
      throw FirestoreRepository.precondition('This request is already $state.');
    }
    final toolRef = collection(_tools).doc(request.toolId);
    final tool = fromDoc(Tool.fromRecord)(await transaction.get(toolRef));
    transaction.update(requestRef, {
      'status': ToolRequestStatus.cancelled.id,
      'closedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      'closedBy': actor.id,
    });
    if (request.kind == ToolRequestKind.checkOut &&
        tool.status == ToolStatus.reserved) {
      transaction.update(toolRef, {
        'status': ToolStatus.available.id,
        'updatedAt': FirestoreRepository.serverNow,
      });
    }
    final checkOut = request.kind == ToolRequestKind.checkOut;
    final what = checkOut ? 'checkout' : 'return';
    stageAuditEntry(
      transaction,
      db.raw,
      actor: actor,
      action: AuditAction.statusChanged,
      entityType: _requests,
      entityId: requestId,
      description:
          'Cancelled the $what of ${request.toolName} (${request.toolCode})',
    );
    stageNotification(
      transaction,
      db.raw,
      recipientId: request.personnelId,
      type: NotificationType.toolRequestCancelled,
      title: 'Cancelled: $what of ${request.toolName}',
      body:
          'GSU cancelled the request to ${checkOut ? 'collect' : 'return'} '
          '${request.toolName} (${request.toolCode}).',
      relatedEntityType: _requests,
      relatedEntityId: requestId,
    );
  });

  @override
  Stream<Result<List<ToolRequest>>> watchOpenRequests() => watchMany(
    query: collection(_requests)
        .where('status', isEqualTo: ToolRequestStatus.pending.id),
    convert: fromDoc(ToolRequest.fromRecord),
  ).map((result) => result.map(_requestsNewestFirst));

  @override
  Stream<Result<List<ToolRequest>>> watchRequestsFor(String personnelId) =>
      watchMany(
        query: collection(_requests)
            .where('personnelId', isEqualTo: personnelId),
        convert: fromDoc(ToolRequest.fromRecord),
      ).map((result) => result.map(_requestsNewestFirst));

  @override
  Stream<Result<List<ToolRequest>>> watchRequestHistory(String toolId) =>
      watchMany(
        query: collection(_requests).where('toolId', isEqualTo: toolId),
        convert: fromDoc(ToolRequest.fromRecord),
      ).map((result) => result.map(_requestsNewestFirst));

  static List<ToolRequest> _requestsNewestFirst(List<ToolRequest> requests) =>
      [...requests]..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoansFor(String personnelId) =>
      // Two equality filters and a sort here: served without a composite
      // index on the live project.
      watchMany(
        query: collection(_loans)
            .where('borrowedBy', isEqualTo: personnelId)
            .where('returnedAt', isNull: true),
        convert: fromDoc(ToolLoan.fromRecord),
      ).map((result) => result.map(_newestFirst));

  @override
  Stream<Result<List<ToolLoan>>> watchLoansForWorkOrder(String workOrderId) =>
      watchMany(
        query: collection(_loans).where('workOrderId', isEqualTo: workOrderId),
        convert: fromDoc(ToolLoan.fromRecord),
      ).map((result) => result.map(_newestFirst));

  static List<ToolLoan> _newestFirst(List<ToolLoan> loans) =>
      [...loans]..sort((a, b) => b.borrowedAt.compareTo(a.borrowedAt));

  @override
  Stream<Result<List<ToolLoan>>> watchOpenLoans() => watchMany(
    query: collection(_loans)
        .where('returnedAt', isNull: true)
        .orderBy('borrowedAt', descending: true),
    convert: fromDoc(ToolLoan.fromRecord),
  );

  @override
  Future<Result<List<ToolLoan>>> getOpenLoansForPersonnel(String personnelId) =>
      getMany(
        query: collection(_loans)
            .where('borrowedBy', isEqualTo: personnelId)
            .where('returnedAt', isNull: true)
            .orderBy('borrowedAt', descending: true),
        convert: fromDoc(ToolLoan.fromRecord),
      );

  @override
  Stream<Result<List<ToolLoan>>> watchLoanHistory(String toolId) => watchMany(
    query: collection(_loans).where('toolId', isEqualTo: toolId),
    convert: fromDoc(ToolLoan.fromRecord),
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
    convert: fromDoc(ToolLoan.fromRecord),
  );
}
