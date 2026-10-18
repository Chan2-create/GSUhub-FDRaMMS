import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/firebase/firebase_call_guard.dart';
import 'package:gsuhub/features/inventory/presentation/inventory_screen.dart';
import 'package:gsuhub/features/reporting/presentation/submission/qr_scanner_screen.dart';
import 'package:gsuhub/features/reporting/presentation/submission/widgets/geo_tag_map.dart';

import 'fake_admin_backend.dart' show FakeFileDownloadService;
import 'fake_config_repository.dart';
import 'fake_firestore_repositories.dart';
import 'fake_notifications.dart';
import 'fake_report_form_backend.dart';
import 'fake_requestor_app.dart';
import 'firestore_backend/core/services/firebase/firestore_service_impl.dart';
import 'firestore_backend/features/audit/data/repositories/audit_log_repository_firestore.dart';
import 'firestore_backend/features/notifications/data/repositories/notification_repository_firestore.dart';
import 'test_app_config.dart';

/// Stands up the personnel app (Objective 5) without Firebase: the real
/// router, shell, screens and repositories, over an in-memory Firestore —
/// the screens' behaviour is mostly what those repositories' transactions
/// do, so hand-written fakes would be testing themselves.

const fakeTechnician = AuthUser(
  uid: 'personnel-1',
  email: 'personnel-1@dorsu.edu.ph',
  role: UserRole.maintenancePersonnel,
);

const fakeAdministrator = AuthUser(
  uid: 'admin-1',
  email: 'admin@dorsu.edu.ph',
  role: UserRole.admin,
);

/// The fakes one test works with.
class PersonnelHarness {
  PersonnelHarness({AuthUser signedIn = fakeTechnician})
    : auth = ScriptedAuthService(signedIn: signedIn);

  /// The in-memory Firestore and the real repositories over it, for
  /// seeding and for reading back what the app wrote.
  final data = FirestoreHarness();
  final ScriptedAuthService auth;
  final push = FakeNotificationService();
  final picker = FakePhotoPicker();
  final storage = FakeStorageService();
  final connectivity = FakeConnectivityService();
  final config = FakeConfigRepository();

  /// What the console offered to save: CSV exports and QR label sheets.
  final downloads = FakeFileDownloadService();

  /// What the next scan reads; null backs out of the scanner.
  String? nextScan;
  int scans = 0;

  /// One assigned job, as an administrator leaves it: the technician's
  /// profile, a report and its work order (pending), a task due today, a
  /// material in stock and a tool on the shelf.
  Future<void> seedJob({
    WorkOrderStatus status = WorkOrderStatus.pending,
  }) async {
    await data.addPersonnel(fakeTechnician.uid);
    await data.addReport(
      'rep-1',
      status: status == WorkOrderStatus.pending
          ? ReportStatus.assigned
          : ReportStatus.inProgress,
      workOrderId: 'wo-1',
    );
    await data.addWorkOrder('wo-1', reportIds: ['rep-1'], status: status);
    await data.addTask('task-1', workOrderId: 'wo-1', dueDate: DateTime.now());
    await data.addInventoryItem('inv-led');
    await data.addTool('tool-1');
  }

  /// A stored document's fields, or empty when there is none.
  Future<Map<String, dynamic>> read(String collection, String id) =>
      data.doc(collection, id);

  Future<String?> workOrderStatus([String id = 'wo-1']) async =>
      (await read(FirestorePaths.workOrders, id))['status'] as String?;

  /// Boots the app at [start], phone-sized unless [size] says otherwise.
  Future<void> pump(
    WidgetTester tester, {
    String start = RoutePaths.personnelDashboard,
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(auth.dispose);
    addTearDown(connectivity.dispose);
    addTearDown(push.dispose);

    final guard = FirebaseCallGuard(testAppConfig());
    final db = FirestoreServiceImpl(firestore: data.firestore, guard: guard);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig()),
          startLocationProvider.overrideWithValue(start),
          authServiceProvider.overrideWithValue(auth),
          firebaseCallGuardProvider.overrideWithValue(guard),
          // The app reads these from Supabase now (Objective 1); the
          // harness keeps them in the same in-memory Firestore as the rest.
          userRepositoryProvider.overrideWithValue(data.users),
          facilityRepositoryProvider.overrideWithValue(data.facilities),
          damageReportRepositoryProvider.overrideWithValue(data.reports),
          workOrderRepositoryProvider.overrideWithValue(data.workOrders),
          feedbackRepositoryProvider.overrideWithValue(data.feedback),
          taskRepositoryProvider.overrideWithValue(data.tasks),
          accomplishmentReportRepositoryProvider.overrideWithValue(
            data.accomplishments,
          ),
          materialUsageRepositoryProvider.overrideWithValue(data.materials),
          inventoryRepositoryProvider.overrideWithValue(data.inventory),
          materialRequestRepositoryProvider.overrideWithValue(data.requests),
          materialAllocationRepositoryProvider.overrideWithValue(
            data.allocations,
          ),
          toolRepositoryProvider.overrideWithValue(data.tools),
          notificationRepositoryProvider.overrideWithValue(
            FirestoreNotificationRepository(db: db, guard: guard),
          ),
          auditLogRepositoryProvider.overrideWithValue(
            FirestoreAuditLogRepository(db: db, guard: guard),
          ),
          configRepositoryProvider.overrideWithValue(config),
          photoPickerServiceProvider.overrideWithValue(picker),
          storageServiceProvider.overrideWithValue(storage),
          connectivityServiceProvider.overrideWithValue(connectivity),
          notificationServiceProvider.overrideWithValue(push),
          mapTileLayerProvider.overrideWithValue(const SizedBox.shrink()),
          qrScanLauncherProvider.overrideWithValue((_) async => null),
          personnelScanLauncherProvider.overrideWithValue((_) async {
            scans++;
            return nextScan;
          }),
          consoleScanLauncherProvider.overrideWithValue((_) async {
            scans++;
            return nextScan;
          }),
          fileDownloadServiceProvider.overrideWithValue(downloads),
        ],
        child: const GsuhubApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}
