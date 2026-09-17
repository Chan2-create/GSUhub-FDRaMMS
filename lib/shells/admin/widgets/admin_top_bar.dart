import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Top app bar (Figma node `196:743`): page title, live date, primary
/// actions, notification bell, help, avatar.
///
/// Two buttons render disabled with tooltips — Export Data belongs to
/// Objective 2.C and Report New Damage to 2.B. They are shown because the
/// design shows them and their absence would misrepresent the layout, but
/// they do nothing yet and say so.
class AdminTopBar extends StatelessWidget {
  const AdminTopBar({
    required this.pageTitle,
    required this.unreadNotifications,
    super.key,
  });

  final String pageTitle;

  /// Drives the red dot on the bell. Zero hides it.
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    // The mockup reads "October 24, 2026" — a placeholder. Bound to the
    // real date.
    final today = DateFormat('MMMM d, y').format(DateTime.now());

    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          // The design's leading title slot is an empty frame, followed by
          // a divider and the section name. The empty frame is omitted —
          // filling it with the route title too would print the same word
          // twice and, at the design's own 1440px width, overflow the row
          // by 69px once the 305px sidebar is accounted for.
          Expanded(
            child: Text(
              pageTitle,
              style: AppTextStyles.topBarTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
          const SizedBox(width: 16),
          SvgPicture.asset(
            'assets/icons/topbar_calendar.svg',
            width: 18,
            height: 20,
            colorFilter: const ColorFilter.mode(
              AppColors.textMuted,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 8),
          Text(today, style: AppTextStyles.topBarMeta),
          const SizedBox(width: 24),
          const _ExportDataButton(),
          const SizedBox(width: 12),
          const _ReportNewDamageButton(),
          const SizedBox(width: 12),
          _NotificationBell(unreadCount: unreadNotifications),
          const _HelpButton(),
          const SizedBox(width: 8),
          const _Avatar(),
        ],
      ),
    );
  }
}

class _ExportDataButton extends StatelessWidget {
  const _ExportDataButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Exporting reports arrives in Objective 2.C.',
    child: OutlinedButton.icon(
      onPressed: null,
      icon: SvgPicture.asset(
        'assets/icons/topbar_export.svg',
        width: 12,
        height: 12,
        colorFilter: const ColorFilter.mode(
          AppColors.textFaint,
          BlendMode.srcIn,
        ),
      ),
      label: const Text('Export Data', style: AppTextStyles.buttonLabel),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
  );
}

class _ReportNewDamageButton extends StatelessWidget {
  const _ReportNewDamageButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Creating reports from the admin console arrives in 2.B.',
    child: FilledButton.icon(
      onPressed: null,
      icon: SvgPicture.asset(
        'assets/icons/topbar_add.svg',
        width: 11,
        height: 11,
        colorFilter: const ColorFilter.mode(
          AppColors.ctaAmberForeground,
          BlendMode.srcIn,
        ),
      ),
      label: const Text('Report New Damage', style: AppTextStyles.buttonLabel),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ctaAmber,
        foregroundColor: AppColors.ctaAmberForeground,
        disabledBackgroundColor: AppColors.ctaAmber.withValues(alpha: 0.5),
        disabledForegroundColor: AppColors.ctaAmberForeground.withValues(
          alpha: 0.7,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
  );
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: unreadCount == 0
        ? 'No unread notifications'
        : '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}',
    child: Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          // Reading the notification centre is a later objective; the
          // badge itself is live.
          onPressed: null,
          icon: SvgPicture.asset(
            'assets/icons/topbar_bell.svg',
            width: 16,
            height: 20,
            colorFilter: const ColorFilter.mode(
              AppColors.textMuted,
              BlendMode.srcIn,
            ),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.notificationBadge,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface),
              ),
            ),
          ),
      ],
    ),
  );
}

class _HelpButton extends StatelessWidget {
  const _HelpButton();

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: null,
    tooltip: 'Help',
    icon: SvgPicture.asset(
      'assets/icons/topbar_help.svg',
      width: 20,
      height: 20,
      colorFilter: const ColorFilter.mode(AppColors.textMuted, BlendMode.srcIn),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 36,
    decoration: const BoxDecoration(
      color: AppColors.accentGold,
      shape: BoxShape.circle,
    ),
  );
}
