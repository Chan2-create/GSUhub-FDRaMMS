import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../dashboard_providers.dart';

/// "Monthly Report Volume by Building" — one horizontal bar per facility,
/// split into this month and last (Figma node `196:781`).
class BuildingVolumeChart extends StatelessWidget {
  const BuildingVolumeChart({required this.volumes, super.key});

  final List<BuildingVolume> volumes;

  @override
  Widget build(BuildContext context) {
    // Bars are scaled against the busiest building rather than the sum,
    // so the longest bar fills the track and the comparison between
    // buildings stays readable.
    final maxTotal = volumes
        .map((volume) => volume.total)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final volume in volumes) ...[
          _Bar(volume: volume, maxTotal: maxTotal),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.volume, required this.maxTotal});

  final BuildingVolume volume;
  final int maxTotal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              volume.facilityName,
              style: AppTextStyles.barLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${volume.currentMonth} '
            'Report${volume.currentMonth == 1 ? '' : 's'}',
            style: AppTextStyles.barLabel,
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 10,
          child: ColoredBox(
            color: AppColors.trackBackground,
            child: Row(
              children: [
                Flexible(
                  flex: volume.currentMonth,
                  child: Container(color: AppColors.primary),
                ),
                Flexible(
                  flex: volume.previousMonth,
                  child: Container(color: AppColors.trackComparison),
                ),
                // Remainder of the track, so a quiet building's bar is
                // visibly shorter than a busy one's.
                Flexible(
                  flex: (maxTotal - volume.total).clamp(0, maxTotal),
                  child: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

/// The "CURRENT MONTH / PREVIOUS MONTH" key shown in the card header.
class BuildingVolumeLegend extends StatelessWidget {
  const BuildingVolumeLegend({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _LegendKey(color: AppColors.primary, label: 'CURRENT MONTH'),
      SizedBox(width: 8),
      _LegendKey(color: AppColors.trackComparison, label: 'PREVIOUS MONTH'),
    ],
  );
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppTextStyles.legendKeyUpper),
    ],
  );
}
