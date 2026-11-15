import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../map_view/presentation/report_map.dart';
import '../../../map_view/presentation/report_map_providers.dart';

/// "Campus View" (Figma `198:2968`): a still preview of Map View.
///
/// The design shows an interactive campus map with per-building density
/// bars. "Density" is not a figure the data model or the manuscript
/// produces, so the panel draws what Map View draws, the open reports'
/// geo-tags, and leads there for the rest (2026-11-12; until then it was
/// a placeholder waiting on a mapping library, which the faculty and
/// staff app's geo-tag preview has since settled).
class CampusViewCard extends ConsumerWidget {
  const CampusViewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    height: 422,
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Container(
          width: 210,
          height: double.infinity,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.borderStrong)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Campus View', style: AppTextStyles.panelHeading),
              const SizedBox(height: 4),
              const Text(
                'Where the open geo-tagged reports were filed on campus.',
                style: AppTextStyles.bodyText,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.go(RoutePaths.adminMapView),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: const Text('Open Map View'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFEFF4FF),
            child: AsyncValueView<ReportMapData>(
              value: ref.watch(openReportMapProvider),
              isEmpty: (data) => data.located.isEmpty,
              emptyIcon: Icons.map_outlined,
              emptyMessage: 'No open report has a geo-tag to show.',
              loadingHeight: 420,
              data: (data) =>
                  ReportMap(reports: data.located, interactive: false),
            ),
          ),
        ),
      ],
    ),
  );
}
