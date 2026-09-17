// ignore_for_file: lines_longer_than_80_chars
//
// Committed TEMPLATE — documents the shape FlutterFire CLI generates.
// This file is never imported by the app; it exists purely as a reference
// so a fresh clone knows what `firebase_options.dart` (gitignored, see
// .gitignore) is expected to contain once generated.
//
// To generate the real file:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// That command creates a Firebase project (or links an existing one),
// registers Android + Web apps, and overwrites
// lib/core/config/firebase_options.dart with real, project-specific
// values. Do not hand-edit the generated file; re-run `flutterfire
// configure` if the Firebase project changes.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Set to `false` by the real, generated `firebase_options.dart`. Callers
/// (see `app.dart`) use this to skip `Firebase.initializeApp` when only
/// this placeholder template is present, so the app still runs without a
/// live Firebase project.
const bool isPlaceholderFirebaseConfig = true;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// GSUhub targets Android and web only (manuscript §3.2 Technical
  /// Feasibility) — no iOS/desktop options are generated.
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError(
      'DefaultFirebaseOptions have not been configured for '
      '$defaultTargetPlatform. GSUhub targets Android and web only.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'PLACEHOLDER_API_KEY',
    appId: 'PLACEHOLDER_APP_ID',
    messagingSenderId: 'PLACEHOLDER_SENDER_ID',
    projectId: 'PLACEHOLDER_PROJECT_ID',
    authDomain: 'placeholder.firebaseapp.com',
    storageBucket: 'placeholder.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PLACEHOLDER_API_KEY',
    appId: 'PLACEHOLDER_APP_ID',
    messagingSenderId: 'PLACEHOLDER_SENDER_ID',
    projectId: 'PLACEHOLDER_PROJECT_ID',
    storageBucket: 'placeholder.appspot.com',
  );
}
