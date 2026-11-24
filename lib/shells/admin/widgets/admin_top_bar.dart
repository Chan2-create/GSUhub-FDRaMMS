import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/services/auth_service.dart';
import '../../../features/analytics/presentation/analytics_export.dart';
import '../../../features/analytics/presentation/analytics_providers.dart';
import 'admin_profile_menu.dart';

/// The console's header (Figma `196:743`, refined 2026-11-15): one white
/// bar across the whole window. The GSUhub logo over the sidebar's
/// column; after a hairline, the page's name and the date; at the right,
/// Export Data, the bell, Help, another hairline and
/// the account button. The shell draws the gold rule under it, full
/// width, and the sidebar below that.
///
/// The design's controls sat in a white card with its own shadow inside
/// the white header, which read as a second, floating bar (Chris,
/// 2026-11-15); the card is gone and its contents share the one bar.
///
/// Export Data downloads the Analytics CSV from any page (2.C). The
/// design's Report New Damage button was removed (Chris, 2026-11-25):
/// filing a report is a faculty and staff function (manuscript §1.5),
/// done from the mobile app, and it only ever showed disabled here.
///
/// [pageControls] is the slot a page fills with its own control, as
/// Analytics does with its period selector (Figma `87:4308`).
class AdminTopBar extends StatelessWidget {
  const AdminTopBar({
    required this.pageTitle,
    required this.unreadNotifications,
    required this.user,
    required this.onSignOut,
    super.key,
    this.pageControls,
    this.showMenuButton = false,
    this.brandWidth,
  });

  final String pageTitle;

  /// Drives the red dot on the bell. Zero hides it.
  final int unreadNotifications;

  /// Who is signed in, for the account menu at the right.
  final AuthUser? user;

  /// Ends the session, once Logout in the account menu is confirmed.
  final Future<void> Function() onSignOut;

  /// A page's own control, between the page's name and the date.
  final Widget? pageControls;

  /// On a phone the sidebar is a drawer, opened from here.
  final bool showMenuButton;

  /// The logo's column: the sidebar's width beneath it, so the page's
  /// name starts where the sidebar ends. Null on a phone, where the bar
  /// is a single row behind the menu button and the logo gives way to
  /// the page's name.
  final double? brandWidth;

  /// The header's height.
  static const double height = 64;

  /// The phone's bar.
  static const double _phoneBarHeight = 56;

  /// Narrower than this, the bar keeps the page's name, its control,
  /// Export Data as an icon, and the bell; the rest returns with the room.
  static const double _compactWidth = 640;

  /// The date needs this much room.
  static const double _dateWidth = 940;

  @override
  Widget build(BuildContext context) {
    // The mockup reads "October 24, 2026" — a placeholder. Bound to the
    // real date.
    final today = DateFormat('MMMM d, y').format(DateTime.now());

    final brand = brandWidth;
    if (brand == null) {
      return Container(
        height: _phoneBarHeight,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: EdgeInsets.only(left: showMenuButton ? 4 : 24, right: 8),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _compact(context, constraints.maxWidth, withAccount: true),
        ),
      );
    }

    return Container(
      height: height,
      color: AppColors.surface,
      child: Row(
        children: [
          _Brand(width: brand),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth < _compactWidth
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _compact(context, constraints.maxWidth - 16),
                    )
                  : _wide(context, constraints.maxWidth, today),
            ),
          ),
          const SizedBox(width: 8),
          const _Hairline(),
          const SizedBox(width: 12),
          AdminProfileMenu(user: user, onSignOut: onSignOut),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  /// The bar beside the logo: the page's name and the date at the left,
  /// the actions at the right. The actions scale down together rather
  /// than overflow in a window between the compact width and the full
  /// one, or with a page control added, as Analytics adds its period
  /// selector; at the design's width that does nothing.
  Widget _wide(BuildContext context, double width, String today) => Row(
    children: [
      const _Hairline(),
      const SizedBox(width: 20),
      Semantics(
        header: true,
        child: Text(pageTitle, style: AppTextStyles.topBarTitle),
      ),
      if (pageControls case final controls?) ...[
        const SizedBox(width: 16),
        controls,
      ],
      if (width >= _dateWidth) ...[
        const SizedBox(width: 20),
        SvgPicture.asset(
          'assets/icons/topbar_calendar.svg',
          width: 16,
          height: 18,
          colorFilter: const ColorFilter.mode(
            AppColors.textMuted,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 8),
        Text(today, style: AppTextStyles.topBarMeta),
      ],
      const SizedBox(width: 16),
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No Report New Damage (removed 2026-11-25): reports are
              // filed by faculty and staff from the phone app.
              const _ExportDataButton(),
              const SizedBox(width: 8),
              _NotificationBell(unreadCount: unreadNotifications),
              const _HelpButton(),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _compact(
    BuildContext context,
    double width, {
    bool withAccount = false,
  }) => Row(
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
              // On a phone the account menu, with Logout, is here: the
              // bar has no room for it outside. Beside the logo it is
              // not, since the account button stands at the right already.
              if (withAccount)
                AdminProfileMenu(
                  user: user,
                  onSignOut: onSignOut,
                  size: 30,
                  compact: true,
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// A one-pixel vertical rule, the header's only separators.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, color: AppColors.border);
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
