import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/config/app_config.dart';
import 'package:gsuhub/core/config/env.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            appName: 'GSUhub',
            environment: Environment.development,
            useFirestoreEmulator: true,
          ),
        ),
      ],
      child: const GsuhubAdminApp(),
    ),
  );

  testWidgets('app boots to the dashboard placeholder route', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('/admin/dashboard'), findsOneWidget);
  });
}
