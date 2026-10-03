import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/app_config.dart';
import '../../utils/result.dart';
import '../notification_service.dart';
import 'firebase_call_guard.dart';

/// Firebase Cloud Messaging implementation of [NotificationService], with
/// `flutter_local_notifications` for what the phone shows and
/// `permission_handler` for Android's runtime permission (Objective 3.B).
///
/// Covers the notification triggers listed in manuscript §1.5: report
/// acknowledgment, work-order and task assignment, status updates,
/// maintenance completion, and low-stock alerts.
///
/// ## What this class does and does not do
///
/// It handles *transport*: permission, tokens, the Android channel, taps,
/// and raising a notification on this device. It does not decide when a
/// notification is sent or what it says — the repositories write those,
/// in the transaction that moves a report.
///
/// Sending a push to *another* device needs a trusted sender. On the Spark
/// plan there is no Cloud Function to be one, and an app cannot send FCM
/// messages without a server credential, which must never ship inside it.
/// So nothing pushes to a closed app yet; see docs/architecture_decisions.md.
/// What does reach this device — from the Firebase console, or a Cloud
/// Function once the project moves to Blaze — is handled in full.
///
/// Persisting a notification for the in-app list (Figure 22) is
/// `NotificationRepository`'s job, not this one.
class FcmNotificationService implements NotificationService {
  FcmNotificationService({
    required this._messaging,
    required this._guard,
    required this._config,
    FlutterLocalNotificationsPlugin? local,
  }) : _local = local ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging;
  final FirebaseCallGuard _guard;
  final AppConfig _config;
  final FlutterLocalNotificationsPlugin _local;

  final _localTaps = StreamController<Map<String, dynamic>>.broadcast();
  Future<void>? _initialized;

  /// GSUhub's one Android channel. Its id is also FCM's default channel
  /// (AndroidManifest.xml), so a push that arrives while the app is closed
  /// lands in the same place as one the app raises itself.
  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'report_updates',
    'Report updates',
    description:
        'When a report you filed is received, assigned, worked on '
        'or finished.',
    importance: Importance.high,
  );

  /// Android notifications need an Android device; the web build is the
  /// administrator console, which has no use for them.
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<Result<void>> initialize() =>
      _guard.callOnce(() => _initialized ??= _initialize());

  Future<void> _initialize() async {
    if (!_isAndroid) return;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = _decode(response.payload);
        if (payload != null) _localTaps.add(payload);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  @override
  Future<Result<PushPermission>> permissionStatus() =>
      _guard.callOnce(() async {
        if (_isAndroid) {
          return _fromPermission(await Permission.notification.status);
        }
        final settings = await _messaging.getNotificationSettings();
        return _fromAuthorization(settings.authorizationStatus);
      });

  @override
  Future<Result<PushPermission>> requestPermission() =>
      _guard.callOnce(() async {
        if (_isAndroid) {
          return _fromPermission(await Permission.notification.request());
        }
        final settings = await _messaging.requestPermission();
        return _fromAuthorization(settings.authorizationStatus);
      });

  @override
  Future<Result<void>> openSettings() => _guard.callOnce(() async {
    await openAppSettings();
  });

  static PushPermission _fromPermission(PermissionStatus status) =>
      switch (status) {
        PermissionStatus.granted ||
        PermissionStatus.limited ||
        PermissionStatus.provisional => PushPermission.granted,
        PermissionStatus.permanentlyDenied => PushPermission.permanentlyDenied,
        PermissionStatus.denied ||
        PermissionStatus.restricted => PushPermission.denied,
      };

  static PushPermission _fromAuthorization(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        // A browser that was refused does not ask again on its own.
        AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently =>
          PushPermission.permanentlyDenied,
        AuthorizationStatus.notDetermined => PushPermission.denied,
      };

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

  /// Tokens are not permanent — they change on reinstall, cache clear, or
  /// at the service's discretion. A stored token that is never refreshed
  /// silently stops receiving notifications, which presents as "push just
  /// stopped working for that one user" and is miserable to diagnose.
  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<Result<void>> deleteDeviceToken() =>
      _guard.callOnce(_messaging.deleteToken);

  @override
  Stream<Map<String, dynamic>> get onMessage =>
      FirebaseMessaging.onMessage.map(_payloadOf);

  @override
  Stream<Map<String, dynamic>> get onTapped => Stream.multi((listener) {
    final subscriptions = [
      FirebaseMessaging.onMessageOpenedApp.map(_payloadOf).listen(listener.add),
      _localTaps.stream.listen(listener.add),
    ];
    listener.onCancel = () =>
        Future.wait([for (final s in subscriptions) s.cancel()]);
  });

  @override
  Future<Result<Map<String, dynamic>?>> launchPayload() =>
      _guard.callOnce(() async {
        final pushed = await _messaging.getInitialMessage();
        if (pushed != null) return _payloadOf(pushed);
        if (!_isAndroid) return null;
        final details = await _local.getNotificationAppLaunchDetails();
        if (details == null || !details.didNotificationLaunchApp) return null;
        return _decode(details.notificationResponse?.payload);
      });

  @override
  Future<Result<void>> show({
    required int id,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) => _guard.callOnce(() async {
    if (!_isAndroid) return;
    await _local.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: jsonEncode(payload),
    );
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

  static Map<String, dynamic>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

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
