import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../map/report_map.dart';
import '../map/report_map_providers.dart';

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

/// "Need urgent assistance?" (Figma `198:2991`).
///
/// Rendered as designed, with the action disabled: dispatching an
/// emergency team appears nowhere in the manuscript's requirements, so
/// there is no defined recipient, channel or record for it. Shown because
/// the design shows it; inert because nothing behind it exists.
class EmergencyCard extends StatelessWidget {
  const EmergencyCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.fromLTRB(24, 23, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Need urgent assistance?',
          style: AppTextStyles.emergencyTitle,
        ),
        const SizedBox(height: 12),
        const Text(
          'For immediate safety hazards or structural emergencies, contact '
          'the 24/7 Facility Response Unit.',
          style: AppTextStyles.emergencyBody,
        ),
        const SizedBox(height: 48),
        Tooltip(
          message:
              'Emergency dispatch is not part of the documented GSU '
              'requirements — flagged for the adviser.',
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: null,
              icon: SvgPicture.asset(
                'assets/icons/emergency_phone.svg',
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(
                  AppColors.ctaAmberForeground,
                  BlendMode.srcIn,
                ),
              ),
              label: const Text(
                'Dispatch Emergency Team',
                style: AppTextStyles.ctaLabel,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ctaAmber,
                foregroundColor: AppColors.ctaAmberForeground,
                disabledBackgroundColor: AppColors.ctaAmber.withValues(
                  alpha: 0.5,
                ),
                disabledForegroundColor: AppColors.ctaAmberForeground
                    .withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
