import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

/// "Campus View" (Figma `198:2968`), as a placeholder.
///
/// The design shows an interactive campus map with per-building density
/// bars. Neither exists yet: the project has no map dependency, and
/// "density" is not a figure anything in the data model produces. Adding a
/// map library is a decision with licensing, API-key and offline
/// consequences, so the panel keeps its place in the layout and says what
/// it is waiting for rather than drawing invented data.
class CampusViewCard extends StatelessWidget {
  const CampusViewCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
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
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Campus View', style: AppTextStyles.panelHeading),
              SizedBox(height: 4),
              Text(
                'Detailed overview of campus buildings and facilities for '
                'rapid navigation.',
                style: AppTextStyles.bodyText,
              ),
            ],
          ),
        ),
        const Expanded(
          child: ColoredBox(
            color: Color(0xFFEFF4FF),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 40,
                      color: AppColors.textFaint,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Campus map pending a decision on a mapping library.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
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
