import '../../../../core/utils/result.dart';
import '../models/app_notification.dart';

/// Abstract contract for the `notifications` collection — the persisted
/// record behind each push, backing the in-app notification list
/// (manuscript Figure 22).
///
/// Distinct from `core/services/notification_service.dart`, which is the
/// transport (FCM tokens, permission, delivery). This is the history.
///
/// **Interface only** — implementation is 1.C.
abstract interface class NotificationRepository {
  /// One user's notifications, newest first.
  Stream<Result<List<AppNotification>>> watchForUser(
    String userId, {
    bool unreadOnly = false,
  });

  /// Unread count for a badge, without transferring the notifications
  /// themselves.
  Stream<Result<int>> watchUnreadCount(String userId);

  Future<Result<String>> create(AppNotification notification);

  Future<Result<void>> markAsRead(String notificationId);

  Future<Result<void>> markAllAsRead(String userId);
}
