import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// One slice of the category donut.
class CategorySlice {
  const CategorySlice({
    required this.label,
    required this.count,
    required this.share,
  });

  final String label;
  final int count;

  /// 0.0–1.0 share of the total.
  final double share;
}

/// "Reports by Category" donut with a centre total and a two-column
/// legend (Figma node `196:591`).
///
/// Hand-drawn with a [CustomPainter] rather than pulling in a charting
/// package: this is one static ring with no axes, tooltips or animation,
/// and a dependency would bring far more surface area than the ~40 lines
/// it replaces.
///
/// Shared since 2.C: Analytics draws the same ring, smaller, with its
/// legend beside it and each slice's share spelled out (Figma `85:4046`).
/// Colours are dealt by rank in both, so the same data reads the same on
/// both screens.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({required this.slices, super.key}) : _beside = false;

  /// The Analytics layout: a 160px ring with the legend to its right.
  const CategoryDonut.besideLegend({required this.slices, super.key})
    : _beside = true;

  final List<CategorySlice> slices;
  final bool _beside;

  static const double _size = 192;
  static const double _strokeWidth = 32;
  static const double _besideSize = 160;
  static const double _besideStrokeWidth = 20;

  int get _total => slices.fold<int>(0, (sum, slice) => sum + slice.count);

  @override
  Widget build(BuildContext context) => _beside ? _besideLegend() : _stacked();

  Widget _besideLegend() => Row(
    children: [
      SizedBox.square(
        dimension: _besideSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(_besideSize),
              painter: _DonutPainter(
                slices: slices,
                strokeWidth: _besideStrokeWidth,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_total', style: AppTextStyles.donutCenterValue),
                const Text('TOTAL', style: AppTextStyles.chartAxisLabel),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 32),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < slices.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ShareRow(slice: slices[i], color: colorFor(i)),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _stacked() {
    final total = _total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(_size),
                painter: _DonutPainter(
                  slices: slices,
                  strokeWidth: _strokeWidth,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: AppTextStyles.chartCenterValue),
                  const Text('TOTAL', style: AppTextStyles.captionUpper),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Legend(slices: slices),
      ],
    );
  }

  /// Colour for the slice at [index], wrapping to a neutral once the
  /// palette is exhausted.
  static Color colorFor(int index) => index < AppColors.categorySeries.length
      ? AppColors.categorySeries[index]
      : AppColors.categoryOther;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.strokeWidth});

  final List<CategorySlice> slices;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Starts at 12 o'clock and runs clockwise, matching the design.
    var startAngle = -math.pi / 2;

    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].share * 2 * math.pi;
      canvas.drawArc(
        rect,
        startAngle,
        // A hairline gap between slices keeps adjacent colours legible
        // without a separate divider stroke. Not applied to a single
        // full-circle slice, which would otherwise show a notch.
        slices.length == 1 ? sweep : sweep - 0.02,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = CategoryDonut.colorFor(i),
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.strokeWidth != strokeWidth;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.slices});

  final List<CategorySlice> slices;

  @override
  Widget build(BuildContext context) {
    // Two equal columns, as the design lays them out, each taking half the
    // width the card actually has. An earlier version pinned items to 110px,
    // which fit the mockup's short labels and truncated real ones ("Air
    // Conditioni..."); the obvious replacement, a LayoutBuilder, cannot be
    // used here — the dashboard wraps this row in an IntrinsicHeight, and
    // LayoutBuilder throws when asked for intrinsic dimensions. Plain flex
    // answers those queries, so Expanded does the same job safely.
    //
    // Indices are dealt out column-wise so the entries still read left to
    // right, row by row: 0 1 / 2 3.
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < slices.length; i++) {
      final column = i.isEven ? left : right;
      if (column.isNotEmpty) column.add(const SizedBox(height: 12));
      column.add(
        _LegendEntry(slice: slices[i], color: CategoryDonut.colorFor(i)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: left,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: right,
          ),
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.slice, required this.color});

  final CategorySlice slice;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '${slice.label} (${(slice.share * 100).round()}%)',
          style: AppTextStyles.legendLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// A legend row in the Analytics layout: square key, name, and the share
/// right-aligned.
class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.slice, required this.color});

  final CategorySlice slice;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          slice.label,
          style: AppTextStyles.legendName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      Text('${(slice.share * 100).round()}%', style: AppTextStyles.legendShare),
    ],
  );
}
