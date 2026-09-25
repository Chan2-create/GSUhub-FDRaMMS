import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/features/analytics/presentation/analytics_summary.dart';
import 'package:gsuhub/features/analytics/presentation/widgets/building_bars.dart';

/// "Reports by Building" draws each bar from the left edge of a full-width
/// track, scaled against the busiest building.
void main() {
  testWidgets('bars start at the track edge and scale to the busiest', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: BuildingBars(
                buildings: [
                  BuildingCount(facilityName: 'Main Library', count: 4),
                  BuildingCount(facilityName: 'Gymnasium', count: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final chart = find.byType(BuildingBars);
    final tracks = find.descendant(
      of: chart,
      matching: find.byType(ColoredBox),
    );
    final fills = find.descendant(
      of: tracks,
      matching: find.byType(DecoratedBox),
    );
    expect(tracks, findsNWidgets(2));

    final trackRects = [
      for (var i = 0; i < 2; i++) tester.getRect(tracks.at(i)),
    ];
    final fillRects = [for (var i = 0; i < 2; i++) tester.getRect(fills.at(i))];

    for (final track in trackRects) {
      expect(track.width, 400, reason: 'the track spans the card');
    }
    // Left-aligned, not centred.
    expect(fillRects[0].left, trackRects[0].left);
    expect(fillRects[1].left, trackRects[1].left);
    // The busiest fills the track; half as many fills half of it.
    expect(fillRects[0].width, 400);
    expect(fillRects[1].width, 200);
  });
}
