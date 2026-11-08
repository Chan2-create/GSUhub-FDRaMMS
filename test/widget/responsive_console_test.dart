import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/notification_type.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';
import '../support/firestore_backend/core/data/firestore_records.dart';

/// Every console page at a phone's, a tablet's, a laptop's and the
/// design's width (360, 768, 1024, 1440): nothing overflows, nothing
/// throws, and the page itself never scrolls sideways.
void main() {
  Future<PersonnelHarness> console() async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    final data = app.data;
    await data.addPersonnel(
      fakeAdministrator.uid,
      role: UserRole.admin,
      fullName: 'Ramon Dela Cruz',
    );
    await data.addPersonnel(fakeTechnician.uid, activeTaskCount: 2);
    await data.addPersonnel(
      'personnel-2',
      fullName: 'Juan Luna Dela Paz Santiago',
      activeTaskCount: 1,
    );
    await data.addPersonnel(
      'faculty-1',
      role: UserRole.requestor,
      fullName: 'Maria Santos',
    );
    await data.addPersonnel(
      'pending-1',
      role: UserRole.requestor,
      accountStatus: AccountStatus.pending,
      fullName: 'Liza Tan',
    );

    final statuses = [
      (ReportStatus.submitted, null),
      (ReportStatus.underReview, null),
      (ReportStatus.approved, null),
      (ReportStatus.assigned, 'wo-1'),
      (ReportStatus.inProgress, 'wo-2'),
      (ReportStatus.forReview, 'wo-3'),
      (ReportStatus.completed, 'wo-4'),
      (ReportStatus.closed, 'wo-5'),
      (ReportStatus.rejected, null),
    ];
    for (final (i, (status, workOrder)) in statuses.indexed) {
      await data.addReport(
        'rep-${i + 1}',
        status: status,
        workOrderId: workOrder,
        submittedAt: DateTime.now().subtract(Duration(hours: i * 7)),
      );
    }
    for (final (id, report, status) in [
      ('wo-1', 'rep-4', WorkOrderStatus.pending),
      ('wo-2', 'rep-5', WorkOrderStatus.inProgress),
      ('wo-3', 'rep-6', WorkOrderStatus.forReview),
      ('wo-4', 'rep-7', WorkOrderStatus.completed),
      ('wo-5', 'rep-8', WorkOrderStatus.completed),
    ]) {
      await data.addWorkOrder(id, reportIds: [report], status: status);
    }
    await data.addTask('task-1', workOrderId: 'wo-2', dueDate: DateTime.now());

    await data.addInventoryItem('inv-led', quantity: 40, unitCost: 100);
    await data.addInventoryItem(
      'inv-wire',
      name: '12/2 Romex Electrical Wire (250ft roll)',
      quantity: 1,
      unit: 'rolls',
      minimum: 3,
      unitCost: 3850,
    );
    await data.addTool('tool-1');
    await data.addTool('tool-2', status: ToolStatus.borrowed);

    final room = await data.facilities.createFacility(
      draft: const FacilityDraft(
        buildingName: 'College of Engineering and Technology Building',
        roomIdentifier: 'Laboratory 203',
        qrCode: 'FAC-ENG-203',
      ),
      actor: FirestoreHarness.admin,
    );
    await data.facilities.createAsset(
      draft: AssetDraft(
        name: 'Split-type Air Conditioner',
        facilityId: room.fold((id) => id, (_) => ''),
        condition: ItemCondition.fair,
        serialNumber: 'AC-2024-00917',
      ),
      actor: FirestoreHarness.admin,
    );

    for (final (i, type) in [
      NotificationType.lowStockAlert,
      NotificationType.statusUpdate,
    ].indexed) {
      await data.firestore
          .collection(FirestorePaths.notifications)
          .doc('n-$i')
          .set(
            AppNotification(
              id: 'n-$i',
              recipientId: fakeAdministrator.uid,
              type: type,
              title: 'Low stock: 12/2 Romex Electrical Wire (250ft roll)',
              body:
                  'It is down to 1 roll; its minimum is 3 rolls. Record a '
                  'delivery when stock arrives.',
              isRead: false,
              createdAt: DateTime.now().subtract(Duration(minutes: i * 90)),
              relatedEntityType: FirestorePaths.inventoryItems,
              relatedEntityId: 'inv-wire',
            ).toFields().forFirestore,
          );
    }
    return app;
  }

  const pages = {
    'Dashboard': RoutePaths.adminDashboard,
    'Reports': RoutePaths.adminReports,
    'Report detail': '/admin/reports/rep-2',
    'Work Orders': RoutePaths.adminWorkOrders,
    'Work order detail': '/admin/work-orders/wo-2',
    'Task Assignment': RoutePaths.adminTaskAssignment,
    'Inventory': RoutePaths.adminInventory,
    'Facilities': RoutePaths.adminFacilities,
    'Personnel': RoutePaths.adminPersonnel,
    'Analytics': RoutePaths.adminAnalytics,
    'User Accounts': RoutePaths.adminUsers,
    'Notifications': RoutePaths.adminNotifications,
    'Settings': RoutePaths.adminSettings,
  };
  const widths = [360.0, 768.0, 1024.0, 1440.0];

  for (final MapEntry(key: name, value: path) in pages.entries) {
    group(name, () {
      for (final width in widths) {
        testWidgets('fits at ${width.toInt()}px', (tester) async {
          final app = await console();
          // An overflow or any other error fails the test by itself, with
          // the widget and line that caused it.
          await app.pump(tester, start: path, size: Size(width, 900));

          // The page never scrolls sideways: whatever is wider than the
          // window scrolls inside its own card.
          final shell = tester.getSize(find.byType(Scaffold).first);
          expect(shell.width, width);
        });
      }
    });
  }
}
