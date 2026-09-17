import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/data/firestore_repository.dart';
import '../../../../core/utils/result.dart';
import '../models/app_notification.dart';
import 'notification_repository.dart';

/// Firestore-backed [NotificationRepository] — the persisted history
/// behind the in-app notification list (manuscript Figure 22).
class NotificationRepositoryImpl extends FirestoreRepository
    implements NotificationRepository {
  const NotificationRepositoryImpl({required super.db, required super.guard});

  static const String _path = FirestorePaths.notifications;

  @override
  Stream<Result<List<AppNotification>>> watchForUser(
    String userId, {
    bool unreadOnly = false,
  }) {
    Query<Map<String, dynamic>> query = collection(_path)
        .where('recipientId', isEqualTo: userId);

    if (unreadOnly) query = query.where('isRead', isEqualTo: false);

    return watchMany(
      query: query.orderBy('createdAt', descending: true).limit(100),
      convert: AppNotification.fromFirestore,
    );
  }

  @override
  Stream<Result<int>> watchUnreadCount(String userId) => guard.stream(
    collection(_path)
        .where('recipientId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        // Firestore's count() aggregation is one-shot and has no
        // snapshots() equivalent, so a live badge has to come from the
        // document stream. Capped because the badge only ever needs to
        // distinguish "some" from "a lot" — nobody reads past 99.
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.length),
  );

  @override
  Future<Result<String>> create(AppNotification notification) =>
      add(path: _path, data: notification.toFirestore());

  @override
  Future<Result<void>> markAsRead(String notificationId) => updateDoc(
    path: _path,
    id: notificationId,
    data: {'isRead': true, 'readAt': FirestoreRepository.serverNow},
  );

  @override
  Future<Result<void>> markAllAsRead(String userId) async {
    final unread = await getMany(
      query: collection(_path)
          .where('recipientId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          // Firestore batches cap at 500 writes; 400 leaves headroom and
          // is far beyond any realistic unread backlog for one user.
          .limit(400),
      convert: AppNotification.fromFirestore,
    );

    return unread.fold((notifications) async {
      if (notifications.isEmpty) return const Result<void>.success(null);

      return db.runBatch((batch) {
        for (final notification in notifications) {
          batch.update(collection(_path).doc(notification.id), {
            'isRead': true,
            'readAt': FirestoreRepository.serverNow,
          });
        }
      });
    }, (failure) async => Result.failure(failure));
  }
}
