import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/shells/admin/widgets/admin_sidebar.dart';

import '../support/fake_admin_backend.dart';

/// The console's numbered badges (2026-11-26, the adviser's consultation):
/// each sidebar item counts the unread notices about its section, as a
/// number, and opening the section reads them. The bell keeps the whole
/// list, and counts them too.
void main() {
  late GoRouter router;
  late FakeNotificationRepository notices;

  AppNotification notice(String id, String entity, NotificationType type) =>
      AppNotification(
        id: id,
        recipientId: fakeAdminUser.uid,
        type: type,
        title: 'Notice $id',
        body: 'Body',
        isRead: false,
        createdAt: DateTime.now(),
        relatedEntityType: entity,
        relatedEntityId: 'x-$id',
      );

  Future<void> pumpConsole(
    WidgetTester tester, {
    String at = RoutePaths.adminDashboard,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    notices = FakeNotificationRepository(const Result.success(4))
      ..unreadNotices = [
        notice('n-1', 'damage_reports', NotificationType.reportSubmitted),
        notice('n-2', 'damage_reports', NotificationType.reportSubmitted),
        notice('n-3', 'work_orders', NotificationType.reviewRequested),
        notice('n-4', 'users', NotificationType.accountRequested),
      ];
    router = buildAppRouter(
      guard: const AppRouteGuard(user: fakeAdminUser),
      initialLocation: at,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      fakeAdminScope(
        notificationRepository: notices,
        unreadCount: const Result.success(4),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder sidebarText(String text) =>
      find.descendant(of: find.byType(AdminSidebar), matching: find.text(text));

  /// The sidebar row of [label], for its badge.
  Finder row(String label) =>
      find.ancestor(of: sidebarText(label), matching: find.byType(Row));

  testWidgets('each item counts its own unread notices, as a number', (
    tester,
  ) async {
    await pumpConsole(tester);

    expect(
      find.descendant(
        of: row('Damage Reports').first,
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('Work Order Management').first,
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('User Accounts').first, matching: find.text('1')),
      findsOneWidget,
    );
    // No Notifications item; the bell holds the whole list, with a number.
    expect(sidebarText('Notifications'), findsNothing);
    expect(find.byTooltip('4 unread notifications'), findsOneWidget);
  });

  testWidgets('opening a section reads its notices, and only those', (
    tester,
  ) async {
    await pumpConsole(tester, at: RoutePaths.adminReports);

    expect(notices.markedManyRead, [
      ['n-1', 'n-2'],
    ]);
  });

  testWidgets('a page under a section is the section: a report clears '
      'Damage Reports', (tester) async {
    await pumpConsole(tester, at: RoutePaths.adminReportDetailFor('rep-1'));
    expect(notices.markedManyRead, [
      ['n-1', 'n-2'],
    ]);
  });

  testWidgets('Work Order Management reads its own', (tester) async {
    await pumpConsole(tester, at: RoutePaths.adminWorkOrders);
    expect(notices.markedManyRead, [
      ['n-3'],
    ]);
  });
}
