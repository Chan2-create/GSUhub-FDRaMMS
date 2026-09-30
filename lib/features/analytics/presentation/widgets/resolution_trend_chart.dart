import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../analytics_summary.dart';

/// "Average Resolution Time by Month" (Figma `85:4140`): a smoothed line
/// through each month's average, points marked, the change from the first
/// month with data to the last shown as a badge.
///
/// Hand-painted, like the dashboard's donut: one line and six points do not
/// justify a charting dependency, and a painter draws them as vectors, so
/// they stay sharp at any display density.
class ResolutionTrendChart extends StatelessWidget {
  const ResolutionTrendChart({required this.months, super.key});

  final List<MonthlyValue<double?>> months;

  /// "-72% Improvement" — the change from the first month with data to the
  /// last. Null with fewer than two such months.
  static ({String text, bool improved})? badgeFor(
    List<MonthlyValue<double?>> months,
  ) {
    final values = [for (final month in months) ?month.value];
    if (values.length < 2 || values.first <= 0) return null;
    final change = (values.last - values.first) / values.first * 100;
    final rounded = change.round();
    if (rounded == 0) return (text: 'No change', improved: true);
    return rounded < 0
        ? (text: '$rounded% Improvement', improved: true)
        : (text: '+$rounded% Slower', improved: false);
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMM');
    final described = months
        .map(
          (m) =>
              '${label.format(m.month)} '
              '${m.value == null ? 'none completed' : '${m.value!.toStringAsFixed(1)} days'}',
        )
        .join(', ');

    return Semantics(
      label: 'Average resolution time by month: $described',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 184,
            width: double.infinity,
            child: CustomPaint(painter: _LinePainter(months: months)),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              for (final month in months)
                Expanded(
                  child: Text(
                    label.format(month.month).toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.chartAxisLabel,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The badge in the chart card's corner.
class ResolutionBadge extends StatelessWidget {
  const ResolutionBadge({
    required this.text,
    required this.improved,
    super.key,
  });

  final String text;
  final bool improved;

  @override
  Widget build(BuildContext context) {
    final foreground = improved
        ? AppColors.statusResolvedForeground
        : AppColors.statusPendingForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: improved
            ? AppColors.trendGoodBackground
            : AppColors.trendBadBackground,
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTextStyles.chartBadge.copyWith(color: foreground),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.months});

  final List<MonthlyValue<double?>> months;

  static const double _pointRadius = 5.5;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final month in months) month.value];
    final present = [for (final value in values) ?value];
    if (present.isEmpty) return;

    var low = present.reduce((a, b) => a < b ? a : b);
    var high = present.reduce((a, b) => a > b ? a : b);
    if (high - low < 0.5) {
      // A flat or single-point series still gets a band to sit in, rather
      // than dividing by nothing.
      low -= 0.5;
      high += 0.5;
    }
    final pad = (high - low) * 0.15;
    low = (low - pad).clamp(0, double.infinity);
    high += pad;

    // One x slot per month, matching the labels beneath (each an equal
    // share of the width, point centred in it).
    final slot = size.width / values.length;
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        if (values[i] != null)
          Offset(
            slot * i + slot / 2,
            _pointRadius +
                (size.height - 2 * _pointRadius) *
                    (1 - (values[i]! - low) / (high - low)),
          ),
    ];

    final line = Paint()
      ..color = AppColors.chartLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.length > 1) canvas.drawPath(_smooth(points), line);

    final fill = Paint()..color = AppColors.chartLine;
    final ring = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in points) {
      canvas
        ..drawCircle(point, _pointRadius, fill)
        ..drawCircle(point, _pointRadius, ring);
    }
  }

  /// A Catmull-Rom curve through [points], as cubic Béziers — smooth like
  /// the design's line, and passing exactly through every month's value.
  static Path _smooth(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => oldDelegate.months != months;
}
