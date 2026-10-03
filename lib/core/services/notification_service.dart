import '../utils/result.dart';

/// Whether this device may show GSUhub's notifications (Objective 3.B).
enum PushPermission {
  /// Allowed.
  granted,

  /// Not allowed yet; asking again can still show the system prompt.
  denied,

  /// Refused for good — Android 13+ stops prompting after the second
  /// refusal. Only the app's page in the phone's settings can change it.
  permanentlyDenied,
}

/// Abstract push-notification contract. Every shell depends on this
/// interface, never on `firebase_messaging` directly — see the "Shared
/// Backend Contract" in docs/architecture_decisions.md, rule 1.
///
/// Payloads are loose `Map<String, dynamic>`s rather than a typed model,
/// because what a notification *contains* (report id, work order id, etc.)
/// is defined by the feature that sends it, not by this transport-level
/// contract. A notification about a report carries `reportId`,
/// `notificationId` and `recipientId` (3.B).
///
/// Showing a notification on this device ([show]) belongs here too: on the
/// Spark plan nothing can push to a phone, so while GSUhub is running it
/// raises each new notice itself.
abstract interface class NotificationService {
  /// Prepares the device side: the Android notification channel and the
  /// handling of taps. Safe to call more than once.
  Future<Result<void>> initialize();

  /// Whether notifications are allowed now, without asking.
  Future<Result<PushPermission>> permissionStatus();

  /// Asks for permission — the system prompt on Android 13+ — and returns
  /// the outcome.
  Future<Result<PushPermission>> requestPermission();

  /// Opens GSUhub's page in the phone's settings, the only way back from
  /// [PushPermission.permanentlyDenied].
  Future<Result<void>> openSettings();

  /// The device's current push token, or `null` if unavailable.
  Future<Result<String?>> getDeviceToken();

  /// A new token whenever the push service rotates it.
  Stream<String> get onTokenRefresh;

  /// Retires this device's token so nothing more reaches it — on sign-out,
  /// so the next account on the phone never receives the last one's.
  Future<Result<void>> deleteDeviceToken();

  /// Emits the raw data payload of a push received while the app is in the
  /// foreground.
  Stream<Map<String, dynamic>> get onMessage;

  /// Emits the payload of a notification the person tapped while the app
  /// was running — a push, or one [show] raised.
  Stream<Map<String, dynamic>> get onTapped;

  /// The payload of the notification whose tap launched the app from
  /// closed, if one did.
  Future<Result<Map<String, dynamic>?>> launchPayload();

  /// Shows a notification on this device now, on GSUhub's channel. [id]
  /// keeps one notice from showing twice; [payload] comes back through
  /// [onTapped] or [launchPayload].
  Future<Result<void>> show({
    required int id,
    required String title,
    required String body,
    required Map<String, String> payload,
  });

  /// Subscribes this device to a topic (e.g. per-role broadcast channels).
  Future<Result<void>> subscribeToTopic(String topic);

  Future<Result<void>> unsubscribeFromTopic(String topic);
}
