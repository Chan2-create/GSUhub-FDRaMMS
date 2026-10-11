import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../models/app_notification.dart';
import '../models/report_notice.dart';

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
}) {
  final notification = AppNotification(
    id: 'pending',
    recipientId: recipientId,
    type: notice.type,
    title: notice.title,
    body: notice.body,
    isRead: false,
    relatedEntityType: FirestorePaths.damageReports,
    relatedEntityId: reportId,
    createdAt: DateTime.now().toUtc(),
  );

  transaction.set(firestore.collection(FirestorePaths.notifications).doc(), {
    ...notification.toFirestore(),
    'createdAt': FirestoreRepository.serverNow,
  });
}
