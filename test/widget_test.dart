import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/config/app_config.dart';
import 'package:gsuhub/core/config/env.dart';
import 'package:gsuhub/core/di/service_providers.dart';

import 'support/test_app_config.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(testAppConfig())],
      child: const GsuhubApp(),
    ),
  );

  testWidgets('app boots to the admin dashboard placeholder route', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('/admin/dashboard'), findsOneWidget);
  });

  testWidgets('emulator banner is hidden when not in emulator mode', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.byType(Banner), findsNothing);
  });

  testWidgets('emulator banner is shown in emulator mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig(useEmulator: true)),
        ],
        child: const GsuhubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The banner is what stops someone mistaking seeded emulator data for
    // the live project during a demo. Its message is painted on a canvas
    // rather than rendered as a Text widget, so assert on the widget.
    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'EMULATOR');
  });

  test('AppConfig.fromEnvironment defaults to development, no emulator', () {
    final config = AppConfig.fromEnvironment();

    expect(config.environment, Environment.development);
    expect(config.useEmulator, isFalse);
    expect(config.appName, 'GSUhub');
  });
}
