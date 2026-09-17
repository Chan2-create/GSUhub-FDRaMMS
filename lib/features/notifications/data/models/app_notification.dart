import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/notification_type.dart';
import '../../../../core/utils/firestore_converters.dart';

/// A `notifications` document — the persisted record behind a push
/// notification, so the in-app notification list (manuscript Figure 22)
/// survives the push itself being dismissed or missed.
///
/// Triggers come from §1.5: "push notifications for report
/// acknowledgment, work-order and task assignment, status updates, and
/// maintenance completion", plus low-stock alerts.
///
/// The document shape beyond recipient/type/title/body is DERIVED — the
/// manuscript specifies when notifications fire, not how they are stored.
/// See docs/data_dictionary.md.
class AppNotification {
  AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.relatedEntityType,
    this.relatedEntityId,
    this.readAt,
  }) {
    FirestoreConverters.validateNotBlank(recipientId, 'recipientId');
    FirestoreConverters.validateNotBlank(title, 'title');
    if (isRead && readAt == null) {
      throw ArgumentError.value(
        readAt,
        'readAt',
        'A notification marked read must record when it was read',
      );
    }
  }

  factory AppNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppNotification(
      id: doc.id,
      recipientId: FirestoreConverters.require<String>(data, 'recipientId'),
      type: FirestoreConverters.requireEnum(
        data,
        'type',
        NotificationType.fromId,
      ),
      title: FirestoreConverters.require<String>(data, 'title'),
      body: FirestoreConverters.require<String>(data, 'body'),
      isRead: FirestoreConverters.require<bool>(data, 'isRead'),
      relatedEntityType: FirestoreConverters.optional<String>(
        data,
        'relatedEntityType',
      ),
      relatedEntityId: FirestoreConverters.optional<String>(
        data,
        'relatedEntityId',
      ),
      readAt: FirestoreConverters.optionalDate(data, 'readAt'),
      createdAt: FirestoreConverters.requireDate(data, 'createdAt'),
    );
  }

  final String id;

  /// The `users` document this notification is addressed to. Security
  /// rules restrict reads to this user.
  final String recipientId;

  final NotificationType type;
  final String title;
  final String body;

  /// Collection name of the thing this notification is about — a value
  /// from `FirestorePaths`, so tapping the notification can deep-link.
  /// Kept as a string because it names a collection, not a domain concept.
  final String? relatedEntityType;

  final String? relatedEntityId;

  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  Map<String, dynamic> toFirestore() => {
    'recipientId': recipientId,
    'type': type.id,
    'title': title,
    'body': body,
    'relatedEntityType': relatedEntityType,
    'relatedEntityId': relatedEntityId,
    'isRead': isRead,
    'readAt': readAt == null ? null : Timestamp.fromDate(readAt!),
    'createdAt': Timestamp.fromDate(createdAt),
  };

  AppNotification copyWith({
    String? id,
    String? recipientId,
    NotificationType? type,
    String? title,
    String? body,
    String? relatedEntityType,
    String? relatedEntityId,
    bool? isRead,
    DateTime? readAt,
    DateTime? createdAt,
  }) => AppNotification(
    id: id ?? this.id,
    recipientId: recipientId ?? this.recipientId,
    type: type ?? this.type,
    title: title ?? this.title,
    body: body ?? this.body,
    relatedEntityType: relatedEntityType ?? this.relatedEntityType,
    relatedEntityId: relatedEntityId ?? this.relatedEntityId,
    isRead: isRead ?? this.isRead,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt ?? this.createdAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          other.id == id &&
          other.recipientId == recipientId &&
          other.type == type &&
          other.title == title &&
          other.body == body &&
          other.relatedEntityType == relatedEntityType &&
          other.relatedEntityId == relatedEntityId &&
          other.isRead == isRead &&
          other.readAt == readAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    recipientId,
    type,
    title,
    body,
    relatedEntityType,
    relatedEntityId,
    isRead,
    readAt,
    createdAt,
  );

  @override
  String toString() =>
      'AppNotification(id: $id, recipientId: $recipientId, type: $type, '
      'isRead: $isRead)';
}
