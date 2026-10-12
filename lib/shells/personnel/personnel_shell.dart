import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/result.dart';
import '../../core/widgets/offline_banner.dart';
import '../../features/notifications/presentation/notification_providers.dart';
import '../../features/reporting/presentation/submission/qr_scanner_screen.dart';
import '../mobile/mobile_bottom_bar.dart';
import '../mobile/mobile_header.dart';

/// The personnel app's four tabs (Figures 24 and 25: Home, Tasks,
/// Materials, Profile). Notifications open from the header's bell.
enum PersonnelTab {
  home(
    'Home',
    RoutePaths.personnelDashboard,
    Icons.home_outlined,
    Icons.home_rounded,
  ),
  tasks(
    'Tasks',
    RoutePaths.personnelTasks,
    Icons.assignment_outlined,
    Icons.assignment_rounded,
  ),
  materials(
    'Materials',
    RoutePaths.personnelMaterials,
    Icons.build_outlined,
    Icons.build_rounded,
  ),
  profile(
    'Profile',
    RoutePaths.personnelProfile,
    Icons.person_outline_rounded,
    Icons.person_rounded,
  );

  const PersonnelTab(this.label, this.path, this.icon, this.selectedIcon);

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  /// The tab [location] belongs to, or null. A work order's page sits
  /// under Home, where its card is; My Work Orders too.
  static PersonnelTab? of(String location) {
    if (location.startsWith(RoutePaths.personnelWorkOrders)) {
      return PersonnelTab.home;
    }
    for (final tab in values) {
      if (location == tab.path || location.startsWith('${tab.path}/')) {
        return tab;
      }
    }
    return null;
  }
}

/// The maintenance personnel app's frame (Objective 5.A; Figures 24–25):
/// the GSUhub header above, the floating bottom bar below — its gold "+"
/// opens the scanner (Chris, 2026-10-12) — and the page between.
class PersonnelShell extends ConsumerWidget {
  const PersonnelShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  /// Scans a code and opens what it identifies (5.C).
  static Future<void> scan(BuildContext context, WidgetRef ref) async {
    final code = await ref.read(qrScanLauncherProvider)(context);
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    await context.push(RoutePaths.personnelScanFor(code.trim()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = switch (ref.watch(unreadNotificationCountProvider).value) {
      Success(:final value) => value,
      _ => 0,
    };
    final tabs = [
      for (final tab in PersonnelTab.values)
        MobileTab(
          label: tab.label,
          path: tab.path,
          icon: tab.icon,
          selectedIcon: tab.selectedIcon,
        ),
    ];
    final current = PersonnelTab.of(location);

    final page = Scaffold(
      backgroundColor: AppColors.mobilePageBackground,
      extendBody: true,
      body: Column(
        children: [
          MobileHeader(
            alertsPath: RoutePaths.personnelAlerts,
            hasUnread: unread > 0,
          ),
          const OfflineBanner(),
          // A semantics container of its own, so the page route's modal
          // barrier does not hide the header from screen readers.
          Expanded(child: Semantics(container: true, child: child)),
        ],
      ),
      bottomNavigationBar: MobileBottomBar(
        tabs: tabs,
        location: location,
        selected: current == null ? null : tabs[current.index],
        actionLabel: 'Scan a code',
        onAction: () => scan(context, ref),
      ),
    );

    // Back from another tab returns Home, rather than closing the app.
    final isOtherTab =
        location != RoutePaths.personnelDashboard &&
        PersonnelTab.values.any((tab) => tab.path == location);
    if (!isOtherTab) return page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(RoutePaths.personnelDashboard);
      },
      child: page,
    );
  }
}

/// The bottom padding a page inside [PersonnelShell] needs so its last
/// item clears the floating bar.
double personnelBottomInset(BuildContext context) => mobileBottomInset(context);
