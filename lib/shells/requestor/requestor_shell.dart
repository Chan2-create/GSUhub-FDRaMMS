import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/routing/route_paths.dart';
import 'requestor_bottom_bar.dart';
import 'requestor_header.dart';

/// The faculty and staff app's frame around its four tabs (Objective 3.A,
/// Figma `170:2050`): the GSUhub header above, the floating bottom bar
/// below, the tab's page between.
///
/// The report form (3.C) opens over this rather than inside it — its frame
/// has no bottom bar — and the sign-in pages sit outside it altogether.
class RequestorShell extends StatelessWidget {
  const RequestorShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// The current location, for the bar's highlight and the back button.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: AppColors.mobilePageBackground,
      // The bar floats over the page, as drawn: pages pad their scrolling
      // content by the bottom inset this gives them.
      extendBody: true,
      body: Column(
        children: [
          const RequestorHeader(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: RequestorBottomBar(location: location),
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
double requestorBottomInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 16;
