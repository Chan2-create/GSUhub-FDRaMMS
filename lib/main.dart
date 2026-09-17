import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_initializer.dart';
import 'core/di/service_providers.dart';
import 'core/services/firebase/fcm_notification_service.dart';
import 'core/widgets/startup_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startApp();
}

/// Runs the startup sequence, rendering either the app or an error screen.
///
/// Firebase is initialized *before* the router mounts, because every route
/// guard and repository the app builds needs working handles. Starting the
/// UI first and initializing in the background would mean the first frame
/// renders against services that may not exist yet.
Future<void> _startApp() async {
  final config = AppConfig.fromEnvironment();
  final startup = await FirebaseInitializer.initialize(config);

  switch (startup) {
    case FirebaseStartupFailure():
      // Retry re-runs the whole sequence rather than only reconnecting:
      // the usual cause is "emulators were not running yet", and by the
      // time the user taps Retry they have started them.
      runApp(StartupErrorScreen(failure: startup, onRetry: _startApp));

    case FirebaseStartupSuccess():
      // Registered before runApp so a notification that cold-starts the
      // app is not missed. Web has its own service worker
      // (web/firebase-messaging-sw.js) and rejects this handler.
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }

      runApp(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            firebaseStartupProvider.overrideWithValue(startup),
          ],
          child: const GsuhubApp(),
        ),
      );
  }
}
