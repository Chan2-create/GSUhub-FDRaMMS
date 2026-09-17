import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/constants/app_colors.dart';
import 'core/routing/app_router.dart';

/// Provides the app-wide [AppConfig]. A concrete instance is supplied by
/// [ProviderScope.overrides] in `main.dart` so tests can inject a different
/// configuration without touching this provider's definition.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

/// The Admin web app's [GoRouter], built once per widget tree.
final appRouterProvider = Provider((ref) => buildAppRouter());

/// Root widget for the Admin web application.
class GsuhubAdminApp extends ConsumerWidget {
  const GsuhubAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: AppColors.primary),
      routerConfig: router,
    );
  }
}
