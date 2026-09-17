import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/firestore_converters.dart';

/// A `work_orders` document — "an official maintenance task generated
/// within the GSUhub system based on validated facility damage reports"
/// (manuscript §1.7), assigned to personnel for execution.
///
/// [reportIds] is an **array**, not a single id: when an Administrator
/// merges duplicate reports, the merged set is "consolidated into a single
/// work order to prevent redundant maintenance assignments" (manuscript
/// §3.4). Each merged report keeps its own document; they all point here,
/// and this points back at all of them.
class WorkOrder {
  WorkOrder({
    required this.id,
    required this.reportIds,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.assignedPersonnelIds = const [],
    this.facilityId,
    this.facilityName,
    this.adminNotes,
    this.scheduledFor,
    this.startedAt,
    this.completedAt,
  }) {
    if (reportIds.isEmpty) {
      throw ArgumentError.value(
        reportIds,
        'reportIds',
        'A work order must originate from at least one damage report',
      );
    }
    FirestoreConverters.validateNotBlank(title, 'title');
    FirestoreConverters.validateNotBlank(createdBy, 'createdBy');
  }

  factory WorkOrder.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return WorkOrder(
      id: doc.id,
      reportIds: FirestoreConverters.stringList(data, 'reportIds'),
      title: FirestoreConverters.require<String>(data, 'title'),
      description: FirestoreConverters.require<String>(data, 'description'),
      category: FirestoreConverters.requireEnum(
        data,
        'category',
        DamageCategory.fromId,
      ),
      priority: FirestoreConverters.requireEnum(
        data,
        'priority',
        PriorityLevel.fromId,
      ),
      status: FirestoreConverters.requireEnum(
        data,
        'status',
        WorkOrderStatus.fromId,
      ),
      assignedPersonnelIds: FirestoreConverters.stringList(
        data,
        'assignedPersonnelIds',
      ),
      facilityId: FirestoreConverters.optional<String>(data, 'facilityId'),
      facilityName: FirestoreConverters.optional<String>(data, 'facilityName'),
      adminNotes: FirestoreConverters.optional<String>(data, 'adminNotes'),
      scheduledFor: FirestoreConverters.optionalDate(data, 'scheduledFor'),
      startedAt: FirestoreConverters.optionalDate(data, 'startedAt'),
      completedAt: FirestoreConverters.optionalDate(data, 'completedAt'),
      createdBy: FirestoreConverters.require<String>(data, 'createdBy'),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;

  /// Every damage report this work order resolves. Length > 1 means
  /// duplicates were merged.
  final List<String> reportIds;

  final String title;
  final String description;
  final DamageCategory category;

  /// Copied from the originating report's official priority at creation
  /// time. Held here too so the Kanban board and personnel app can sort
  /// without loading the report.
  final PriorityLevel priority;

  final WorkOrderStatus status;

  /// Personnel assigned to execute this work order (manuscript Figure 18,
  /// "Task Assignment"). A list because larger jobs can take a crew.
  final List<String> assignedPersonnelIds;

  final String? facilityId;

  /// DENORMALIZED from `facilities.name`, for the Kanban card and
  /// personnel list views (Figure 19, Figure 25).
  final String? facilityName;

  /// Free-text instruction from the Administrator, surfaced to personnel
  /// (manuscript Figure 23 shows: "Admin: Please prioritize this before
  /// the lab session at 2 PM").
  final String? adminNotes;

  final DateTime? scheduledFor;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// The Administrator who raised this work order.
  final String createdBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this work order consolidates merged duplicate reports.
  bool get isMergedFromDuplicates => reportIds.length > 1;

  Map<String, dynamic> toFirestore() => {
    'reportIds': reportIds,
    'title': title,
    'description': description,
    'category': category.id,
    'priority': priority.id,
    'status': status.id,
    'assignedPersonnelIds': assignedPersonnelIds,
    'facilityId': facilityId,
    'facilityName': facilityName,
    'adminNotes': adminNotes,
    'scheduledFor': scheduledFor == null
        ? null
        : Timestamp.fromDate(scheduledFor!),
    'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
    'completedAt': completedAt == null
        ? null
        : Timestamp.fromDate(completedAt!),
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  WorkOrder copyWith({
    String? id,
    List<String>? reportIds,
    String? title,
    String? description,
    DamageCategory? category,
    PriorityLevel? priority,
    WorkOrderStatus? status,
    List<String>? assignedPersonnelIds,
    String? facilityId,
    String? facilityName,
    String? adminNotes,
    DateTime? scheduledFor,
    DateTime? startedAt,
    DateTime? completedAt,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WorkOrder(
    id: id ?? this.id,
    reportIds: reportIds ?? this.reportIds,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    assignedPersonnelIds: assignedPersonnelIds ?? this.assignedPersonnelIds,
    facilityId: facilityId ?? this.facilityId,
    facilityName: facilityName ?? this.facilityName,
    adminNotes: adminNotes ?? this.adminNotes,
    scheduledFor: scheduledFor ?? this.scheduledFor,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WorkOrder) return false;
    return other.id == id &&
        listEquals(other.reportIds, reportIds) &&
        other.title == title &&
        other.description == description &&
        other.category == category &&
        other.priority == priority &&
        other.status == status &&
        listEquals(other.assignedPersonnelIds, assignedPersonnelIds) &&
        other.facilityId == facilityId &&
        other.facilityName == facilityName &&
        other.adminNotes == adminNotes &&
        other.scheduledFor == scheduledFor &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt &&
        other.createdBy == createdBy &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    ...reportIds,
    title,
    description,
    category,
    priority,
    status,
    ...assignedPersonnelIds,
    facilityId,
    facilityName,
    adminNotes,
    scheduledFor,
    startedAt,
    completedAt,
    createdBy,
    createdAt,
    updatedAt,
  ]);

  @override
  String toString() =>
      'WorkOrder(id: $id, title: $title, status: $status, '
      'priority: $priority, reportIds: $reportIds)';
}
