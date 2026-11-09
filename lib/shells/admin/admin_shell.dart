import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/breakpoints.dart';
import '../../core/di/service_providers.dart';
import '../../core/routing/route_paths.dart';
import '../../features/analytics/presentation/widgets/analytics_range_select.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/dashboard/presentation/dashboard_providers.dart';
import '../../features/inventory/presentation/inventory_providers.dart';
import 'widgets/admin_nav_items.dart';
import 'widgets/admin_sidebar.dart';
import 'widgets/admin_top_bar.dart';

/// Chrome around every admin screen: sidebar, top bar, gold accent rule,
/// and the routed content area (Figma node `196:534`).
///
/// 1.A left this as a bare router outlet; 2.A gives it the real layout.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.child, super.key});

  final Widget child;

  /// The logo's column beside the icon rail: the logo's own width.
  static const double _railBrandWidth = 150;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(authStateProvider).value;

    final unread = user == null
        ? 0
        : ref
                  .watch(unreadNotificationCountProvider(user.uid))
                  .value
                  ?.fold((count) => count, (_) => 0) ??
              0;

    // As drawn above Breakpoints.expanded; an icon rail on a tablet or a
    // small laptop; a drawer behind the top bar's menu button on a phone.
    final width = Breakpoints.widthOf(context);
    final drawer = width < Breakpoints.compact;
    final rail = !drawer && width < Breakpoints.expanded;
    AdminSidebar sidebar({bool rail = false}) => AdminSidebar(
      currentLocation: location,
      user: user,
      rail: rail,
      badges: {
        RoutePaths.adminInventory: ref.watch(lowStockCountProvider),
        RoutePaths.adminNotifications: unread,
      },
      onSignOut: () async {
        await ref.read(authControllerProvider.notifier).signOut();
        if (context.mounted) context.go(RoutePaths.adminLogin);
      },
    );

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      drawer: drawer
          ? Drawer(
              width: AdminSidebar.width.clamp(0, width - 56),
              shape: const RoundedRectangleBorder(),
              child: sidebar(),
            )
          : null,
      // As in the dashboard frame: the header and its gold rule run the
      // full width of the window, the logo over the sidebar's column, and
      // the sidebar starts beneath them.
      body: Column(
        children: [
          AdminTopBar(
            pageTitle: titleFor(location),
            unreadNotifications: unread,
            showMenuButton: drawer,
            // The logo needs 150px; the icon rail is narrower than that.
            brandWidth: drawer
                ? null
                : rail
                ? _railBrandWidth
                : AdminSidebar.width,
            pageControls: location.startsWith(RoutePaths.adminAnalytics)
                ? const AnalyticsRangeSelect()
                : null,
          ),
          // The gold rule the design runs beneath the top bar.
          Container(height: 13, color: AppColors.accentGold),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!drawer) sidebar(rail: rail),
                // A container of its own, so the page route's modal
                // barrier hides nothing outside it: without one, screen
                // readers lost the sidebar and the top bar.
                Expanded(child: Semantics(container: true, child: child)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Human-readable name for a route, taken from the sidebar definition so
  /// the two can never drift apart.
  static String titleFor(String location) {
    for (final group in adminNavGroups) {
      for (final item in group.items) {
        if (location.startsWith(item.path)) return item.label;
      }
    }
    return 'GSU Administration';
  }
}
