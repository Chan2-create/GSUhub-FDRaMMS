import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../../utils/result.dart';
import '../notification_service.dart';
import 'firebase_call_guard.dart';

/// Firebase Cloud Messaging implementation of [NotificationService].
///
/// Covers the notification triggers listed in manuscript §1.5: report
/// acknowledgment, work-order and task assignment, status updates,
/// maintenance completion, and low-stock alerts.
///
/// ## What this class does and does not do
///
/// It handles *transport*: permission, tokens, topic subscriptions, and
/// surfacing foreground messages. It does not decide when a notification
/// is sent or what it says — that belongs to whichever feature raises it,
/// and delivery to other devices requires a trusted sender (see the Cloud
/// Functions note in docs/architecture_decisions.md; on the Spark plan
/// there is no server-side sender, so cross-device push is not yet wired).
///
/// Persisting a notification for the in-app list (Figure 22) is
/// `NotificationRepository`'s job, not this one.
class FcmNotificationService implements NotificationService {
  FcmNotificationService({
    required this._messaging,
    required this._guard,
    required this._config,
  });

  final FirebaseMessaging _messaging;
  final FirebaseCallGuard _guard;
  final AppConfig _config;

  @override
  Future<Result<void>> requestPermission() => _guard.call(() async {
    await _messaging.requestPermission(provisional: true);
  });

  @override
  Future<Result<String?>> getDeviceToken() => _guard.call(() {
    // Web requires the VAPID key to mint a token; mobile must not be
    // given one. Passing it on Android is not merely redundant — it
    // produces an argument error.
    if (kIsWeb) {
      if (!_config.hasVapidKey) {
        // Returning null rather than throwing: a missing VAPID key should
        // degrade push silently in local development, not break app
        // startup for someone who just wants to work on the dashboard.
        debugPrint(
          'GSUhub: FCM_VAPID_KEY not supplied — web push is disabled. '
          'See docs/firebase_setup.md.',
        );
        return Future<String?>.value();
      }
      return _messaging.getToken(vapidKey: _config.fcmVapidKey);
    }
    return _messaging.getToken();
  });

  /// Emits a new token whenever FCM rotates it.
  ///
  /// Tokens are not permanent — they change on reinstall, cache clear, or
  /// at the service's discretion. A stored token that is never refreshed
  /// silently stops receiving notifications, which presents as "push just
  /// stopped working for that one user" and is miserable to diagnose.
  /// Callers should persist each emission via
  /// `UserRepository.setFcmToken`.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onMessage =>
      FirebaseMessaging.onMessage.map(_payloadOf);

  /// Emits when the user taps a notification that opened the app from the
  /// background, so the app can deep-link to the referenced record.
  Stream<Map<String, dynamic>> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_payloadOf);

  /// The notification that cold-started the app, if any.
  Future<Result<Map<String, dynamic>?>> getInitialMessage() =>
      _guard.call(() async {
        final message = await _messaging.getInitialMessage();
        return message == null ? null : _payloadOf(message);
      });

  @override
  Future<Result<void>> subscribeToTopic(String topic) => _guard.call(() {
    // Topic subscription is unsupported on web; FCM web delivers to
    // tokens only. Silently succeeding keeps callers from having to
    // branch on platform for what is an optimization, not a requirement.
    if (kIsWeb) return Future<void>.value();
    return _messaging.subscribeToTopic(topic);
  });

  @override
  Future<Result<void>> unsubscribeFromTopic(String topic) => _guard.call(() {
    if (kIsWeb) return Future<void>.value();
    return _messaging.unsubscribeFromTopic(topic);
  });

  /// Flattens a message into the loose payload map the interface promises,
  /// merging the notification's title/body with its data fields so callers
  /// have one shape to read regardless of how the message was composed.
  static Map<String, dynamic> _payloadOf(RemoteMessage message) => {
    ...message.data,
    if (message.notification?.title != null)
      'title': message.notification!.title,
    if (message.notification?.body != null) 'body': message.notification!.body,
    if (message.messageId != null) 'messageId': message.messageId,
  };
}

/// Background message handler.
///
/// Must be a top-level function — the Android background isolate has no
/// access to the main isolate's state and looks this up by symbol, so it
/// cannot be a method or a closure.
///
/// Kept deliberately minimal: FCM already displays the notification itself
/// on Android when the message carries a `notification` block, so there is
/// nothing to do here beyond existing. Any real work would need its own
/// `Firebase.initializeApp` in this isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty. See the doc comment above.
}
