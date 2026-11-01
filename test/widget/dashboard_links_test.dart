import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';

import '../support/fake_admin_backend.dart';
import '../support/fake_requestor_app.dart';

/// The dashboard's Recent Reports card leads to the reports (Objective 7.A:
/// its View All and each row's view button were placeholders until the
/// screens they open were built).
void main() {
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 2000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    router = buildAppRouter(
      guard: const AppRouteGuard(user: fakeAdminUser),
      initialLocation: RoutePaths.adminDashboard,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      fakeAdminScope(
        reports: Result.success([fakeMyReport('r-1')]),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  String where() => router.routerDelegate.currentConfiguration.uri.path;

  testWidgets('View All opens Damage Reports', (tester) async {
    await pump(tester);

    final viewAll = find.widgetWithText(TextButton, 'View All');
    await tester.ensureVisible(viewAll);
    await tester.pumpAndSettle();
    await tester.tap(viewAll);
    await tester.pumpAndSettle();

    expect(where(), RoutePaths.adminReports);
  });

  testWidgets('a row\'s view button opens that report', (tester) async {
    await pump(tester);

    final open = find.byTooltip('Open the report');
    await tester.ensureVisible(open.first);
    await tester.pumpAndSettle();
    await tester.tap(open.first);
    await tester.pumpAndSettle();

    expect(where(), RoutePaths.adminReportDetailFor('r-1'));
  });
}
