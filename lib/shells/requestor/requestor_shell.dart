import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/routing/route_paths.dart';
import '../../core/utils/result.dart';
import '../../core/widgets/offline_banner.dart';
import '../../features/notifications/presentation/notification_providers.dart';
import '../mobile/mobile_bottom_bar.dart';
import '../page_refresh.dart';
import 'requestor_bottom_bar.dart';
import 'requestor_header.dart';

/// The faculty and staff app's frame around its tabs (Objective 3.A,
/// Figma `170:2050`): the GSUhub header above, the floating bottom bar
/// below, the tab's page between.
///
/// The report form (3.C) opens over this rather than inside it — its frame
/// has no bottom bar — and the sign-in pages sit outside it altogether.
class RequestorShell extends ConsumerWidget {
  const RequestorShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// The current location, for the bar's highlight and the back button.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = switch (ref.watch(unreadNotificationCountProvider).value) {
      Success(:final value) => value,
      _ => 0,
    };
    // Every unread notice, on the Notifications tab (2026-11-26): what
    // the header's bell counted until it made way for Help.
    final badges = {if (unread > 0) RoutePaths.staffAlerts: unread};
    final page = Scaffold(
      backgroundColor: AppColors.mobilePageBackground,
      // The bar floats over the page, as drawn: pages pad their scrolling
      // content by the bottom inset this gives them.
      extendBody: true,
      body: Column(
        children: [
          const RequestorHeader(),
          const OfflineBanner(),
          // A container of its own, so the page route's modal barrier
          // does not hide the header and the offline banner above it from
          // screen readers.
          //
          // No NavBadgeClearer, unlike the other two (2026-11-26): the
          // notices are read one by one on Notifications, or all at once
          // with "Mark all as read", so opening the page does not hide
          // which ones are new.
          Expanded(
            child: Semantics(
              container: true,
              child: PageRefreshFrame(child: child),
            ),
          ),
        ],
      ),
      bottomNavigationBar: RequestorBottomBar(
        location: location,
        badges: badges,
      ),
    );

    // Tabs are switched with `go`, which leaves nothing beneath them to go
    // back to. Back from another tab's own page returns Home, rather than
    // closing the app from wherever the person happened to be.
    final isOtherTab =
        location != RoutePaths.staffHome &&
        RequestorTab.values.any((tab) => tab.path == location);
    if (!isOtherTab) return page;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(RoutePaths.staffHome);
      },
      child: page,
    );
  }
}

/// The bottom padding a page inside [RequestorShell] needs so its last item
/// clears the floating bar.
double requestorBottomInset(BuildContext context) => mobileBottomInset(context);
