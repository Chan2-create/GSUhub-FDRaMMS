import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_notification.dart';

/// The signed-in person's uid: the live auth state first, then the
/// service's cached user — the stream has not necessarily emitted by the
/// first read.
String? _signedInUid(Ref ref) =>
    (ref.watch(authStateProvider).value ??
            ref.read(authServiceProvider).currentUser)
        ?.uid;

/// The signed-in requestor's notifications, newest first, live — the
/// Alerts tab (Figma `169:1459`, Objective 3.B). Auto-disposed with the
/// tab, and swapped for an empty list on sign-out before the rules would
/// start refusing it.
final myNotificationsProvider =
    StreamProvider.autoDispose<Result<List<AppNotification>>>((ref) {
      final uid = _signedInUid(ref);
      if (uid == null) {
        return Stream.value(const Result.success(<AppNotification>[]));
      }
      return ref.watch(notificationRepositoryProvider).watchForUser(uid);
    });

/// How many of them are unread, live — the badge on the Alerts tab. Kept
/// apart from the list so the badge does not hold the whole list open on
/// every tab.
final unreadNotificationCountProvider = StreamProvider.autoDispose<Result<int>>(
  (ref) {
    final uid = _signedInUid(ref);
    if (uid == null) return Stream.value(const Result.success(0));
    return ref.watch(notificationRepositoryProvider).watchUnreadCount(uid);
  },
);

/// Marking notifications read, for the signed-in requestor.
class NotificationActions {
  const NotificationActions(this._ref);

  final Ref _ref;

  Future<Result<void>> markRead(String notificationId) =>
      _ref.read(notificationRepositoryProvider).markAsRead(notificationId);

  Future<Result<void>> markAllRead() async {
    final uid =
        (_ref.read(authStateProvider).value ??
                _ref.read(authServiceProvider).currentUser)
            ?.uid;
    if (uid == null) return const Result.success(null);
    return _ref.read(notificationRepositoryProvider).markAllAsRead(uid);
  }
}

final notificationActionsProvider = Provider<NotificationActions>(
  NotificationActions.new,
);

/// Whether this phone may show GSUhub's notifications, for the Alerts tab's
/// prompt (3.B). Asking and opening settings refresh it.
class PushPermissionController extends AsyncNotifier<PushPermission> {
  @override
  Future<PushPermission> build() async =>
      _orDenied(await ref.read(notificationServiceProvider).permissionStatus());

  /// Asks — the system prompt, while Android still shows one.
  Future<void> request() async {
    final service = ref.read(notificationServiceProvider);
    state = AsyncData(_orDenied(await service.requestPermission()));
  }

  /// Opens GSUhub's page in the phone's settings; [refresh] once back.
  Future<void> openSettings() async {
    await ref.read(notificationServiceProvider).openSettings();
  }

  Future<void> refresh() async {
    final service = ref.read(notificationServiceProvider);
    state = AsyncData(_orDenied(await service.permissionStatus()));
  }

  // A permission that cannot be read is treated as not given: the prompt
  // shows, and asking again settles it.
  static PushPermission _orDenied(Result<PushPermission> result) =>
      result.fold((permission) => permission, (_) => PushPermission.denied);
}

final pushPermissionProvider =
    AsyncNotifierProvider<PushPermissionController, PushPermission>(
      PushPermissionController.new,
    );
