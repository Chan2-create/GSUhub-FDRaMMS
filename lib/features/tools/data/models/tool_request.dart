import '../../../../core/data/data_record.dart';
import '../../../../core/utils/record_converters.dart';

/// What an administrator asked of a technician about a tool (2026-11-16).
enum ToolRequestKind {
  /// Collect a tool from GSU: Check Out.
  checkOut,

  /// Hand a tool back to GSU: Check In.
  checkIn;

  /// The value persisted on `tool_requests.kind`.
  String get id => name;

  /// How the console and the app name the transaction.
  String get label => switch (this) {
    ToolRequestKind.checkOut => 'Check-Out',
    ToolRequestKind.checkIn => 'Check-In',
  };

  static ToolRequestKind fromId(String id) => ToolRequestKind.values.firstWhere(
    (kind) => kind.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'id', 'Unknown ToolRequestKind'),
  );
}

/// How a request stands in the database.
enum ToolRequestStatus {
  /// Waiting for the technician to scan the tool and confirm.
  pending,

  /// Confirmed by the technician, with the tool scanned.
  confirmed,

  /// Withdrawn by an administrator.
  cancelled,

  /// A checkout not collected in time; the tool went back on the shelf.
  expired;

  /// The value persisted on `tool_requests.status`.
  String get id => name;

  static ToolRequestStatus fromId(String id) =>
      ToolRequestStatus.values.firstWhere(
        (status) => status.id == id,
        orElse: () =>
            throw ArgumentError.value(id, 'id', 'Unknown ToolRequestStatus'),
      );
}

/// A transaction's status as people read it, the table Chris's brief of
/// 2026-11-16 sets out: three for a checkout, three for a return, and the
/// two endings either can have.
enum ToolTransactionStatus {
  /// Check-Out: asked; the technician has not confirmed receipt.
  pendingConfirmation('Pending Confirmation'),

  /// Check-Out: the technician scanned the tool and confirmed receipt.
  borrowed('Borrowed'),

  /// Check-In: asked back; the technician has not confirmed the return.
  awaitingReturn('Awaiting Return'),

  /// Check-In: the requested time passed without the return confirmed.
  overdue('Overdue'),

  /// Check-In: the technician scanned the tool and confirmed the return.
  returned('Returned'),

  /// Either: withdrawn by an administrator.
  cancelled('Cancelled'),

  /// Check-Out: not collected in time; the tool went back on the shelf.
  expired('Expired');

  const ToolTransactionStatus(this.label);

  final String label;

  /// Whether the technician still has something to do.
  bool get isOpen => switch (this) {
    pendingConfirmation || awaitingReturn || overdue => true,
    _ => false,
  };
}

/// A `tool_requests` row: one Check-Out or Check-In an administrator
/// started, kept for good as the history of the tool's transactions.
///
/// Nothing about the tool changes when it is asked: a checkout reserves
/// the tool, and it becomes the technician's (a [ToolLoan]) only when they
/// scan it and confirm; a return closes the loan only when they scan it
/// back. The tool's name, ID and code are kept as they were when asked, so
/// the history reads the same after the tool is renamed or deleted.
class ToolRequest {
  ToolRequest({
    required this.id,
    required this.kind,
    required this.toolId,
    required this.toolName,
    required this.toolCode,
    required this.qrCode,
    required this.personnelId,
    required this.requestedBy,
    required this.requestedAt,
    required this.status,
    this.checkoutAt,
    this.dueAt,
    this.expiresAt,
    this.purpose,
    this.message,
    this.workOrderId,
    this.loanId,
    this.confirmedAt,
    this.closedAt,
    this.closedBy,
  }) {
    RecordConverters.validateNotBlank(toolId, 'toolId');
    RecordConverters.validateNotBlank(personnelId, 'personnelId');
    if (kind == ToolRequestKind.checkIn && (loanId == null || dueAt == null)) {
      throw ArgumentError.value(
        loanId,
        'loanId',
        'A return request names the loan to close and when',
      );
    }
  }

  factory ToolRequest.fromRecord(DataRecord record) {
    final data = record.fields;
    return ToolRequest(
      id: record.id,
      kind: RecordConverters.requireEnum(data, 'kind', ToolRequestKind.fromId),
      toolId: RecordConverters.require<String>(data, 'toolId'),
      toolName: RecordConverters.require<String>(data, 'toolName'),
      toolCode: RecordConverters.require<String>(data, 'toolCode'),
      qrCode: RecordConverters.require<String>(data, 'qrCode'),
      personnelId: RecordConverters.require<String>(data, 'personnelId'),
      requestedBy: RecordConverters.require<String>(data, 'requestedBy'),
      requestedAt: RecordConverters.requireDate(data, 'requestedAt'),
      status: RecordConverters.requireEnum(
        data,
        'status',
        ToolRequestStatus.fromId,
      ),
      checkoutAt: RecordConverters.optionalDate(data, 'checkoutAt'),
      dueAt: RecordConverters.optionalDate(data, 'dueAt'),
      expiresAt: RecordConverters.optionalDate(data, 'expiresAt'),
      purpose: RecordConverters.optional<String>(data, 'purpose'),
      message: RecordConverters.optional<String>(data, 'message'),
      workOrderId: RecordConverters.optional<String>(data, 'workOrderId'),
      loanId: RecordConverters.optional<String>(data, 'loanId'),
      confirmedAt: RecordConverters.optionalDate(data, 'confirmedAt'),
      closedAt: RecordConverters.optionalDate(data, 'closedAt'),
      closedBy: RecordConverters.optional<String>(data, 'closedBy'),
    );
  }

  final String id;
  final ToolRequestKind kind;
  final String toolId;
  final String toolName;
  final String toolCode;

  /// The code on the tool's label when it was asked: the one to scan.
  final String qrCode;

  /// The technician asked to collect or return it.
  final String personnelId;

  /// The administrator who asked.
  final String requestedBy;

  final DateTime requestedAt;
  final ToolRequestStatus status;

  /// Check-Out: when the technician is to collect it.
  final DateTime? checkoutAt;

  /// Check-Out: when it is expected back. Check-In: when it is to be back.
  final DateTime? dueAt;

  /// Check-Out: when an uncollected request lapses.
  final DateTime? expiresAt;

  /// Check-Out: what the tool is for.
  final String? purpose;

  /// The administrator's instructions or message.
  final String? message;

  final String? workOrderId;

  /// Check-Out: the loan its confirmation opened. Check-In: the loan to
  /// close.
  final String? loanId;

  /// When the technician scanned the tool and confirmed.
  final DateTime? confirmedAt;

  /// When it was cancelled or lapsed.
  final DateTime? closedAt;

  /// The administrator who cancelled it; null when it lapsed.
  final String? closedBy;

  bool get isPending => status == ToolRequestStatus.pending;

  /// How it stands at [now]. Overdue and lapsed are read from the clock,
  /// so they show the moment they are true, before the database's sweep
  /// has marked them.
  ToolTransactionStatus statusAt(DateTime now) => switch ((kind, status)) {
    (ToolRequestKind.checkOut, ToolRequestStatus.pending) =>
      expiresAt != null && !now.isBefore(expiresAt!)
          ? ToolTransactionStatus.expired
          : ToolTransactionStatus.pendingConfirmation,
    (ToolRequestKind.checkOut, ToolRequestStatus.confirmed) =>
      ToolTransactionStatus.borrowed,
    (ToolRequestKind.checkIn, ToolRequestStatus.pending) =>
      dueAt != null && now.isAfter(dueAt!)
          ? ToolTransactionStatus.overdue
          : ToolTransactionStatus.awaitingReturn,
    (ToolRequestKind.checkIn, ToolRequestStatus.confirmed) =>
      ToolTransactionStatus.returned,
    (_, ToolRequestStatus.cancelled) => ToolTransactionStatus.cancelled,
    (_, ToolRequestStatus.expired) => ToolTransactionStatus.expired,
  };

  Map<String, dynamic> toFields() => {
    'kind': kind.id,
    'toolId': toolId,
    'toolName': toolName,
    'toolCode': toolCode,
    'qrCode': qrCode,
    'personnelId': personnelId,
    'requestedBy': requestedBy,
    'requestedAt': requestedAt,
    'status': status.id,
    'checkoutAt': checkoutAt,
    'dueAt': dueAt,
    'expiresAt': expiresAt,
    'purpose': purpose,
    'message': message,
    'workOrderId': workOrderId,
    'loanId': loanId,
    'confirmedAt': confirmedAt,
    'closedAt': closedAt,
    'closedBy': closedBy,
  };

  @override
  String toString() =>
      'ToolRequest(id: $id, ${kind.id} $toolName for $personnelId, '
      '${status.id})';
}
