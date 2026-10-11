import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/result.dart';
import '../data/models/app_notification.dart';
import 'notification_providers.dart';

/// Keeps this phone's side of notifications in step with who is signed in
/// (Objective 3.B). Runs for a signed-in requestor only — the console's
/// administrators and Objective 5's personnel get none of it yet.
///
/// While a requestor is signed in it:
/// - asks for notification permission once per sign-in, while Android will
///   still show the prompt;
/// - saves the device's push token on their account, and again whenever it
///   rotates;
/// - raises a notification on the phone for each new notice that arrives
///   while GSUhub is running — the foreground, and the background for as
///   long as Android keeps the app alive. With no server on the Spark plan,
///   this is how a requestor hears of a move without opening the app;
/// - shows a push that arrives in the foreground, which Android would not;
/// - opens the report a tapped notification is about, including one that
///   launched the app from closed.
///
/// [signOutDevice] retires the token before sign-out, so the next account
/// on this phone never receives the last one's notifications.
class PushCoordinator {
  PushCoordinator(this._ref);

  final Ref _ref;

  String? _uid;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Notices already raised or already there when the listener started —
  /// so none is raised twice, and signing in does not replay old ones.
  final _known = <String>{};
  bool _baselineTaken = false;

  /// Where a tapped notification leads, once the app can go there.
  void Function(String location)? _navigate;
  String? _pendingLocation;

  /// Serialises sign-in and sign-out handling: each waits for the last.
  Future<void> _queue = Future<void>.value();

  /// The router's `go`, handed over by the app. A tap that arrived before
  /// it — a cold start — is followed now.
  void attach(void Function(String location) navigate) {
    _navigate = navigate;
    final pending = _pendingLocation;
    if (pending != null) {
      _pendingLocation = null;
      navigate(pending);
    }
  }

  /// Called with every auth change.
  void userChanged(AuthUser? user) {
    final uid = user != null && user.role == UserRole.requestor
        ? user.uid
        : null;
    _queue = _queue.then((_) => _switchTo(uid));
  }

  Future<void> _switchTo(String? uid) async {
    if (uid == _uid) return;
    await _stop();
    _uid = uid;
    if (uid != null) await _start(uid);
  }

  NotificationService get _service => _ref.read(notificationServiceProvider);

  Future<void> _start(String uid) async {
    final service = _service;
    await service.initialize();

    // Not in a browser: the faculty app ships on Android, and there web
    // push is off, so a browser prompt would ask for nothing.
    if (!kIsWeb) {
      final permission = await service.permissionStatus();
      if (permission case Success(value: PushPermission.denied)) {
        await service.requestPermission();
        _ref.invalidate(pushPermissionProvider);
      }
    }

    await _registerToken(uid);
    _subscriptions
      ..add(service.onTokenRefresh.listen((token) => _saveToken(uid, token)))
      ..add(service.onMessage.listen(_showPush))
      ..add(service.onTapped.listen(_open))
      ..add(
        _ref
            .read(notificationRepositoryProvider)
            .watchForUser(uid)
            .listen(_onNotices),
      );

    final launch = await service.launchPayload();
    if (launch case Success(value: final payload?)) _open(payload);
  }

  Future<void> _stop() async {
    // Not awaited: nothing here depends on a cancel finishing, and a
    // stream whose cancel never completes (3.C met one) must not hold up
    // sign-out behind it.
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _known.clear();
    _baselineTaken = false;
  }

  Future<void> _registerToken(String uid) async {
    final token = await _service.getDeviceToken();
    if (token case Success(value: final value?)) await _saveToken(uid, value);
  }

  /// Saves [token] on the account unless it is already there — one read
  /// rather than a write on every launch.
  Future<void> _saveToken(String uid, String token) async {
    final users = _ref.read(userRepositoryProvider);
    final profile = await users.getById(uid);
    if (profile case Success(:final value) when value.fcmToken == token) {
      return;
    }
    await users.setFcmToken(uid, token);
  }

  /// Retires this phone's token and stops listening, before the account
  /// signs out — the rules let only the account itself clear its token.
  Future<void> signOutDevice() {
    final done = _queue.then((_) async {
      final uid = _uid;
      if (uid == null) return;
      await _ref.read(userRepositoryProvider).setFcmToken(uid, null);
      await _service.deleteDeviceToken();
      await _stop();
      _uid = null;
    });
    _queue = done;
    return done;
  }

  void _onNotices(Result<List<AppNotification>> result) {
    final notices = switch (result) {
      Success(:final value) => value,
      Error() => null,
    };
    if (notices == null) return;

    if (!_baselineTaken) {
      _known.addAll(notices.map((notice) => notice.id));
      _baselineTaken = true;
      return;
    }
    for (final notice in notices.reversed) {
      if (notice.isRead || !_known.add(notice.id)) continue;
      unawaited(
        _service.show(
          id: _localIdOf(notice.id),
          title: notice.title,
          body: notice.body,
          payload: {
            'notificationId': notice.id,
            'recipientId': notice.recipientId,
            if (notice.relatedEntityType == FirestorePaths.damageReports &&
                notice.relatedEntityId != null)
              'reportId': notice.relatedEntityId!,
          },
        ),
      );
    }
  }

  /// A push that arrived while GSUhub is open. Android shows none in the
  /// foreground on its own; one the listener already raised is skipped.
  void _showPush(Map<String, dynamic> payload) {
    final notificationId = payload['notificationId'] as String?;
    if (notificationId != null && !_known.add(notificationId)) return;
    final title = payload['title'] as String?;
    if (title == null) return;
    unawaited(
      _service.show(
        id: _localIdOf(notificationId ?? '${payload['messageId']}'),
        title: title,
        body: payload['body'] as String? ?? '',
        payload: {
          for (final entry in payload.entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
      ),
    );
  }

  /// Follows a tapped notification to its report, marking it read. One
  /// addressed to another account — signed out since it arrived — is
  /// ignored rather than opened under the wrong person.
  void _open(Map<String, dynamic> payload) {
    final recipient = payload['recipientId'] as String?;
    if (recipient != null && recipient != _uid) return;

    final notificationId = payload['notificationId'] as String?;
    if (notificationId != null) {
      unawaited(
        _ref.read(notificationActionsProvider).markRead(notificationId),
      );
    }

    final reportId =
        payload['reportId'] as String? ?? payload['relatedEntityId'] as String?;
    final location = reportId == null
        ? RoutePaths.staffAlerts
        : RoutePaths.staffReportDetailFor(reportId);
    final navigate = _navigate;
    if (navigate == null) {
      _pendingLocation = location;
    } else {
      navigate(location);
    }
  }

  /// Android wants an int id per notification; the same notice always maps
  /// to the same one, so a repeat replaces rather than stacks.
  static int _localIdOf(String id) => id.hashCode & 0x7fffffff;

  Future<void> dispose() => _stop();

  @visibleForTesting
  Future<void> get settled => _queue;
}

/// The app's one [PushCoordinator], following the auth state. The app
/// watches it from the root so it lives as long as the app does.
final pushCoordinatorProvider = Provider<PushCoordinator>((ref) {
  final coordinator = PushCoordinator(ref);
  ref
    ..listen(
      authStateProvider,
      (_, next) => coordinator.userChanged(next.value),
      fireImmediately: true,
    )
    ..onDispose(coordinator.dispose);
  return coordinator;
});
