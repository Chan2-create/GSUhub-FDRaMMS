import '../../../../core/data/data_record.dart';
import '../../../../core/enums/material_request_status.dart';
import '../../../../core/utils/record_converters.dart';
import 'material_line.dart';

/// A technician's request for materials a work order needs and does not
/// have — `material_requests/{id}` (Objective 6.B, Figure Group 43's
/// "Additional Materials Needed" and "Request History").
///
/// §3.4 has personnel "request and monitor materials assigned to work
/// orders". Approving one adds its lines to the work order's pre-assigned
/// materials; nothing comes off stock until the accomplishment report is
/// filed, from what was actually used (§1.5).
class MaterialRequest {
  MaterialRequest({
    required this.id,
    required this.workOrderId,
    required this.requestedBy,
    required this.requestedByName,
    required this.items,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.adminNote,
    this.reviewedBy,
    this.reviewedAt,
  }) {
    RecordConverters.validateNotBlank(workOrderId, 'workOrderId');
    RecordConverters.validateNotBlank(requestedBy, 'requestedBy');
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'A request needs a material');
    }
  }

  factory MaterialRequest.fromRecord(DataRecord record) {
    final data = record.fields;
    return MaterialRequest(
      id: record.id,
      workOrderId: RecordConverters.require<String>(data, 'workOrderId'),
      requestedBy: RecordConverters.require<String>(data, 'requestedBy'),
      requestedByName: RecordConverters.require<String>(
        data,
        'requestedByName',
      ),
      items: [
        for (final item
            in RecordConverters.optional<List<dynamic>>(data, 'items') ??
                const [])
          MaterialLine.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
      status: RecordConverters.requireEnum(
        data,
        'status',
        MaterialRequestStatus.fromId,
      ),
      note: RecordConverters.optional<String>(data, 'note'),
      adminNote: RecordConverters.optional<String>(data, 'adminNote'),
      reviewedBy: RecordConverters.optional<String>(data, 'reviewedBy'),
      reviewedAt: RecordConverters.optionalDate(data, 'reviewedAt'),
      createdAt: RecordConverters.requireDate(data, 'createdAt'),
      updatedAt: RecordConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;
  final String workOrderId;

  /// The technician who asked.
  final String requestedBy;

  /// DENORMALIZED from `users.fullName`, for the console's list.
  final String requestedByName;

  final List<MaterialLine> items;
  final MaterialRequestStatus status;

  /// The technician's own words: "Floor sealant needed for Lobby area."
  final String? note;

  /// GSU's answer, shown under "Admin Note" (Group 43). Required to
  /// decline.
  final String? adminNote;

  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == MaterialRequestStatus.pending;

  Map<String, dynamic> toFields() => {
    'workOrderId': workOrderId,
    'requestedBy': requestedBy,
    'requestedByName': requestedByName,
    'items': [for (final item in items) item.toMap()],
    'status': status.id,
    'note': note,
    'adminNote': adminNote,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
