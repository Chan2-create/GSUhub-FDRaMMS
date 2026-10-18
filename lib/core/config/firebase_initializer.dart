import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'app_config.dart';
import 'web_auth_emulator.dart';

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
///
/// Firebase is sign-in and push notifications only (Objective 1): the data
/// and photos are on Supabase, which the app reaches with the signed-in
/// user's token (lib/core/services/supabase).
final class FirebaseStartupSuccess extends FirebaseStartupResult {
  const FirebaseStartupSuccess({
    required this.auth,
    required this.messaging,
    required this.usingEmulator,
  });

  final FirebaseAuth auth;
  final FirebaseMessaging messaging;

  /// Whether sign-in goes to the local Auth emulator. Surfaced so the UI
  /// can show an unmistakable banner — the worst emulator bug is believing
  /// you are looking at real data when you are not, and vice versa.
  final bool usingEmulator;
}

/// Firebase could not be initialized.
final class FirebaseStartupFailure extends FirebaseStartupResult {
  const FirebaseStartupFailure({
    required this.summary,
    required this.detail,
    this.isEmulatorFailure = false,
    this.isConfigurationFailure = false,
    this.advice,
  });

  /// Short, user-facing explanation.
  final String summary;

  /// Technical detail for the developer.
  final String detail;

  /// True when the failure looks like "the emulator is not running", which
  /// has a specific and very common fix.
  final bool isEmulatorFailure;

  /// True when the build itself was configured wrongly. Retrying cannot
  /// help: `--dart-define` values are fixed at compile time.
  final bool isConfigurationFailure;

  /// What to do about it, when the failure has a specific fix the
  /// standard wording would get wrong.
  final String? advice;
}

/// Initializes Firebase and, in emulator mode, points sign-in at the local
/// Auth emulator.
abstract final class FirebaseInitializer {
  /// Initializes Firebase for the current platform.
  ///
  /// Never throws. Every failure is returned as [FirebaseStartupFailure]
  /// so startup can render an error screen instead of dying.
  static Future<FirebaseStartupResult> initialize(AppConfig config) async {
    try {
      if (config.useEmulator) {
        // Before Firebase starts: on the web, starting restores a saved
        // session, and restoring talks to whichever Auth is attached then.
        await prepareAuthEmulatorBeforeStart(
          'http://${config.emulatorHost}:${config.authEmulatorPort}',
        );
      }

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final auth = FirebaseAuth.instance;
      final messaging = FirebaseMessaging.instance;

      if (config.useEmulator) {
        await auth.useAuthEmulator(
          config.emulatorHost,
          config.authEmulatorPort,
        );
        if (authEmulatorAttached() == false) {
          return const FirebaseStartupFailure(
            summary: 'Sign-in is not connected to the Auth emulator.',
            detail:
                'Firebase Auth reached the live project before the emulator '
                'could be attached, so this tab would sign in to real '
                'accounts. GSUhub stopped instead.',
            advice:
                'Close this tab and open the app in a new one. If it keeps '
                'happening, clear the site data for this page in the browser.',
          );
        }
        if (kDebugMode) {
          debugPrint(
            'GSUhub: signing in with the Auth emulator at '
            '${config.emulatorHost}:${config.authEmulatorPort}; data from '
            '${config.supabaseUrl}. No live project data is being read or '
            'written.',
          );
        }
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
}
