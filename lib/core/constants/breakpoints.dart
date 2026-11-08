import 'package:flutter/widgets.dart';

/// The console's window widths (responsive pass, 2026-11-08). The Figma
/// frames are drawn at 1440; above [expanded] the console is laid out as
/// drawn, and below it the same screens make room.
abstract final class Breakpoints {
  /// Below this, a phone: the sidebar becomes a drawer behind a menu
  /// button, and pages keep a narrower margin.
  static const double compact = 720;

  /// From this, the design's full sidebar; between [compact] and here, a
  /// rail of its icons.
  static const double expanded = 1200;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) => widthOf(context) < compact;

  /// A page's side margin: the design's 32, or 16 on a phone.
  static double gutter(BuildContext context) => isCompact(context) ? 16 : 32;

  /// How many equal columns of at least [minWidth] fit in [width], at most
  /// [max]: the stat-card rows and card grids.
  static int columnsFor(
    double width, {
    required double minWidth,
    required int max,
    double gap = 24,
  }) => ((width + gap) / (minWidth + gap)).floor().clamp(1, max);
}
