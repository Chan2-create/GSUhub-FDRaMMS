import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/di/service_providers.dart';
import '../../core/routing/route_paths.dart';
import '../../features/analytics/presentation/widgets/analytics_range_select.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/dashboard/presentation/dashboard_providers.dart';
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

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSidebar(
            currentLocation: location,
            user: user,
            onSignOut: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go(RoutePaths.adminLogin);
            },
          ),
          Expanded(
            child: Column(
              children: [
                AdminTopBar(
                  pageTitle: titleFor(location),
                  unreadNotifications: unread,
                  pageControls: location.startsWith(RoutePaths.adminAnalytics)
                      ? const AnalyticsRangeSelect()
                      : null,
                ),
                // The gold rule the design runs beneath the top bar.
                Container(height: 13, color: AppColors.accentGold),
                Expanded(child: child),
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
