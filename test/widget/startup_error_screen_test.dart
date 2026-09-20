import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/config/firebase_initializer.dart';
import 'package:gsuhub/core/widgets/startup_error_screen.dart';

void main() {
  testWidgets('a configuration failure offers no retry', (tester) async {
    // `--dart-define` values are fixed at compile time, so a Retry button
    // here would re-run the same broken build and fail identically.
    await tester.pumpWidget(
      const StartupErrorScreen(
        failure: FirebaseStartupFailure(
          summary: 'Conflicting backend flags.',
          detail: 'USE_EMULATOR=true and USE_LIVE_FIREBASE=true',
          isConfigurationFailure: true,
        ),
      ),
    );

    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('invalid configuration'), findsOneWidget);
    expect(find.textContaining('internet connection'), findsNothing);
  });

  testWidgets('an emulator failure explains the fix and offers retry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      StartupErrorScreen(
        failure: const FirebaseStartupFailure(
          summary: 'Could not connect to the GSUhub backend.',
          detail: 'unavailable',
          isEmulatorFailure: true,
        ),
        onRetry: () => retried = true,
      ),
    );

    expect(find.textContaining('firebase emulators:start'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
