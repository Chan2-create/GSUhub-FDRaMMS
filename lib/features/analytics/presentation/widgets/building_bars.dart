import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../analytics_summary.dart';

/// "Reports by Building" (Figma `85:4095`): the busiest locations as
/// horizontal bars, each scaled against the busiest.
///
/// The design fades each bar a step from the one above — primary navy at
/// 7/7, 6/7, 5/7, 4/7 and 3/7 opacity, which is exactly what its five fills
/// measure — so rank reads at a glance as well as by length.
class BuildingBars extends StatelessWidget {
  const BuildingBars({required this.buildings, super.key});

  final List<BuildingCount> buildings;

  @override
  Widget build(BuildContext context) {
    final peak = buildings.isEmpty ? 0 : buildings.first.count;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buildings.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _BuildingBar(
            building: buildings[i],
            fraction: peak == 0 ? 0 : buildings[i].count / peak,
            // Blended against white, not the track, which is what the
            // design's solid fills measure.
            color: Color.alphaBlend(
              AppColors.primary.withValues(alpha: (7 - i) / 7),
              AppColors.surface,
            ),
          ),
        ],
      ],
    );
  }
}

class _BuildingBar extends StatelessWidget {
  const _BuildingBar({
    required this.building,
    required this.fraction,
    required this.color,
  });

  final BuildingCount building;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              building.facilityName.toUpperCase(),
              style: AppTextStyles.barRowLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text('${building.count}', style: AppTextStyles.barRowValue),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // Full width, stated: the parent column centres and loosens its
        // children, and a fractional fill in a loose box shrinks the whole
        // track down to the fill.
        child: SizedBox(
          width: double.infinity,
          height: 8,
          child: ColoredBox(
            color: AppColors.trackBackground,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
