import 'dart:convert';

import 'env.dart';

/// Default weighted-prioritization criteria (manuscript §3.4, Table 3.2:
/// Severity 0.40, Safety Risk 0.30, Frequency 0.20, Location Importance
/// 0.10). Exposed as overridable configuration rather than hardcoded into
/// the scoring logic itself, because two open questions remain unresolved
/// (see docs/architecture_decisions.md "Known blockers"):
///
/// - a conflicting statement elsewhere about the weight values, and
/// - an unspecified source for the 1-4 criterion ratings (who assigns
///   them, and when).
///
/// Neither question blocks this scaffolding objective. Building the actual
/// scoring engine and wiring it to a live, admin-editable `config`
/// Firestore document is Objective 1.3's responsibility; this class only
/// reserves the shape so that work has an obvious home.
class PrioritizationWeights {
  const PrioritizationWeights({
    this.severity = 0.40,
    this.safetyRisk = 0.30,
    this.frequency = 0.20,
    this.locationImportance = 0.10,
  });

  final double severity;
  final double safetyRisk;
  final double frequency;
  final double locationImportance;

  /// The four weights must sum to 1.0 for the Priority Score formula
  /// (manuscript §3.4) to stay bounded within its documented 1.00-4.00
  /// range.
  bool get isValid =>
      (severity + safetyRisk + frequency + locationImportance - 1.0).abs() <
      0.0001;
}

/// Central, environment-aware application configuration. A single instance
/// is expected to be provided at the app root (see `app.dart`) and read
/// from there — nothing in `core/` should construct its own instance.
class AppConfig {
  const AppConfig({
    required this.appName,
    required this.environment,
    required this.useEmulator,
    required this.emulatorHost,
    required this.authEmulatorPort,
    required this.fcmVapidKey,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.prioritizationWeights = const PrioritizationWeights(),
    this.requestTimeout = const Duration(seconds: 20),
    this.maxRetryAttempts = 2,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    appName: 'GSUhub',
    environment: Env.current,
    useEmulator: Env.useEmulator,
    emulatorHost: Env.emulatorHost,
    authEmulatorPort: Env.authEmulatorPort,
    fcmVapidKey: Env.fcmVapidKey,
    supabaseUrl: Env.supabaseUrl,
    supabaseAnonKey: Env.supabaseAnonKey,
  );

  final String appName;
  final Environment environment;

  /// Whether sign-in goes to the local Auth emulator, and the data to the
  /// local Supabase stack, instead of the live projects. The default in
  /// development builds — see [Env.useEmulator].
  final bool useEmulator;

  final String emulatorHost;
  final int authEmulatorPort;

  /// Web Push public key; empty disables web push registration. Public by
  /// design, but supplied at build time so no project-specific value is
  /// committed. See [Env.fcmVapidKey].
  final String fcmVapidKey;

  /// Where GSUhub's data and photos live. See [Env.supabaseUrl].
  final String supabaseUrl;

  /// The Supabase anon or publishable key. See [Env.supabaseAnonKey].
  final String supabaseAnonKey;

  /// How long a single Firebase call may run before it is abandoned.
  ///
  /// Firestore's own offline queue will happily wait indefinitely for
  /// connectivity, which is the right default for a note-taking app and
  /// the wrong one here: manuscript §1.5 states internet connectivity is
  /// required, so a request that cannot reach the backend should surface
  /// as a clear error the user can act on rather than a spinner that never
  /// resolves.
  final Duration requestTimeout;

  /// Retries for transient failures (`unavailable`, `deadline-exceeded`).
  /// Permission and not-found errors are never retried — they are
  /// deterministic, and retrying them only delays the error.
  final int maxRetryAttempts;

  final PrioritizationWeights prioritizationWeights;

  bool get hasVapidKey => fcmVapidKey.isNotEmpty;

  /// Why this build cannot reach its database, or `null` when it can.
  ///
  /// All of it is fixed at build time, so startup checks it before
  /// anything else and shows the answer instead of failing later on the
  /// first query.
  String? get supabaseConfigProblem {
    if (supabaseUrl.isEmpty) {
      return 'SUPABASE_URL is not set. Pass '
          '--dart-define=SUPABASE_URL=https://<project-ref>.supabase.co.';
    }
    final url = Uri.tryParse(supabaseUrl);
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      return 'SUPABASE_URL is not a URL: $supabaseUrl';
    }
    if (supabaseAnonKey.isEmpty) {
      return 'SUPABASE_ANON_KEY is not set. For the local stack it is the '
          'ANON_KEY that `npx supabase status` prints; for the hosted '
          'project, its anon or publishable key.';
    }
    if (_isPrivilegedKey(supabaseAnonKey)) {
      return 'SUPABASE_ANON_KEY is a service-role or secret key. It skips '
          'every access rule and must never ship in the app. Use the anon '
          'or publishable key.';
    }
    if (useEmulator && !_isLocal(url.host)) {
      return 'This build signs in with the Firebase Auth emulator, whose '
          'tokens only the local Supabase stack accepts, but SUPABASE_URL '
          'points at $supabaseUrl. Leave SUPABASE_URL out to use the local '
          'stack, or build with USE_LIVE_FIREBASE=true.';
    }
    return null;
  }

  bool _isLocal(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '10.0.2.2' ||
      host == emulatorHost;

  /// A secret key, or a legacy key whose JWT says `service_role`.
  static bool _isPrivilegedKey(String key) {
    if (key.startsWith('sb_secret_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'service_role';
    } on FormatException {
      return false;
    }
  }
}
