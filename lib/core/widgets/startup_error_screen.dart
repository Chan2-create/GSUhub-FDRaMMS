import 'package:flutter/material.dart';

import '../config/firebase_initializer.dart';

/// Shown when Firebase could not be initialized, in place of the app.
///
/// Deliberately plain — this is not designed UI, and manuscript §3.5's
/// figures are unresolved. It exists because the alternative to an ugly
/// error screen is a blank white window, which tells the user nothing and
/// tells a developer even less.
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    required this.failure,
    required this.onRetry,
    super.key,
  });

  final FirebaseStartupFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  failure.summary,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (failure.isEmulatorFailure) ...[
                  const Text(
                    'The app is running in emulator mode but could not '
                    'reach the Firebase Emulator Suite.',
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    'Start it with:\n    firebase emulators:start',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                ] else
                  const Text(
                    'Check your internet connection and try again. If this '
                    'keeps happening, contact the GSU administrator.',
                  ),
                const SizedBox(height: 16),
                SelectableText(
                  failure.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
