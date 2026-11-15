import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/widgets/launch_splash.dart';

/// The logo over the first frames (§38): shown while the session is
/// being restored and for its own entrance, then gone.
void main() {
  late StreamController<AuthUser?> auth;

  setUp(() => auth = StreamController<AuthUser?>());
  tearDown(() => auth.close());

  // The logo is transparent for its first frame, and a transparent
  // widget has no semantics, so presence is by key and the label is
  // checked once it shows.
  Finder logo() => find.byKey(const ValueKey('launch-logo'));
  final page = find.text('PAGE');

  Future<void> pump(
    WidgetTester tester, {
    bool reducedMotion = false,
    Widget page = const Scaffold(body: Text('PAGE')),
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => auth.stream)],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: MaterialApp(home: LaunchSplash(child: page)),
      ),
    ),
  );

  testWidgets('covers the page until the session is known, then leaves', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(logo(), findsOneWidget);

    // Its entrance is over; the session is still unknown: it stays, and
    // says what it is.
    await tester.pump(LaunchSplash.entrance);
    await tester.pump(const Duration(seconds: 2));
    expect(logo(), findsOneWidget);
    expect(find.bySemanticsLabel('GSUhub is starting'), findsOneWidget);

    auth.add(null);
    await tester.pumpAndSettle();
    expect(logo(), findsNothing);
    expect(page, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('with the session known at once, it stays only for its '
      'entrance', (tester) async {
    final semantics = tester.ensureSemantics();
    auth.add(null);
    await pump(tester);
    await tester.pump();
    expect(logo(), findsOneWidget, reason: 'the entrance plays out');

    await tester.pump(LaunchSplash.entrance);
    await tester.pump(LaunchSplash.entrance);
    await tester.pump(LaunchSplash.exit);
    await tester.pump(LaunchSplash.exit);
    await tester.pump();
    expect(logo(), findsNothing);
    semantics.dispose();
  });

  testWidgets('settles for tests that wait, and leaves no timer', (
    tester,
  ) async {
    auth.add(null);
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(LaunchSplash), findsOneWidget);
    expect(logo(), findsNothing);
  });

  testWidgets('the page under it is built once, and kept when it leaves', (
    tester,
  ) async {
    // Returning the page on its own once the logo had gone moved it in
    // the tree, and every page and listener under it was built again:
    // the report page's test counted three listeners where two belong.
    var built = 0;
    auth.add(null);
    await pump(tester, page: _Counted(onInit: () => built++));
    await tester.pumpAndSettle();

    expect(logo(), findsNothing);
    expect(page, findsOneWidget);
    expect(built, 1);
  });

  testWidgets('under reduced motion the logo does not scale', (tester) async {
    await pump(tester, reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 100));

    // The one around the logo: the page's own route transition scales too.
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: logo(), matching: find.byType(ScaleTransition)).first,
    );
    expect(scale.scale.value, 1);
  });
}

/// A page that counts how often it is built from scratch.
class _Counted extends StatefulWidget {
  const _Counted({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('PAGE'));
}
