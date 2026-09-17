import '../utils/result.dart';

/// Abstract push-notification contract. Every shell depends on this
/// interface, never on `firebase_messaging` directly — see the "Shared
/// Backend Contract" in docs/architecture_decisions.md, rule 1.
///
/// The foreground-message payload is a loose `Map<String, dynamic>` rather
/// than a typed notification model, because what a notification *contains*
/// (report id, work order id, etc.) is defined by the feature that sends
/// it (reporting, work_orders, ...), not by this transport-level contract.
///
/// No implementation exists yet. A concrete `FirebaseNotificationService`
/// is built in Objective 1.C once Cloud Messaging is actually configured.
abstract interface class NotificationService {
  /// Requests OS-level notification permission. Required on iOS and newer
  /// Android; a no-op returning success on platforms that don't ask.
  Future<Result<void>> requestPermission();

  /// The device's current push token, or `null` if unavailable.
  Future<Result<String?>> getDeviceToken();

  /// Emits the raw data payload of a notification received while the app
  /// is in the foreground.
  Stream<Map<String, dynamic>> get onMessage;

  /// Subscribes this device to a topic (e.g. per-role broadcast channels).
  Future<Result<void>> subscribeToTopic(String topic);

  Future<Result<void>> unsubscribeFromTopic(String topic);
}
