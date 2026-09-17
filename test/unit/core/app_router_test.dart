import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

void main() {
  group('buildAppRouter', () {
    testWidgets('starts at the admin dashboard placeholder', (tester) async {
      final router = buildAppRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text(RoutePaths.adminDashboard), findsOneWidget);
    });

    testWidgets('navigates within the admin shell', (tester) async {
      final router = buildAppRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go(RoutePaths.adminReports);
      await tester.pumpAndSettle();

      expect(find.text(RoutePaths.adminReports), findsOneWidget);
    });

    testWidgets('root path redirects to the admin dashboard', (tester) async {
      final router = buildAppRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go(RoutePaths.root);
      await tester.pumpAndSettle();

      expect(find.text(RoutePaths.adminDashboard), findsOneWidget);
    });

    testWidgets('navigates into the requestor (staff) shell', (tester) async {
      final router = buildAppRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go(RoutePaths.staffSubmitReport);
      await tester.pumpAndSettle();

      expect(find.text(RoutePaths.staffSubmitReport), findsOneWidget);
    });

    testWidgets('navigates into the personnel shell', (tester) async {
      final router = buildAppRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go(RoutePaths.personnelDashboard);
      await tester.pumpAndSettle();

      expect(find.text(RoutePaths.personnelDashboard), findsOneWidget);
    });

    testWidgets('reaches the login placeholder for each shell', (tester) async {
      final router = buildAppRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      for (final loginPath in [
        RoutePaths.adminLogin,
        RoutePaths.staffLogin,
        RoutePaths.personnelLogin,
      ]) {
        router.go(loginPath);
        await tester.pumpAndSettle();
        expect(find.text(loginPath), findsOneWidget);
      }
    });
  });
}
