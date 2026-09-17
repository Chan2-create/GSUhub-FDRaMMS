import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/enums/task_status.dart';
import '../../../../core/utils/firestore_converters.dart';

/// A `tasks` document — one checklist item within a work order, backing
/// the personnel "daily task management" capability (manuscript §1.2
/// objectives; Figure 24 shows a "Today's To-Do" list with per-item
/// "Upload Proof" actions and a completion count).
///
/// Named `MaintenanceTask` rather than `Task` to avoid colliding with
/// `dart:async`'s scheduling vocabulary and with Flutter's own `Task`
/// types in tooling contexts.
class MaintenanceTask {
  MaintenanceTask({
    required this.id,
    required this.workOrderId,
    required this.title,
    required this.assignedTo,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.dueDate,
    this.proofPhotoUrls = const [],
    this.completedAt,
  }) {
    FirestoreConverters.validateNotBlank(workOrderId, 'workOrderId');
    FirestoreConverters.validateNotBlank(title, 'title');
    FirestoreConverters.validateNotBlank(assignedTo, 'assignedTo');
  }

  factory MaintenanceTask.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return MaintenanceTask(
      id: doc.id,
      workOrderId: FirestoreConverters.require<String>(data, 'workOrderId'),
      title: FirestoreConverters.require<String>(data, 'title'),
      assignedTo: FirestoreConverters.require<String>(data, 'assignedTo'),
      status: FirestoreConverters.requireEnum(
        data,
        'status',
        TaskStatus.fromId,
      ),
      description: FirestoreConverters.optional<String>(data, 'description'),
      dueDate: FirestoreConverters.optionalDate(data, 'dueDate'),
      proofPhotoUrls: FirestoreConverters.stringList(data, 'proofPhotoUrls'),
      completedAt: FirestoreConverters.optionalDate(data, 'completedAt'),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
      updatedAt: FirestoreConverters.requireDate(data, 'updatedAt'),
    );
  }

  final String id;

  /// The work order this task belongs to.
  final String workOrderId;

  final String title;
  final String? description;

  /// The single technician responsible. Unlike
  /// `WorkOrder.assignedPersonnelIds`, a task has exactly one owner —
  /// Figure 24's checklist is per-person.
  final String assignedTo;

  final TaskStatus status;
  final DateTime? dueDate;

  /// Photo evidence uploaded via "Upload Proof" (Figure 24).
  final List<String> proofPhotoUrls;

  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether proof has been attached, which Figure 24 surfaces as the
  /// "PROOF SUBMITTED" badge.
  bool get hasProof => proofPhotoUrls.isNotEmpty;

  Map<String, dynamic> toFirestore() => {
    'workOrderId': workOrderId,
    'title': title,
    'description': description,
    'assignedTo': assignedTo,
    'status': status.id,
    'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
    'proofPhotoUrls': proofPhotoUrls,
    'completedAt': completedAt == null
        ? null
        : Timestamp.fromDate(completedAt!),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  MaintenanceTask copyWith({
    String? id,
    String? workOrderId,
    String? title,
    String? description,
    String? assignedTo,
    TaskStatus? status,
    DateTime? dueDate,
    List<String>? proofPhotoUrls,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MaintenanceTask(
    id: id ?? this.id,
    workOrderId: workOrderId ?? this.workOrderId,
    title: title ?? this.title,
    description: description ?? this.description,
    assignedTo: assignedTo ?? this.assignedTo,
    status: status ?? this.status,
    dueDate: dueDate ?? this.dueDate,
    proofPhotoUrls: proofPhotoUrls ?? this.proofPhotoUrls,
    completedAt: completedAt ?? this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MaintenanceTask) return false;
    return other.id == id &&
        other.workOrderId == workOrderId &&
        other.title == title &&
        other.description == description &&
        other.assignedTo == assignedTo &&
        other.status == status &&
        other.dueDate == dueDate &&
        listEquals(other.proofPhotoUrls, proofPhotoUrls) &&
        other.completedAt == completedAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    workOrderId,
    title,
    description,
    assignedTo,
    status,
    dueDate,
    ...proofPhotoUrls,
    completedAt,
    createdAt,
    updatedAt,
  ]);

  @override
  String toString() =>
      'MaintenanceTask(id: $id, workOrderId: $workOrderId, title: $title, '
      'status: $status, assignedTo: $assignedTo)';
}
