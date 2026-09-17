import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/di/service_providers.dart';
import 'core/routing/app_router.dart';

/// The app's [GoRouter], built once per widget tree.
final appRouterProvider = Provider((ref) => buildAppRouter());

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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: AppColors.primary),
      routerConfig: router,
      builder: (context, child) => _EmulatorBanner(
        enabled: config.useEmulator,
        child: child ?? const SizedBox.shrink(),
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
