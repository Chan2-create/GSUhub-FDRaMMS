import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../features/analytics/presentation/analytics_export.dart';
import '../../../features/analytics/presentation/analytics_providers.dart';

/// Top app bar (Figma node `196:743`): page title, live date, primary
/// actions, notification bell, help, avatar.
///
/// Export Data downloads the Analytics CSV from any page (2.C). Report New
/// Damage renders disabled with a tooltip: filing a report is a faculty and
/// staff function (manuscript §1.5), done from the mobile app, and 2.B
/// found no documented admin path for it. It is shown because the design
/// shows it and its absence would misrepresent the layout.
///
/// [pageControls] is the slot a page fills with its own control, as
/// Analytics does with its period selector (Figma `87:4308`).
class AdminTopBar extends StatelessWidget {
  const AdminTopBar({
    required this.pageTitle,
    required this.unreadNotifications,
    super.key,
    this.pageControls,
  });

  final String pageTitle;

  /// Drives the red dot on the bell. Zero hides it.
  final int unreadNotifications;

  /// A page's own control, between the title and the date.
  final Widget? pageControls;

  /// Room the page title keeps before the actions start to scale down.
  static const double _minTitleWidth = 120;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
              const SizedBox(width: 16),
              if (pageControls case final controls?) ...[
                controls,
                const SizedBox(width: 16),
              ],
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
          );

          return Row(
            children: [
              // The design's leading title slot is an empty frame, followed
              // by a divider and the section name. The empty frame is
              // omitted — filling it with the route title too would print
              // the same word twice and, at the design's own 1440px width,
              // overflow the row by 69px once the 305px sidebar is
              // accounted for.
              Expanded(
                child: Text(
                  pageTitle,
                  style: AppTextStyles.topBarTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              // At the design's width everything fits and this does
              // nothing. In a narrower window — or with a page control
              // added, as Analytics adds its period selector — the actions
              // scale down together instead of overflowing the bar.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth - 16 - _minTitleWidth).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExportDataButton extends ConsumerStatefulWidget {
  const _ExportDataButton();

  @override
  ConsumerState<_ExportDataButton> createState() => _ExportDataButtonState();
}

class _ExportDataButtonState extends ConsumerState<_ExportDataButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider);
    return Tooltip(
      message:
          'Download reports for the Analytics period '
          '(${range.label.toLowerCase()}) as a CSV file',
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _export,
        icon: SvgPicture.asset(
          'assets/icons/topbar_export.svg',
          width: 12,
          height: 12,
          colorFilter: const ColorFilter.mode(
            AppColors.primary,
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

  Future<void> _export() async {
    setState(() => _busy = true);
    await ref.read(analyticsExportControllerProvider).export(context);
    if (mounted) setState(() => _busy = false);
  }
}

class _ReportNewDamageButton extends StatelessWidget {
  const _ReportNewDamageButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message:
        'Reports are submitted by faculty and staff from the mobile app — '
        'not from the admin console.',
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
