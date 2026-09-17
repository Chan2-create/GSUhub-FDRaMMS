import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/item_condition.dart';
import '../../../../core/utils/firestore_converters.dart';

/// A `tool_loans` document — one borrow-and-return cycle for a [Tool].
///
/// Backs the accountability half of manuscript §1.5's tool tracking
/// requirement: "issuance, borrowing, usage, return status, condition
/// monitoring, and personnel accountability", and §3.4's note that the
/// module "records borrowed maintenance tools, return dates, tool
/// conditions upon return, and personnel accountability".
///
/// Recording condition at both ends of the loan is what makes damage
/// attributable: a tool that goes out `good` and comes back `poor` has a
/// documented custodian.
class ToolLoan {
  ToolLoan({
    required this.id,
    required this.toolId,
    required this.toolName,
    required this.borrowedBy,
    required this.borrowedAt,
    required this.conditionOnBorrow,
    this.workOrderId,
    this.expectedReturnAt,
    this.returnedAt,
    this.conditionOnReturn,
    this.notes,
  }) {
    FirestoreConverters.validateNotBlank(toolId, 'toolId');
    FirestoreConverters.validateNotBlank(toolName, 'toolName');
    FirestoreConverters.validateNotBlank(borrowedBy, 'borrowedBy');
    if (returnedAt != null && returnedAt!.isBefore(borrowedAt)) {
      throw ArgumentError.value(
        returnedAt,
        'returnedAt',
        'A tool cannot be returned before it was borrowed',
      );
    }
    if (returnedAt != null && conditionOnReturn == null) {
      throw ArgumentError.value(
        conditionOnReturn,
        'conditionOnReturn',
        'Condition must be recorded when a tool is returned (condition '
            'monitoring, manuscript §1.5)',
      );
    }
  }

  factory ToolLoan.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ToolLoan(
      id: doc.id,
      toolId: FirestoreConverters.require<String>(data, 'toolId'),
      toolName: FirestoreConverters.require<String>(data, 'toolName'),
      borrowedBy: FirestoreConverters.require<String>(data, 'borrowedBy'),
      borrowedAt: FirestoreConverters.requireDate(data, 'borrowedAt'),
      conditionOnBorrow: FirestoreConverters.requireEnum(
        data,
        'conditionOnBorrow',
        ItemCondition.fromId,
      ),
      workOrderId: FirestoreConverters.optional<String>(data, 'workOrderId'),
      expectedReturnAt: FirestoreConverters.optionalDate(
        data,
        'expectedReturnAt',
      ),
      returnedAt: FirestoreConverters.optionalDate(data, 'returnedAt'),
      conditionOnReturn: FirestoreConverters.optionalEnum(
        data,
        'conditionOnReturn',
        ItemCondition.fromId,
      ),
      notes: FirestoreConverters.optional<String>(data, 'notes'),
    );
  }

  final String id;
  final String toolId;

  /// DENORMALIZED from `tools.name`, so a loan history stays readable
  /// without joining, and survives a tool being renamed or retired.
  final String toolName;

  final String borrowedBy;

  /// The work order the tool was taken out for, when the loan is tied to
  /// one.
  final String? workOrderId;

  final DateTime borrowedAt;
  final DateTime? expectedReturnAt;
  final DateTime? returnedAt;

  final ItemCondition conditionOnBorrow;

  /// Required once [returnedAt] is set — enforced in the constructor.
  final ItemCondition? conditionOnReturn;

  final String? notes;

  /// Whether this loan has been closed out.
  bool get isReturned => returnedAt != null;

  /// Whether the tool is still out past its expected return date.
  /// Evaluated against [now] so this stays testable and free of hidden
  /// clock access.
  bool isOverdue(DateTime now) =>
      !isReturned && expectedReturnAt != null && now.isAfter(expectedReturnAt!);

  /// Whether the tool came back in worse shape than it went out.
  bool get conditionDegraded =>
      conditionOnReturn != null &&
      conditionOnReturn!.index > conditionOnBorrow.index;

  Map<String, dynamic> toFirestore() => {
    'toolId': toolId,
    'toolName': toolName,
    'borrowedBy': borrowedBy,
    'workOrderId': workOrderId,
    'borrowedAt': Timestamp.fromDate(borrowedAt),
    'expectedReturnAt': expectedReturnAt == null
        ? null
        : Timestamp.fromDate(expectedReturnAt!),
    'returnedAt': returnedAt == null ? null : Timestamp.fromDate(returnedAt!),
    'conditionOnBorrow': conditionOnBorrow.id,
    'conditionOnReturn': conditionOnReturn?.id,
    'notes': notes,
  };

  ToolLoan copyWith({
    String? id,
    String? toolId,
    String? toolName,
    String? borrowedBy,
    String? workOrderId,
    DateTime? borrowedAt,
    DateTime? expectedReturnAt,
    DateTime? returnedAt,
    ItemCondition? conditionOnBorrow,
    ItemCondition? conditionOnReturn,
    String? notes,
  }) => ToolLoan(
    id: id ?? this.id,
    toolId: toolId ?? this.toolId,
    toolName: toolName ?? this.toolName,
    borrowedBy: borrowedBy ?? this.borrowedBy,
    workOrderId: workOrderId ?? this.workOrderId,
    borrowedAt: borrowedAt ?? this.borrowedAt,
    expectedReturnAt: expectedReturnAt ?? this.expectedReturnAt,
    returnedAt: returnedAt ?? this.returnedAt,
    conditionOnBorrow: conditionOnBorrow ?? this.conditionOnBorrow,
    conditionOnReturn: conditionOnReturn ?? this.conditionOnReturn,
    notes: notes ?? this.notes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolLoan &&
          other.id == id &&
          other.toolId == toolId &&
          other.toolName == toolName &&
          other.borrowedBy == borrowedBy &&
          other.workOrderId == workOrderId &&
          other.borrowedAt == borrowedAt &&
          other.expectedReturnAt == expectedReturnAt &&
          other.returnedAt == returnedAt &&
          other.conditionOnBorrow == conditionOnBorrow &&
          other.conditionOnReturn == conditionOnReturn &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
    id,
    toolId,
    toolName,
    borrowedBy,
    workOrderId,
    borrowedAt,
    expectedReturnAt,
    returnedAt,
    conditionOnBorrow,
    conditionOnReturn,
    notes,
  );

  @override
  String toString() =>
      'ToolLoan(id: $id, tool: $toolName, borrowedBy: $borrowedBy, '
      'returned: $isReturned)';
}
