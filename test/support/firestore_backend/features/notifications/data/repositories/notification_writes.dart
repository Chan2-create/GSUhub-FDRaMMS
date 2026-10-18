import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/notifications/data/models/personnel_notice.dart';
import 'package:gsuhub/features/notifications/data/models/report_notice.dart';

import '../../../../core/data/firestore_repository.dart';

/// Stages a requestor's notification about their report inside the
/// transaction that moves it (Objective 3.B).
///
/// Written with the status change rather than after it, so the in-app
/// list and the report can never disagree: a move that fails leaves no
/// notice, and one that succeeds always has one. On the Spark plan there
/// is no server to write these, so the client that makes the move writes
/// them; the security rules hold each one to the report's own reporter.
void stageReportNotice(
  Transaction transaction,
  FirebaseFirestore firestore, {
  required String recipientId,
  required String reportId,
  required ReportNotice notice,
}) => stageNotification(
  transaction,
  firestore,
  recipientId: recipientId,
  type: notice.type,
  title: notice.title,
  body: notice.body,
  relatedEntityType: FirestorePaths.damageReports,
  relatedEntityId: reportId,
);

/// Stages a maintenance technician's notification about their work inside
/// the transaction that gives or changes it (Objective 5.A): a work order
/// assigned, a task added, work sent back. It points at the work order, so
/// tapping it opens that.
void stagePersonnelNotice(
  Transaction transaction,
  FirebaseFirestore firestore, {
  required String recipientId,
  required String workOrderId,
  required PersonnelNotice notice,
}) => stageNotification(
  transaction,
  firestore,
  recipientId: recipientId,
  type: notice.type,
  title: notice.title,
  body: notice.body,
  relatedEntityType: FirestorePaths.workOrders,
  relatedEntityId: workOrderId,
);

/// Stages one notification, stamped with server time.
void stageNotification(
  Transaction transaction,
  FirebaseFirestore firestore, {
  required String recipientId,
  required NotificationType type,
  required String title,
  required String body,
  required String relatedEntityType,
  required String relatedEntityId,
}) {
  final notification = AppNotification(
    id: 'pending',
    recipientId: recipientId,
    type: type,
    title: title,
    body: body,
    isRead: false,
    relatedEntityType: relatedEntityType,
    relatedEntityId: relatedEntityId,
    createdAt: DateTime.now().toUtc(),
  );

  transaction.set(firestore.collection(FirestorePaths.notifications).doc(), {
    ...notification.toFirestore(),
    'createdAt': FirestoreRepository.serverNow,
  });
}
