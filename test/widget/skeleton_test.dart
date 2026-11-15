import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/core/widgets/async_value_view.dart';
import 'package:gsuhub/core/widgets/skeleton.dart';

/// Skeletons in place of spinners (§38): the shape of the content while
/// it loads, one thing to a screen reader, still under reduced motion.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );

  testWidgets('stands in for the data while it loads, then gives way', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Widget view(AsyncValue<Result<List<String>>> value) =>
        AsyncValueView<List<String>>(
          value: value,
          loading: Skeleton.cards(count: 2, height: 80),
          data: (items) => Text(items.join(', ')),
        );

    await pump(tester, view(const AsyncLoading()));
    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    await pump(tester, view(const AsyncData(Result.success(['one', 'two']))));
    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('one, two'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('without one, the spinner is still the default', (tester) async {
    await pump(
      tester,
      AsyncValueView<int>(
        value: const AsyncLoading(),
        data: (value) => Text('$value'),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the sheen moves, and holds still under reduced motion', (
    tester,
  ) async {
    await pump(tester, Skeleton.lines());
    final before = tester.widget<ShaderMask>(find.byType(ShaderMask));
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester.widget<ShaderMask>(find.byType(ShaderMask));
    expect(
      identical(before, after),
      isFalse,
      reason: 'a new mask each frame as the band moves',
    );

    await pump(tester, Skeleton.lines(), reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a block of lines ends in a shorter one', (tester) async {
    await pump(tester, Skeleton.lines());
    final lines = tester
        .widgetList<SkeletonLine>(find.byType(SkeletonLine))
        .toList();
    expect(lines, hasLength(3));
    expect(lines.last.widthFactor, lessThan(lines.first.widthFactor));
  });
}
