import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/routing/route_paths.dart';
import '../../../features/analytics/presentation/analytics_export.dart';
import '../../../features/analytics/presentation/analytics_providers.dart';

/// Top app bar (Figma node `196:743`, placed as in the dashboard frame):
/// a white header across the whole window, the GSUhub logo over the
/// sidebar's column, a white card with a soft shadow holding the section
/// name, live date, primary actions, bell and help, and the avatar on its
/// own at the right. The shell draws the gold rule under it, full width,
/// and the sidebar below that.
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
    this.showMenuButton = false,
    this.brandWidth,
  });

  final String pageTitle;

  /// Drives the red dot on the bell. Zero hides it.
  final int unreadNotifications;

  /// A page's own control, between the section name and the date.
  final Widget? pageControls;

  /// On a phone the sidebar is a drawer, opened from here.
  final bool showMenuButton;

  /// The logo's column: the sidebar's width beneath it, so the card
  /// starts where the sidebar ends. Null on a phone, where the bar is a
  /// single row behind the menu button and the logo gives way to the
  /// page's name.
  final double? brandWidth;

  /// The header's height, as drawn: the card and the white below it.
  static const double height = 80;

  /// The card's controls row, the original 52px bar.
  static const double _barHeight = 52;

  /// White above the controls row inside the card.
  static const double _cardInset = 17;

  /// Inside a card narrower than this, the bar keeps the page's name, its
  /// control, Export Data as an icon, and the bell. The date, the
  /// disabled Report New Damage and Help come back with the room.
  static const double _compactWidth = 640;

  @override
  Widget build(BuildContext context) {
    // The mockup reads "October 24, 2026" — a placeholder. Bound to the
    // real date.
    final today = DateFormat('MMMM d, y').format(DateTime.now());

    final brand = brandWidth;
    if (brand == null) {
      return Container(
        height: _barHeight,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: EdgeInsets.only(left: showMenuButton ? 4 : 24, right: 8),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _compact(context, constraints.maxWidth),
        ),
      );
    }

    // At the design's 1440 the card ends 96px short of the avatar; the
    // gap closes first as the window narrows.
    final avatarGap =
        ((Breakpoints.widthOf(context) - Breakpoints.expanded) * 0.3 + 24)
            .clamp(24.0, 96.0);

    return Container(
      height: height,
      color: AppColors.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Brand(width: brand),
          Expanded(child: _card(context, today)),
          SizedBox(width: avatarGap),
          const Padding(
            padding: EdgeInsets.only(top: _cardInset),
            child: SizedBox(
              height: _barHeight,
              child: Center(child: _Avatar()),
            ),
          ),
          const SizedBox(width: 25),
        ],
      ),
    );
  }

  /// The white card: flush with the top of the window, so only its
  /// rounded bottom edge and soft shadow show against the white header.
  Widget _card(BuildContext context, String today) => Container(
    height: _cardInset + _barHeight,
    padding: const EdgeInsets.only(top: _cardInset, left: 24, right: 8),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      boxShadow: [
        BoxShadow(
          color: AppColors.topBarShadow,
          offset: Offset(0, 2),
          blurRadius: 3,
          spreadRadius: -1,
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _compactWidth) {
          return _compact(context, constraints.maxWidth);
        }
        // The card's left part is the design's empty title frame; the
        // section name follows the divider, in the date's grey.
        final trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
            const SizedBox(width: 16),
            Semantics(
              header: true,
              child: Text(pageTitle, style: AppTextStyles.topBarMeta),
            ),
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
          ],
        );
        // At the design's width everything fits and this does nothing.
        // In a narrower window — or with a page control added, as
        // Analytics adds its period selector — the row scales down
        // together instead of overflowing the card.
        return Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: trailing,
          ),
        );
      },
    ),
  );

  Widget _compact(BuildContext context, double width) => Row(
    children: [
      if (showMenuButton) const _MenuButton(),
      Expanded(
        child: Text(
          pageTitle,
          style: AppTextStyles.topBarTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (width - 8 - (showMenuButton ? 48 : 0) - 96).clamp(
            0,
            double.infinity,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pageControls case final controls?) ...[
                controls,
                const SizedBox(width: 4),
              ],
              const _ExportDataButton(iconOnly: true),
              _NotificationBell(unreadCount: unreadNotifications),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The GSUhub logo over the sidebar's column, its mark spanning 126 x 42
/// and centred on the header's middle, as drawn.
class _Brand extends StatelessWidget {
  const _Brand({required this.width});

  final double width;

  /// The exported PNG is square with wide transparent margins: the mark
  /// fills its middle 85% across and 28% down, centred at 48% of its
  /// height.
  static const double _box = 148;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: AdminTopBar.height,
    child: const Stack(
      children: [
        Positioned(
          left: -1,
          top: AdminTopBar.height / 2 - _box * 0.482,
          width: _box,
          height: _box,
          child: Image(
            image: AssetImage('assets/images/gsuhub_logo.png'),
            fit: BoxFit.contain,
            semanticLabel: 'GSUhub',
          ),
        ),
      ],
    ),
  );
}

/// Opens the drawer that holds the sidebar on a phone.
class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Open navigation',
    onPressed: () => Scaffold.of(context).openDrawer(),
    icon: const Icon(Icons.menu, color: AppColors.textMuted),
  );
}

class _ExportDataButton extends ConsumerStatefulWidget {
  const _ExportDataButton({this.iconOnly = false});

  /// The export glyph alone, where the bar is narrow.
  final bool iconOnly;

  @override
  ConsumerState<_ExportDataButton> createState() => _ExportDataButtonState();
}

class _ExportDataButtonState extends ConsumerState<_ExportDataButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider);
    final message =
        'Download reports for the Analytics period '
        '(${range.label.toLowerCase()}) as a CSV file';
    if (widget.iconOnly) {
      return IconButton(
        tooltip:
            'Export Data: ${message[0].toLowerCase()}${message.substring(1)}',
        onPressed: _busy ? null : _export,
        icon: SvgPicture.asset(
          'assets/icons/topbar_export.svg',
          width: 14,
          height: 14,
          colorFilter: const ColorFilter.mode(
            AppColors.primary,
            BlendMode.srcIn,
          ),
        ),
      );
    }
    return Tooltip(
      message: message,
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
          // The notification centre (Objective 7.A, Figma 202:5608).
          onPressed: () => context.go(RoutePaths.adminNotifications),
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
