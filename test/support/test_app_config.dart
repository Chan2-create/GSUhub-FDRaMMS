import 'package:gsuhub/core/config/app_config.dart';
import 'package:gsuhub/core/config/env.dart';

/// A fully-specified [AppConfig] for tests.
///
/// Exists so a test never calls `AppConfig.fromEnvironment()`, which reads
/// `--dart-define` values and would therefore behave differently depending
/// on how the test runner was invoked — a test that passes locally and
/// fails in CI for reasons nobody can see.
AppConfig testAppConfig({
  bool useEmulator = false,
  String fcmVapidKey = '',
  Duration requestTimeout = const Duration(seconds: 5),
  int maxRetryAttempts = 0,
}) => AppConfig(
  appName: 'GSUhub',
  environment: Environment.development,
  useEmulator: useEmulator,
  emulatorHost: 'localhost',
  authEmulatorPort: 9099,
  firestoreEmulatorPort: 8080,
  storageEmulatorPort: 9199,
  fcmVapidKey: fcmVapidKey,
  requestTimeout: requestTimeout,
  maxRetryAttempts: maxRetryAttempts,
);
