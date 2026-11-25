import '../../../../core/data/supabase_repository.dart';
import '../../../../core/utils/result.dart';
import '../models/app_notification.dart';
import 'notification_repository.dart';

/// Supabase-backed [NotificationRepository] (Objective 1) — the persisted
/// history behind the in-app notification list (manuscript Figure 22).
///
/// Notifications are written by the database functions that make the move
/// they announce, in the same transaction; row level security shows each
/// one to its recipient only, while their account is active.
class NotificationRepositoryImpl extends SupabaseRepository
    implements NotificationRepository {
  const NotificationRepositoryImpl({
    required super.client,
    required super.guard,
    super.live,
  });

  static const String _table = 'notifications';

  /// The newest hundred, unless more are asked for: the badge only needs
  /// to tell "some" from "a lot".
  static const int _limit = 100;

  @override
  Stream<Result<List<AppNotification>>> watchForUser(
    String userId, {
    bool unreadOnly = false,
    int limit = _limit,
  }) => _watch(userId, limit: limit).map(
    (result) => result.map(
      (notifications) => [
        for (final notification in notifications)
          if (!unreadOnly || !notification.isRead) notification,
      ],
    ),
  );

  @override
  Future<Result<void>> markManyAsRead(List<String> notificationIds) =>
      rpc('mark_notifications_read', {'ids': notificationIds});

  @override
  Stream<Result<int>> watchUnreadCount(String userId) => _watch(userId).map(
    (result) => result.map(
      (notifications) => notifications.where((n) => !n.isRead).length,
    ),
  );

  /// Filtered on the recipient and not on read: callers want both the
  /// read and the unread, and count the unread themselves.
  Stream<Result<List<AppNotification>>> _watch(
    String userId, {
    int limit = _limit,
  }) => watchMany(
    stream: liveRows(
      _table,
      (rows) =>
          rows.eq('recipient_id', userId).order('created_at').limit(limit),
    ),
    convert: AppNotification.fromRecord,
  );

  @override
  Future<Result<String>> create(AppNotification notification) =>
      SupabaseRepository.unsupported('NotificationRepository.create');

  @override
  Future<Result<void>> markAsRead(String notificationId) =>
      rpc('mark_notification_read', {'id': notificationId});

  @override
  Future<Result<void>> markAllAsRead(String userId) =>
      rpc('mark_all_notifications_read', const {});
}
