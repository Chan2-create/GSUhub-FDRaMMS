import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../dashboard_providers.dart';

/// "Reports by Category" donut with a centre total and a two-column
/// legend (Figma node `196:591`).
///
/// Hand-drawn with a [CustomPainter] rather than pulling in a charting
/// package: this is one static ring with no axes, tooltips or animation,
/// and a dependency would bring far more surface area than the ~40 lines
/// it replaces.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({required this.slices, super.key});

  final List<CategorySlice> slices;

  static const double _size = 192;
  static const double _strokeWidth = 32;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.count);

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
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 12,
    children: [
      for (var i = 0; i < slices.length; i++)
        SizedBox(
          width: 110,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: CategoryDonut.colorFor(i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${slices[i].label} '
                  '(${(slices[i].share * 100).round()}%)',
                  style: AppTextStyles.legendLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
