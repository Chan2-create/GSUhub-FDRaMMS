import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_colors.dart';
import 'core/di/service_providers.dart';
import 'core/routing/app_router.dart';
import 'core/routing/route_guards.dart';

/// The app's [GoRouter].
///
/// Rebuilt whenever the auth state changes so the route guard always
/// evaluates against a current session. `GoRouter.redirect` is
/// synchronous and cannot await a lookup, so the resolved user is handed
/// to the guard rather than fetched by it.
///
/// `keepAlive` prevents the router — and with it the entire navigation
/// stack — from being disposed when no widget happens to be listening for
/// a frame.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  final router = buildAppRouter(
    guard: AppRouteGuard(
      user: auth.value,
      // `isLoading` covers the gap on a browser refresh while Firebase
      // restores the session. Redirecting to login during that window
      // would sign the user out of their own page on every reload.
      isResolving: auth.isLoading,
    ),
  );

  ref.onDispose(router.dispose);
  return router;
}, dependencies: const []);

/// Root widget for GSUhub.
class GsuhubApp extends ConsumerWidget {
  const GsuhubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      routerConfig: router,
      builder: (context, child) => _EmulatorBanner(
        enabled: config.useEmulator,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  static ThemeData _theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: AppColors.primary,
      scaffoldBackgroundColor: AppColors.pageBackground,
      fontFamily: 'Public Sans',
    );

    return base.copyWith(
      // Disabled controls appear throughout the admin UI in 2.A — every
      // nav item and top-bar action that belongs to a later objective —
      // so their treatment is set once here rather than per widget.
      tooltipTheme: const TooltipThemeData(waitDuration: Duration.zero),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        space: 1,
        thickness: 1,
      ),
    );
  }
}

/// Marks the UI unmistakably when the app is talking to the local
/// Emulator Suite.
///
/// Without this, emulator and live builds are visually identical, and the
/// two failure modes that follow are both bad: trusting seeded test data
/// as if it were real, or writing test records into the live project
/// during a demo.
class _EmulatorBanner extends StatelessWidget {
  const _EmulatorBanner({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Banner(
      message: 'EMULATOR',
      location: BannerLocation.topStart,
      color: Colors.deepOrange,
      child: child,
    );
  }
}
