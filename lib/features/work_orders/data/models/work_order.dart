import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/constants/damage_categories.dart';
import '../../../../core/data/data_record.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/record_converters.dart';

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
    this.archivedAt,
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
    RecordConverters.validateNotBlank(title, 'title');
    RecordConverters.validateNotBlank(createdBy, 'createdBy');
  }

  factory WorkOrder.fromRecord(DataRecord record) {
    final data = record.fields;
    return WorkOrder(
      id: record.id,
      reportIds: RecordConverters.stringList(data, 'reportIds'),
      title: RecordConverters.require<String>(data, 'title'),
      description: RecordConverters.require<String>(data, 'description'),
      category: RecordConverters.requireEnum(
        data,
        'category',
        DamageCategory.fromId,
      ),
      priority: RecordConverters.requireEnum(
        data,
        'priority',
        PriorityLevel.fromId,
      ),
      status: RecordConverters.requireEnum(
        data,
        'status',
        WorkOrderStatus.fromId,
      ),
      assignedPersonnelIds: RecordConverters.stringList(
        data,
        'assignedPersonnelIds',
      ),
      facilityId: RecordConverters.optional<String>(data, 'facilityId'),
      facilityName: RecordConverters.optional<String>(data, 'facilityName'),
      adminNotes: RecordConverters.optional<String>(data, 'adminNotes'),
      scheduledFor: RecordConverters.optionalDate(data, 'scheduledFor'),
      startedAt: RecordConverters.optionalDate(data, 'startedAt'),
      completedAt: RecordConverters.optionalDate(data, 'completedAt'),
      createdBy: RecordConverters.require<String>(data, 'createdBy'),
      createdAt: RecordConverters.requireDate(data, 'createdAt'),
      updatedAt: RecordConverters.requireDate(data, 'updatedAt'),
      archivedAt: RecordConverters.optionalDate(data, 'archivedAt'),
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

  /// When an administrator archived the work order (2026-11-08): off the
  /// board, its status and history untouched. Null when not.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// Whether this work order consolidates merged duplicate reports.
  bool get isMergedFromDuplicates => reportIds.length > 1;

  /// Whether this work order was past its target completion date, and not
  /// yet finished, at [moment].
  ///
  /// The target date is picked from a calendar, so it names a day rather
  /// than an instant: a job is late only once that day has ended, not from
  /// midnight of the day it is due. Taking [moment] rather than assuming
  /// "now" lets Analytics ask how many were overdue a month ago.
  bool isOverdueAt(DateTime moment) {
    final target = scheduledFor?.toLocal();
    if (target == null || createdAt.isAfter(moment)) return false;

    final finished = completedAt;
    if (finished != null && !finished.isAfter(moment)) return false;
    // Completed with no recorded completion time: when it finished is
    // unknown, so it is not counted late rather than counted late forever.
    if (finished == null && status == WorkOrderStatus.completed) return false;

    final endOfTargetDay = DateTime(target.year, target.month, target.day + 1);
    return moment.toLocal().isAfter(endOfTargetDay);
  }

  Map<String, dynamic> toFields() => {
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
    'scheduledFor': scheduledFor,
    'startedAt': startedAt,
    'completedAt': completedAt,
    'createdBy': createdBy,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'archivedAt': archivedAt,
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
    DateTime? archivedAt,
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
    archivedAt: archivedAt ?? this.archivedAt,
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
        other.updatedAt == updatedAt &&
        other.archivedAt == archivedAt;
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
    archivedAt,
  ]);

  @override
  String toString() =>
      'WorkOrder(id: $id, title: $title, status: $status, '
      'priority: $priority, reportIds: $reportIds)';
}
