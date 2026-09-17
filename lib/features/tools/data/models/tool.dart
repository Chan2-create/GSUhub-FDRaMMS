import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/utils/firestore_converters.dart';

/// A `tools` document — durable maintenance equipment that personnel
/// borrow and return, as opposed to consumable `inventory_items` that are
/// deducted.
///
/// Fields follow the Admin "Tool Assets & Tracking" table (manuscript
/// Figure 15: Tool ID, Tool Name, Status, Condition, Current User, QR),
/// backed by §1.5's requirement for "tool and equipment tracking,
/// including issuance, borrowing, usage, return status, condition
/// monitoring, and personnel accountability".
class Tool {
  Tool({
    required this.id,
    required this.toolCode,
    required this.name,
    required this.status,
    required this.condition,
    required this.qrCode,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.storageLocation,
    this.currentHolderId,
    this.currentLoanId,
  }) {
    FirestoreConverters.validateNotBlank(toolCode, 'toolCode');
    FirestoreConverters.validateNotBlank(name, 'name');
    FirestoreConverters.validateNotBlank(qrCode, 'qrCode');
    if (status == ToolStatus.borrowed && currentHolderId == null) {
      throw ArgumentError.value(
        currentHolderId,
        'currentHolderId',
        'A borrowed tool must record who holds it (personnel '
            'accountability, manuscript §1.5)',
      );
    }
  }

  factory Tool.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Tool(
      id: doc.id,
      toolCode: FirestoreConverters.require<String>(data, 'toolCode'),
      name: FirestoreConverters.require<String>(data, 'name'),
      status: FirestoreConverters.requireEnum(
        data,
        'status',
        ToolStatus.fromId,
      ),
      condition: FirestoreConverters.requireEnum(
        data,
        'condition',
        ItemCondition.fromId,
      ),
      qrCode: FirestoreConverters.require<String>(data, 'qrCode'),
      category: FirestoreConverters.optional<String>(data, 'category'),
      storageLocation: FirestoreConverters.optional<String>(
        data,
        'storageLocation',
      ),
      currentHolderId: FirestoreConverters.optional<String>(
        data,
        'currentHolderId',
      ),
      currentLoanId: FirestoreConverters.optional<String>(
        data,
        'currentLoanId',
      ),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;

  /// Human-readable asset tag shown in the UI, e.g. "TL-0824"
  /// (Figure 15). Distinct from the Firestore document [id].
  final String toolCode;

  final String name;
  final ToolStatus status;
  final ItemCondition condition;

  /// Free-text grouping, e.g. "Power Tools". String rather than an enum
  /// for the same reason as `Asset.category`.
  final String? category;

  final String? storageLocation;

  /// The personnel account currently holding this tool (Figure 15's
  /// "Current User" column). Non-null whenever [status] is
  /// [ToolStatus.borrowed] — enforced in the constructor.
  final String? currentHolderId;

  /// DENORMALIZED pointer to the open `tool_loans` document, so the Admin
  /// tool table can offer a Check In action without querying loans per
  /// row. Cleared on return.
  final String? currentLoanId;

  final String qrCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toFirestore() => {
    'toolCode': toolCode,
    'name': name,
    'status': status.id,
    'condition': condition.id,
    'category': category,
    'storageLocation': storageLocation,
    'currentHolderId': currentHolderId,
    'currentLoanId': currentLoanId,
    'qrCode': qrCode,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Tool copyWith({
    String? id,
    String? toolCode,
    String? name,
    ToolStatus? status,
    ItemCondition? condition,
    String? category,
    String? storageLocation,
    String? currentHolderId,
    String? currentLoanId,
    String? qrCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Tool(
    id: id ?? this.id,
    toolCode: toolCode ?? this.toolCode,
    name: name ?? this.name,
    status: status ?? this.status,
    condition: condition ?? this.condition,
    category: category ?? this.category,
    storageLocation: storageLocation ?? this.storageLocation,
    currentHolderId: currentHolderId ?? this.currentHolderId,
    currentLoanId: currentLoanId ?? this.currentLoanId,
    qrCode: qrCode ?? this.qrCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tool &&
          other.id == id &&
          other.toolCode == toolCode &&
          other.name == name &&
          other.status == status &&
          other.condition == condition &&
          other.category == category &&
          other.storageLocation == storageLocation &&
          other.currentHolderId == currentHolderId &&
          other.currentLoanId == currentLoanId &&
          other.qrCode == qrCode &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    toolCode,
    name,
    status,
    condition,
    category,
    storageLocation,
    currentHolderId,
    currentLoanId,
    qrCode,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'Tool(id: $id, code: $toolCode, name: $name, status: $status, '
      'condition: $condition)';
}
