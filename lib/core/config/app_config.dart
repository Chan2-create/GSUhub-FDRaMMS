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
    required this.useFirestoreEmulator,
    this.prioritizationWeights = const PrioritizationWeights(),
  });

  factory AppConfig.fromEnvironment() => AppConfig(
    appName: 'GSUhub',
    environment: Env.current,
    useFirestoreEmulator: Env.isDevelopment,
  );

  final String appName;
  final Environment environment;

  /// Whether local Firestore/Auth/Storage emulators should be targeted
  /// instead of the live Firebase project. Wiring this flag to the actual
  /// emulator connection calls is left to the objective that first needs a
  /// working Firestore connection.
  final bool useFirestoreEmulator;

  final PrioritizationWeights prioritizationWeights;
}
