import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/utils/firestore_converters.dart';
import 'material_line.dart';

/// A material GSU has set aside for a work order —
/// `work_orders/{id}/materials_allocated/{inventoryItemId}` (Objective
/// 6.B, Figure Group 43's "Pre-assigned Materials").
///
/// The administrator assigns these on the console's work-order page, and
/// an approved request adds to them. They are what the technician can
/// collect from the store; stock changes only by what the technician
/// records as used, when the accomplishment report is filed (§1.5). One
/// per item.
class AllocatedMaterial {
  AllocatedMaterial({
    required this.line,
    required this.allocatedBy,
    required this.allocatedAt,
  });

  factory AllocatedMaterial.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AllocatedMaterial(
      line: MaterialLine.fromMap({...data, 'inventoryItemId': doc.id}),
      allocatedBy: FirestoreConverters.require<String>(data, 'allocatedBy'),
      allocatedAt: FirestoreConverters.requireDate(data, 'allocatedAt'),
    );
  }

  final MaterialLine line;

  /// The administrator who last set the quantity.
  final String allocatedBy;
  final DateTime allocatedAt;

  String get inventoryItemId => line.inventoryItemId;

  Map<String, dynamic> toFirestore() => {
    ...line.toMap()..remove('inventoryItemId'),
    'allocatedBy': allocatedBy,
    'allocatedAt': Timestamp.fromDate(allocatedAt),
  };
}
