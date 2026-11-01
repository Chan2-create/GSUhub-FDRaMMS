import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/routing/app_router.dart';
import 'package:gsuhub/core/routing/route_guards.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/notifications/presentation/admin_notifications_screen.dart';

import '../support/fake_admin_backend.dart';
import '../support/fake_notifications.dart' as notices;
import '../support/fake_requestor_app.dart';

/// The console's notification centre (Objective 7.A, Figma `202:5608`).
void main() {
  AppNotification notice(
    String id, {
    required NotificationType type,
    required String title,
    required String body,
    required String entityType,
    required String entityId,
    bool isRead = false,
    Duration ago = const Duration(hours: 2),
  }) => AppNotification(
    id: id,
    recipientId: fakeAdminUser.uid,
    type: type,
    title: title,
    body: body,
    isRead: isRead,
    readAt: isRead ? DateTime.now() : null,
    relatedEntityType: entityType,
    relatedEntityId: entityId,
    createdAt: DateTime.now().subtract(ago),
  );

  final feed = [
    notice(
      'n-report',
      type: NotificationType.reportSubmitted,
      title: 'New urgent report submitted',
      body: '#R-1 Broken ceiling fan — Science Building.',
      entityType: 'damage_reports',
      entityId: 'r-1',
    ),
    notice(
      'n-work',
      type: NotificationType.workStarted,
      title: 'Work started',
      body: 'Juan Luna started working on #W-1 (Leaking pipe).',
      entityType: 'work_orders',
      entityId: 'w-1',
      isRead: true,
      ago: const Duration(hours: 3),
    ),
    notice(
      'n-stock',
      type: NotificationType.lowStockAlert,
      title: 'Low stock: PVC Pipe (2-inch)',
      body: 'PVC Pipe (2-inch) is down to 12 units; its minimum is 20 units.',
      entityType: 'inventory_items',
      entityId: 'inv-pvc-pipe',
      isRead: true,
      ago: const Duration(hours: 4),
    ),
    notice(
      'n-account',
      type: NotificationType.accountRequested,
      title: 'Account request',
      body:
          'Liza Tan (liza@dorsu.edu.ph) signed up and is waiting for '
          'approval.',
      entityType: 'users',
      entityId: 'faculty-new',
      ago: const Duration(hours: 5),
    ),
  ];

  late GoRouter router;

  Future<notices.FakeNotificationRepository> pump(
    WidgetTester tester, {
    List<AppNotification>? items,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = notices.FakeNotificationRepository(items ?? feed);
    addTearDown(repository.dispose);
    router = buildAppRouter(
      guard: const AppRouteGuard(user: fakeAdminUser),
      initialLocation: RoutePaths.adminNotifications,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      fakeAdminScope(
        notificationRepository: repository,
        reports: Result.success([fakeMyReport('r-1')]),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder inPage(Finder finder) => find.descendant(
    of: find.byType(AdminNotificationsScreen),
    matching: finder,
  );

  testWidgets('lists the administrator\'s notices, newest first', (
    tester,
  ) async {
    await pump(tester);

    expect(inPage(find.text('Notifications')), findsOneWidget);
    expect(
      inPage(find.text('System-wide notification logs and alerts')),
      findsOneWidget,
    );
    final titles = [
      'New urgent report submitted',
      'Work started',
      'Low stock: PVC Pipe (2-inch)',
      'Account request',
    ];
    for (var i = 1; i < titles.length; i++) {
      expect(
        tester.getTopLeft(inPage(find.text(titles[i - 1]))).dy,
        lessThan(tester.getTopLeft(inPage(find.text(titles[i]))).dy),
      );
    }
    expect(inPage(find.text('2 hours ago')), findsOneWidget);
  });

  testWidgets('an unread notice carries its tags; a read one none', (
    tester,
  ) async {
    await pump(tester);

    // The report's priority: the requestor chose High.
    expect(inPage(find.text('HIGH PRIORITY')), findsOneWidget);
    // Two unread notices, two UNREAD tags.
    expect(inPage(find.text('UNREAD')), findsNWidgets(2));
  });

  testWidgets('the pills filter: Unread, Reports, System', (tester) async {
    await pump(tester);

    await tester.tap(inPage(find.text('Unread')));
    await tester.pumpAndSettle();
    expect(inPage(find.text('New urgent report submitted')), findsOneWidget);
    expect(inPage(find.text('Account request')), findsOneWidget);
    expect(inPage(find.text('Work started')), findsNothing);

    await tester.tap(inPage(find.text('Reports')));
    await tester.pumpAndSettle();
    expect(inPage(find.text('New urgent report submitted')), findsOneWidget);
    expect(inPage(find.text('Work started')), findsOneWidget);
    expect(inPage(find.text('Low stock: PVC Pipe (2-inch)')), findsNothing);

    await tester.tap(inPage(find.text('System')));
    await tester.pumpAndSettle();
    expect(inPage(find.text('Low stock: PVC Pipe (2-inch)')), findsOneWidget);
    expect(inPage(find.text('Account request')), findsOneWidget);
    expect(inPage(find.text('Work started')), findsNothing);
  });

  testWidgets('Mark All as Read clears them, live', (tester) async {
    final repository = await pump(tester);

    await tester.tap(inPage(find.text('Mark All as Read')));
    await tester.pumpAndSettle();

    expect(repository.markAllCalls, 1);
    expect(inPage(find.text('UNREAD')), findsNothing);
  });

  testWidgets('a notice opens what it is about, and is marked read', (
    tester,
  ) async {
    final repository = await pump(tester);

    await tester.tap(inPage(find.text('Account request')));
    await tester.pumpAndSettle();

    expect(repository.markedRead, ['n-account']);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      RoutePaths.adminUsers,
    );
  });

  testWidgets('says so when there is nothing to show', (tester) async {
    await pump(tester, items: const []);

    expect(
      inPage(find.textContaining('No notifications yet.')),
      findsOneWidget,
    );
    expect(inPage(find.text('View Older Notifications')), findsNothing);
  });

  testWidgets('older notices load on request', (tester) async {
    final many = [
      for (var i = 0; i < AdminNotificationsScreen.pageSize; i++)
        notice(
          'n-$i',
          type: NotificationType.reportSubmitted,
          title: 'New report submitted $i',
          body: '#R-$i A report.',
          entityType: 'damage_reports',
          entityId: 'r-$i',
          isRead: true,
          ago: Duration(minutes: i + 1),
        ),
    ];
    await pump(tester, items: many);

    final older = inPage(find.text('View Older Notifications'));
    expect(older, findsOneWidget);
    await tester.ensureVisible(older);
    await tester.pumpAndSettle();
    await tester.tap(older);
    await tester.pumpAndSettle();
    // All fifty were all there was: no more to ask for.
    expect(inPage(find.text('View Older Notifications')), findsNothing);
  });
}
