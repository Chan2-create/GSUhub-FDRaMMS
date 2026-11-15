import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/widgets/reduced_motion_transitions.dart';

/// Page transitions step aside under reduced motion (§39), and are the
/// platform's own otherwise. Checked against a marked transition rather
/// than a real one: the platforms' transitions paint through snapshots,
/// with nothing in the tree to find.
void main() {
  const wrapped = ReducedMotionTransitions(_Marked());

  Future<void> pushNext(WidgetTester tester, {required bool reduced}) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {TargetPlatform.android: wrapped},
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('NEXT')),
                  ),
                ),
                child: const Text('GO'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder markedAround(Finder finder) => find.ancestor(
    of: finder,
    matching: find.byKey(const ValueKey('incoming')),
  );

  testWidgets('the new page arrives through the platform\'s transition', (
    tester,
  ) async {
    await pushNext(tester, reduced: false);
    expect(markedAround(find.text('NEXT')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('under reduced motion it is simply there', (tester) async {
    await pushNext(tester, reduced: true);
    expect(find.text('NEXT'), findsOneWidget);
    expect(markedAround(find.text('NEXT')), findsNothing);
    await tester.pumpAndSettle();
  });

  test('keeps the platform\'s timing', () {
    expect(wrapped.transitionDuration, const Duration(milliseconds: 123));
    expect(wrapped.reverseTransitionDuration, const Duration(milliseconds: 77));
  });

  testWidgets('the outgoing page\'s transition steps aside too', (
    tester,
  ) async {
    late BuildContext reduced;
    late BuildContext welcome;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  reduced = context;
                  return const SizedBox();
                },
              ),
            ),
            Builder(
              builder: (context) {
                welcome = context;
                return const SizedBox();
              },
            ),
          ],
        ),
      ),
    );

    final delegated = wrapped.delegatedTransition!;
    // The same each time it is asked for, so routes see no change.
    expect(wrapped.delegatedTransition, delegated);

    const page = SizedBox(key: ValueKey('page'));
    expect(
      delegated(
        reduced,
        kAlwaysCompleteAnimation,
        kAlwaysDismissedAnimation,
        false,
        page,
      ),
      same(page),
    );
    expect(
      delegated(
        welcome,
        kAlwaysCompleteAnimation,
        kAlwaysDismissedAnimation,
        false,
        page,
      )!.key,
      const ValueKey('outgoing'),
    );
  });

  test('a platform without an outgoing transition still has none', () {
    expect(
      const ReducedMotionTransitions(CupertinoLikeWithoutDelegate())
          .delegatedTransition,
      isNull,
    );
  });
}

/// A transition that marks what it builds, with timings of its own.
class _Marked extends PageTransitionsBuilder {
  const _Marked();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 123);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 77);

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _outgoing;

  static Widget? _outgoing(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) => KeyedSubtree(
    key: const ValueKey('outgoing'),
    child: child ?? const SizedBox(),
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    key: const ValueKey('incoming'),
    opacity: animation,
    child: child,
  );
}

/// A transition with no outgoing part, as most platforms' are.
class CupertinoLikeWithoutDelegate extends PageTransitionsBuilder {
  const CupertinoLikeWithoutDelegate();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
