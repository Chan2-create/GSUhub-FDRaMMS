import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'app_config.dart';

/// Outcome of application startup.
///
/// Startup either produces a working set of Firebase handles or an
/// explanation of why it could not. Modelling it as a sealed type forces
/// `main.dart` to handle the failure branch — the alternative, letting an
/// exception escape `main`, is the classic Flutter white screen with the
/// real cause buried in a console the user cannot see.
sealed class FirebaseStartupResult {
  const FirebaseStartupResult();
}

/// Firebase initialized successfully.
final class FirebaseStartupSuccess extends FirebaseStartupResult {
  const FirebaseStartupSuccess({
    required this.auth,
    required this.firestore,
    required this.storage,
    required this.messaging,
    required this.usingEmulator,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseMessaging messaging;

  /// Whether these handles point at the local Emulator Suite. Surfaced so
  /// the UI can show an unmistakable banner — the worst emulator bug is
  /// believing you are looking at real data when you are not, and vice
  /// versa.
  final bool usingEmulator;
}

/// Firebase could not be initialized.
final class FirebaseStartupFailure extends FirebaseStartupResult {
  const FirebaseStartupFailure({
    required this.summary,
    required this.detail,
    this.isEmulatorFailure = false,
    this.isConfigurationFailure = false,
  });

  /// Short, user-facing explanation.
  final String summary;

  /// Technical detail for the developer.
  final String detail;

  /// True when the failure looks like "the emulators are not running",
  /// which has a specific and very common fix.
  final bool isEmulatorFailure;

  /// True when the build itself was configured wrongly. Retrying cannot
  /// help: `--dart-define` values are fixed at compile time.
  final bool isConfigurationFailure;
}

/// Initializes Firebase and, in emulator mode, repoints every SDK at the
/// local Emulator Suite.
abstract final class FirebaseInitializer {
  /// Initializes Firebase for the current platform.
  ///
  /// Never throws. Every failure is returned as [FirebaseStartupFailure]
  /// so startup can render an error screen instead of dying.
  static Future<FirebaseStartupResult> initialize(AppConfig config) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      final storage = FirebaseStorage.instance;
      final messaging = FirebaseMessaging.instance;

      if (config.useEmulator) {
        await _connectEmulators(
          config: config,
          auth: auth,
          firestore: firestore,
          storage: storage,
        );
      } else if (kDebugMode) {
        // Reachable only through USE_LIVE_FIREBASE=true, but a debug build
        // pointed at the demo project deserves to be impossible to miss.
        debugPrint(
          'GSUhub: WARNING — debug build connected to the LIVE Firebase '
          'project. Every write lands in real data.',
        );
      }

      return FirebaseStartupSuccess(
        auth: auth,
        firestore: firestore,
        storage: storage,
        messaging: messaging,
        usingEmulator: config.useEmulator,
      );
    } on FirebaseException catch (error) {
      return FirebaseStartupFailure(
        summary: 'Could not connect to the GSUhub backend.',
        detail: 'FirebaseException(${error.code}): ${error.message}',
        isEmulatorFailure: config.useEmulator,
      );
    } on Object catch (error) {
      return FirebaseStartupFailure(
        summary: 'Could not start GSUhub.',
        detail: '$error',
        isEmulatorFailure: config.useEmulator,
      );
    }
  }

  static Future<void> _connectEmulators({
    required AppConfig config,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  }) async {
    final host = config.emulatorHost;

    await auth.useAuthEmulator(host, config.authEmulatorPort);
    firestore.useFirestoreEmulator(host, config.firestoreEmulatorPort);
    await storage.useStorageEmulator(host, config.storageEmulatorPort);

    if (kDebugMode) {
      debugPrint(
        'GSUhub: using Firebase emulators at $host '
        '(auth ${config.authEmulatorPort}, '
        'firestore ${config.firestoreEmulatorPort}, '
        'storage ${config.storageEmulatorPort}). '
        'No live project data is being read or written.',
      );
    }
  }
}
