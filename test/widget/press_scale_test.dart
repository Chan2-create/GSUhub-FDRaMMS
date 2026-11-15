import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/widgets/press_scale.dart';

/// The phone's buttons shrink a little under the finger (§38), and the
/// button underneath still gets its tap.
void main() {
  Future<void> pump(
    WidgetTester tester,
    VoidCallback onPressed, {
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressScale(
              child: FilledButton(
                onPressed: onPressed,
                child: const Text('Tap me'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('shrinks while pressed, and the tap still lands', (tester) async {
    var taps = 0;
    await pump(tester, () => taps++);
    expect(scaleOf(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tap me')),
    );
    await tester.pump();
    expect(scaleOf(tester), 0.97);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
    expect(taps, 1);
  });

  testWidgets('a cancelled press lets go too', (tester) async {
    await pump(tester, () {});
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tap me')),
    );
    await tester.pump();
    expect(scaleOf(tester), 0.97);

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });

  testWidgets('does not move under reduced motion', (tester) async {
    await pump(tester, () {}, reducedMotion: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tap me')),
    );
    await tester.pump();
    expect(scaleOf(tester), 1);
    await gesture.up();
  });
}
