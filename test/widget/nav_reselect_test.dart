import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/shells/admin/widgets/admin_sidebar.dart';
import 'package:gsuhub/shells/mobile/mobile_bottom_bar.dart';
import 'package:gsuhub/shells/page_refresh.dart';

import '../support/fake_admin_backend.dart';
import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart';

/// A navigation button pressed again (2026-11-25): on its own page it
/// reads the page again; from a page inside its module it returns to the
/// module's page; leaving a page with unsaved work asks first.
void main() {
  final bar = find.byKey(PageRefreshFrame.barKey);

  group('the console sidebar', () {
    late GoRouter router;

    Future<void> pumpConsole(
      WidgetTester tester, {
      String at = RoutePaths.adminReports,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      router = buildAppRouter(
        guard: const AppRouteGuard(user: fakeAdminUser),
        initialLocation: at,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        fakeAdminScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
    }

    String currentPath() => router.routerDelegate.currentConfiguration.uri.path;

    Finder item(String label) => find.descendant(
      of: find.byType(AdminSidebar),
      matching: find.text(label),
    );

    testWidgets('Damage Reports pressed on Damage Reports reads the page '
        'again, with a loading bar, and stays', (tester) async {
      await pumpConsole(tester);
      expect(bar, findsNothing);

      await tester.tap(item('Damage Reports'));
      await tester.pump();
      expect(bar, findsOneWidget);
      expect(currentPath(), RoutePaths.adminReports);

      await tester.pump(PageRefreshController.minimumShown);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      expect(find.text(PageRefreshFrame.failedMessage), findsNothing);
    });

    testWidgets("from a report's details, Damage Reports returns to the "
        'list and reads it again', (tester) async {
      await pumpConsole(tester, at: RoutePaths.adminReportDetailFor('r-1'));

      await tester.tap(item('Damage Reports'));
      await tester.pump();
      expect(currentPath(), RoutePaths.adminReports);
      expect(bar, findsOneWidget);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets('from a work order, Work Order Management returns to the '
        'list', (tester) async {
      await pumpConsole(tester, at: RoutePaths.adminWorkOrderDetailFor('w-1'));

      await tester.tap(item('Work Order Management'));
      await tester.pumpAndSettle();
      expect(currentPath(), RoutePaths.adminWorkOrders);
    });

    testWidgets('another module opens as before, without a refresh', (
      tester,
    ) async {
      await pumpConsole(tester);

      await tester.tap(item('Analytics'));
      await tester.pump();
      expect(bar, findsNothing);
      await tester.pumpAndSettle();
      expect(currentPath(), RoutePaths.adminAnalytics);
    });

    testWidgets('every module can be pressed again on its own page', (
      tester,
    ) async {
      for (final (label, path) in const [
        ('Dashboard', RoutePaths.adminDashboard),
        ('Inventory Management', RoutePaths.adminInventory),
        ('Personnel', RoutePaths.adminPersonnel),
        ('Task Assignment', RoutePaths.adminTaskAssignment),
        ('Work Order Management', RoutePaths.adminWorkOrders),
        ('Analytics', RoutePaths.adminAnalytics),
        ('User Accounts', RoutePaths.adminUsers),
        ('Facilities & Equipment', RoutePaths.adminFacilities),
        // Notifications left the sidebar on 2026-11-26 (the header's bell).
        ('Settings', RoutePaths.adminSettings),
      ]) {
        await pumpConsole(tester, at: path);
        await tester.tap(item(label));
        await tester.pump();
        expect(bar, findsOneWidget, reason: label);
        expect(currentPath(), path, reason: label);
        await tester.pumpAndSettle();
        expect(bar, findsNothing, reason: label);
      }
    });

    testWidgets('pressed over and over, it is one refresh', (tester) async {
      await pumpConsole(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdminSidebar)),
      );
      var refreshes = 0;
      container.listen(pageRefreshProvider.select((state) => state.busy), (
        _,
        busy,
      ) {
        if (busy) refreshes++;
      });

      for (var i = 0; i < 4; i++) {
        await tester.tap(item('Damage Reports'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });

    testWidgets('a refresh that fails says so, and keeps the page', (
      tester,
    ) async {
      await pumpConsole(tester);
      // A view on the page whose next read fails.
      final sync = ProviderScope.containerOf(
        tester.element(find.byType(AdminSidebar)),
      ).read(liveSyncProvider);
      var reads = 0;
      final view = sync
          .watchRows(
            tables: {'damage_reports'},
            fetch: () async {
              if (reads++ > 0) throw Exception('connection lost');
              return const [];
            },
          )
          .listen((_) {}, onError: (_) {});
      await tester.pumpAndSettle();

      await tester.tap(item('Damage Reports'));
      await tester.pump(PageRefreshController.minimumShown);
      await tester.pump();
      expect(find.text(PageRefreshFrame.failedMessage), findsOneWidget);
      expect(currentPath(), RoutePaths.adminReports);
      // Not awaited: under the test's clock a cancel's own future does
      // not complete (as in live_sync_test.dart).
      unawaited(view.cancel());
      await tester.pumpAndSettle();
    });

    group('unsaved work', () {
      Future<void> editKeywords(WidgetTester tester) async {
        final open = find.byTooltip(
          'Add a keyword to ${DamageCategory.plumbing.label}',
        );
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Add a keyword or phrase'),
          'burst pipe',
        );
        final add = find.byTooltip('Add to ${DamageCategory.plumbing.label}');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
      }

      testWidgets('leaving Settings with an edit asks; Stay keeps it', (
        tester,
      ) async {
        await pumpConsole(tester, at: RoutePaths.adminSettings);
        await editKeywords(tester);

        await tester.tap(item('Dashboard'));
        await tester.pumpAndSettle();
        expect(find.text('Leave without saving?'), findsOneWidget);

        await tester.tap(find.text('Stay on this page'));
        await tester.pumpAndSettle();
        expect(currentPath(), RoutePaths.adminSettings);
        expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);
      });

      testWidgets('Leave and discard goes', (tester) async {
        await pumpConsole(tester, at: RoutePaths.adminSettings);
        await editKeywords(tester);

        await tester.tap(item('Dashboard'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave and discard'));
        await tester.pumpAndSettle();
        expect(currentPath(), RoutePaths.adminDashboard);
      });

      testWidgets('Settings pressed again refreshes without asking, and '
          'keeps the edit', (tester) async {
        await pumpConsole(tester, at: RoutePaths.adminSettings);
        await editKeywords(tester);

        await tester.tap(item('Settings'));
        await tester.pump();
        expect(find.text('Leave without saving?'), findsNothing);
        expect(bar, findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(InputChip, 'burst pipe'), findsOneWidget);
      });

      testWidgets('with nothing changed, nothing is asked', (tester) async {
        await pumpConsole(tester, at: RoutePaths.adminSettings);

        await tester.tap(item('Dashboard'));
        await tester.pumpAndSettle();
        expect(find.text('Leave without saving?'), findsNothing);
        expect(currentPath(), RoutePaths.adminDashboard);
      });
    });
  });

  group('the faculty and staff app', () {
    Finder tab(String label) => find.descendant(
      of: find.byType(MobileBottomBar),
      matching: find.text(label),
    );

    testWidgets('Reports pressed on Reports reads it again', (tester) async {
      await RequestorHarness(reports: [fakeMyReport('rep-1')])
          .pump(tester, start: RoutePaths.staffMyReports);

      await tester.tap(tab('Reports'));
      await tester.pump();
      expect(bar, findsOneWidget);
      expect(currentPath(tester), RoutePaths.staffMyReports);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets("from a report's details, Reports returns to the list and "
        'reads it again', (tester) async {
      await RequestorHarness(reports: [fakeMyReport('rep-1')])
          .pump(tester, start: RoutePaths.staffReportDetailFor('rep-1'));

      await tester.tap(tab('Reports'));
      await tester.pump();
      expect(currentPath(tester), RoutePaths.staffMyReports);
      expect(bar, findsOneWidget);
      await tester.pumpAndSettle();
    });

    for (final (label, path) in const [
      ('Home', RoutePaths.staffHome),
      ('Reports', RoutePaths.staffMyReports),
      // No Alerts tab since 2026-11-26: the header's bell opens them.
      ('Profile', RoutePaths.staffProfile),
    ]) {
      testWidgets(' can be pressed again on its own page', (tester) async {
        await RequestorHarness().pump(tester, start: path);
        await tester.tap(tab(label));
        await tester.pump();
        expect(bar, findsOneWidget);
        expect(currentPath(tester), path);
        await tester.pumpAndSettle();
        expect(bar, findsNothing);
      });
    }

    testWidgets('a rating begun asks before another tab opens', (tester) async {
      await RequestorHarness(
        reports: [
          fakeMyReport(
            'rep-1',
            status: ReportStatus.completed,
            reviewedBy: 'admin-1',
            workOrderId: 'wo-1',
          ),
        ],
      ).pump(tester, start: RoutePaths.staffRateReportFor('rep-1'));
      final comments = find.byType(TextField).first;
      await tester.ensureVisible(comments);
      await tester.pumpAndSettle();
      await tester.enterText(comments, 'Quick and tidy.');
      await tester.pump();

      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tester.tap(find.text('Stay on this page'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffRateReportFor('rep-1'));
      expect(find.text('Quick and tidy.'), findsOneWidget);
    });

    testWidgets('Back on a report begun asks first; Leave goes', (
      tester,
    ) async {
      await RequestorHarness().pump(tester);
      await tester.tap(find.byTooltip('Report damage'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffSubmitReport);

      await tester.enterText(
        find.widgetWithText(TextField, 'e.g., Broken Ceiling Fan'),
        'Leaking pipe',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);

      await tester.tap(find.text('Stay on this page'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffSubmitReport);
      expect(find.text('Leaking pipe'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave and discard'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.staffHome);
    });

    testWidgets('Back on an empty report form goes without asking', (
      tester,
    ) async {
      await RequestorHarness().pump(tester);
      await tester.tap(find.byTooltip('Report damage'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsNothing);
      expect(currentPath(tester), RoutePaths.staffHome);
    });
  });

  group('the personnel app', () {
    Finder tab(String label) => find.descendant(
      of: find.byType(MobileBottomBar),
      matching: find.text(label),
    );

    testWidgets('Tasks pressed on Tasks reads it again; from a work order '
        'it returns to Tasks', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester, start: RoutePaths.personnelTasks);

      await tester.tap(tab('Tasks'));
      await tester.pump();
      expect(bar, findsOneWidget);
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelTasks);
    });

    testWidgets('completion notes begun ask before another tab opens', (
      tester,
    ) async {
      final app = PersonnelHarness();
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.pump(tester, start: RoutePaths.personnelWorkOrderFor('wo-1'));

      // The notes box opens with Mark Complete.
      final markComplete = find.text('Mark Complete');
      await reveal(tester, markComplete);
      await tester.tap(markComplete);
      await tester.pumpAndSettle();
      final notes = find.widgetWithText(
        TextField,
        'Enter completion notes here...',
      );
      await reveal(tester, notes);
      await tester.enterText(notes, 'Replaced the ballast.');
      await tester.pump();

      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tester.tap(find.text('Leave and discard'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelDashboard);
    });
  });
}

/// Scrolls [finder] into the middle of a lazily built page, as the
/// personnel app tests do: only so far, it could sit under the bottom bar.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}
