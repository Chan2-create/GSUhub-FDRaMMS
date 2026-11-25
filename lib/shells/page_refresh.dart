import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:go_router/go_router.dart';

import '../core/constants/app_colors.dart';
import '../core/di/service_providers.dart';
import '../core/navigation/unsaved_work.dart';
import '../core/utils/result.dart';
import '../features/damage_reports/presentation/report_review_controller.dart';
import '../features/dashboard/presentation/dashboard_providers.dart';
import '../features/user_management/presentation/profile_providers.dart';

/// Where the app really is: the router's current path, a page pushed over
/// a tab included (2026-11-26). A shell's own [GoRouterState] names the
/// route it was reached by, so with a report's details pushed over Home
/// it still says Home: the bar then lit Home, and Home pressed there
/// refreshed Home's hidden page instead of going back to it. [fallback]
/// is used when there is no router above [context] (a widget test that
/// builds a shell on its own).
String currentRoutePath(BuildContext context, {required String fallback}) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return fallback;
  return router.state.uri.path;
}

/// A navigation button pressed (2026-11-25): the console's sidebar, the
/// phone apps' bottom bar.
///
/// * Another module: goes there, as before. Its page reads its data as
///   it opens.
/// * The module already open, from a page inside it (a report's details):
///   back to the module's own page, and its data read again.
/// * The module's own page, already open: its data read again, in place.
///   Nothing is navigated, so filters, searches, the open tab and any
///   form on the page keep what they hold.
///
/// Whenever the page would be left, unsaved work on it is asked about
/// first ([confirmLeavingUnsavedWork]); staying leaves everything as it
/// was. Refreshing in place discards nothing, so it does not ask.
///
/// [location] is the path shown now, without its query; [target] the
/// button's path; [inModule] whether [location] belongs to the button's
/// module. The router's own current path is what decides whether the page
/// is left, whatever [location] says: from a page pushed over the
/// button's page (a recent report opened from Home), the button goes back
/// to its page, popping what was pushed (2026-11-26).
Future<void> navigateFromNav(
  BuildContext context, {
  required String location,
  required String target,
  required bool inModule,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final router = GoRouter.of(context);
  final here = router.state.uri.path;
  if (here != target) {
    if (!await confirmLeavingUnsavedWork(context)) return;
    router.go(target);
    if (!inModule) return;
  }
  unawaited(container.read(pageRefreshProvider.notifier).refresh());
}

/// Where a refresh is: running or not, and how many have failed, so the
/// shell can tell the person each time one does.
@immutable
class PageRefreshState {
  const PageRefreshState({this.busy = false, this.failures = 0});

  final bool busy;
  final int failures;
}

/// Reads the page on screen again (2026-11-25): every live query showing
/// ([LiveSync.refreshWatched]) and the few views read once
/// ([_readOnce]). One at a time: a tap while one runs joins it rather
/// than sending the same requests again.
class PageRefreshController extends Notifier<PageRefreshState> {
  /// The loading bar shows at least this long, so a quick refresh is
  /// still seen to have happened.
  static const Duration minimumShown = Duration(milliseconds: 400);

  /// Views read once rather than kept live, read again by a refresh. Form
  /// helpers (the building and department lists) are not here: they are
  /// read each time a form opens, and reading them under a half-filled
  /// form would gain nothing.
  static final List<ProviderOrFamily> _readOnce = [
    recentActivityProvider,
    reportHistoryProvider,
    signedInProfileProvider,
  ];

  Future<bool>? _running;

  @override
  PageRefreshState build() => const PageRefreshState();

  /// Reads the page again; true when everything answered. While one is
  /// running, returns that one.
  Future<bool> refresh() =>
      _running ??= _refresh().whenComplete(() => _running = null);

  Future<bool> _refresh() async {
    state = PageRefreshState(busy: true, failures: state.failures);
    var succeeded = true;
    try {
      final shown = [
        if (ref.exists(recentActivityProvider)) recentActivityProvider,
        if (ref.exists(signedInProfileProvider)) signedInProfileProvider,
      ];
      _readOnce.forEach(ref.invalidate);
      final results = await Future.wait([
        ref.read(liveSyncProvider).refreshWatched(),
        for (final provider in shown) _answered(provider),
        Future<bool>.delayed(minimumShown, () => true),
      ]);
      succeeded = results.every((ok) => ok);
    } on Object {
      succeeded = false;
    }
    state = PageRefreshState(failures: state.failures + (succeeded ? 0 : 1));
    return succeeded;
  }

  Future<bool> _answered(FutureProvider<Result<Object?>> provider) async {
    try {
      return switch (await ref.read(provider.future)) {
        Success() => true,
        Error() => false,
      };
    } on Object {
      return false;
    }
  }
}

final pageRefreshProvider =
    NotifierProvider<PageRefreshController, PageRefreshState>(
      PageRefreshController.new,
    );

/// A thin bar along the top of the page while it is being read again, and
/// a message when that failed. Goes over the page's own top edge; takes
/// no room of its own, so nothing on the page moves.
class PageRefreshFrame extends ConsumerWidget {
  const PageRefreshFrame({required this.child, super.key});

  final Widget child;

  /// The loading bar, for tests.
  static const Key barKey = ValueKey('page-refresh-bar');

  /// What a failed refresh says.
  static const String failedMessage =
      'Could not refresh this page. It shows the last information '
      'received, and updates on its own once the connection is back.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pageRefreshProvider.select((state) => state.failures), (
      before,
      now,
    ) {
      if (now <= (before ?? 0)) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(failedMessage)));
    });
    final busy = ref.watch(pageRefreshProvider.select((state) => state.busy));
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (busy)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Semantics(
              label: 'Refreshing',
              liveRegion: true,
              child: const LinearProgressIndicator(
                key: barKey,
                minHeight: 3,
                // Indigo: gold would run into the console's gold rule above.
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}
