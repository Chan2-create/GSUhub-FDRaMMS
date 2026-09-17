import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Skip Firebase initialization while only the placeholder options
  // template is present, so the app still runs without a live Firebase
  // project during scaffolding. See core/config/firebase_options.dart.
  if (isPlaceholderFirebaseConfig) {
    if (kDebugMode) {
      debugPrint(
        'GSUhub: skipping Firebase.initializeApp — '
        'firebase_options.dart is still the placeholder template. '
        'Run `flutterfire configure` to connect a real project.',
      );
    }
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
      ],
      child: const GsuhubAdminApp(),
    ),
  );
}
