/// Build-time environment, selected via `--dart-define=IS_PRODUCTION=true`
/// (defaults to development, e.g. plain `flutter run`).
enum Environment { development, production }

/// Compile-time configuration, all supplied through `--dart-define` so
/// nothing environment-specific is committed to source.
///
/// See docs/firebase_setup.md for the exact run commands.
abstract final class Env {
  static const bool _isProductionDefine = bool.fromEnvironment('IS_PRODUCTION');

  static const bool _isProductionBuild =
      bool.fromEnvironment('dart.vm.product') || _isProductionDefine;

  static const Environment current = _isProductionBuild
      ? Environment.production
      : Environment.development;

  static bool get isDevelopment => current == Environment.development;
  static bool get isProduction => current == Environment.production;

  /// Explicit opt-in to the live `gsuhub-dorsu` project from a development
  /// build.
  ///
  /// `flutter run --dart-define=USE_LIVE_FIREBASE=true`
  static const bool useLiveFirebase = bool.fromEnvironment('USE_LIVE_FIREBASE');

  /// Forces the emulators even in a production build, for exercising a
  /// release bundle against local data.
  ///
  /// `flutter build web --dart-define=USE_EMULATOR=true`
  static const bool _forceEmulator = bool.fromEnvironment('USE_EMULATOR');

  /// Whether to route Firebase traffic at the local Emulator Suite instead
  /// of the live `gsuhub-dorsu` project.
  ///
  /// **On by default in development builds.** `gsuhub-dorsu` is the only
  /// project the team demos from, so the dangerous mistake is the one a
  /// forgotten flag makes: writing test records into it. Reaching the live
  /// project from a debug build therefore takes [useLiveFirebase]; a
  /// production build uses it unless [_forceEmulator] says otherwise.
  static const bool useEmulator =
      _forceEmulator || (!_isProductionBuild && !useLiveFirebase);

  /// Both backend flags at once is a contradiction, not a preference, so
  /// startup refuses it rather than silently picking one.
  static const bool hasConflictingBackendFlags =
      _forceEmulator && useLiveFirebase;

  /// Host the emulators are reachable on.
  ///
  /// Defaults to `localhost` for web and desktop. An Android emulator
  /// reaches the host machine at `10.0.2.2` instead, and a physical Android
  /// device needs the development machine's LAN IP — both are supplied
  /// with `--dart-define=EMULATOR_HOST=...`.
  static const String emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: 'localhost',
  );

  /// Emulator ports. Must match the `emulators` block in `firebase.json`.
  static const int authEmulatorPort = int.fromEnvironment(
    'AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );

  static const int firestoreEmulatorPort = int.fromEnvironment(
    'FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );

  static const int storageEmulatorPort = int.fromEnvironment(
    'STORAGE_EMULATOR_PORT',
    defaultValue: 9199,
  );

  /// Web Push (VAPID) public key from Firebase Console → Project settings
  /// → Cloud Messaging → Web Push certificates.
  ///
  /// This key is **public by design** — it ships inside the web client
  /// bundle and identifies the sender to the browser's push service. It is
  /// kept out of source anyway, so the repository carries no
  /// project-specific values at all and a different Firebase project can
  /// be swapped in without editing code.
  ///
  /// Empty when not supplied, which disables web push registration rather
  /// than failing the app — see `FcmNotificationService`.
  ///
  /// `flutter run -d chrome --dart-define=FCM_VAPID_KEY=<key>`
  static const String fcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

  static bool get hasVapidKey => fcmVapidKey.isNotEmpty;
}
