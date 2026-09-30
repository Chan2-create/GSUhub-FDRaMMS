import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/services/firebase/firebase_call_guard.dart';
import 'package:gsuhub/core/services/firebase/firestore_service_impl.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository_impl.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/data/repositories/work_order_repository_impl.dart';

import 'test_app_config.dart';

/// The real repositories over an in-memory Firestore.
///
/// Used where the logic under test *is* the Firestore interaction — the
/// transactions that guard lifecycle moves — so a hand-written fake would
/// be testing itself. `fake_cloud_firestore` runs real transactions,
/// increments and server timestamps.
class FirestoreHarness {
  FirestoreHarness() : firestore = FakeFirebaseFirestore() {
    final guard = FirebaseCallGuard(testAppConfig());
    final db = FirestoreServiceImpl(firestore: firestore, guard: guard);
    reports = DamageReportRepositoryImpl(db: db, guard: guard);
    workOrders = WorkOrderRepositoryImpl(db: db, guard: guard);
  }

  final FakeFirebaseFirestore firestore;
  late final DamageReportRepositoryImpl reports;
  late final WorkOrderRepositoryImpl workOrders;

  static const admin = AuditActor(id: 'admin-1', name: 'Ramon Dela Cruz');

  Future<void> addReport(
    String id, {
    ReportStatus status = ReportStatus.approved,
    DamageCategory? category = DamageCategory.electrical,
    String? workOrderId,
  }) => firestore
      .collection(FirestorePaths.damageReports)
      .doc(id)
      .set(
        DamageReport(
          id: id,
          reporterId: 'faculty-1',
          reporterName: 'Maria Santos',
          title: 'Flickering lights',
          description: 'Lights in Room 101 flicker constantly.',
          requestorPriority: PriorityLevel.high,
          status: status,
          category: category,
          facilityId: 'fac-engineering',
          facilityName: 'Engineering Building',
          workOrderId: workOrderId,
          submittedAt: DateTime.utc(2026, 9),
          updatedAt: DateTime.utc(2026, 9),
        ).toFirestore(),
      );

  Future<void> addPersonnel(
    String id, {
    AccountStatus accountStatus = AccountStatus.active,
    UserRole role = UserRole.maintenancePersonnel,
    int activeTaskCount = 0,
  }) => firestore
      .collection(FirestorePaths.users)
      .doc(id)
      .set(
        AppUser(
          id: id,
          fullName: 'Marcus Wright',
          email: '$id@dorsu.edu.ph',
          role: role,
          accountStatus: accountStatus,
          specialization: DamageCategory.electrical,
          activeTaskCount: activeTaskCount,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ).toFirestore(),
      );

  Future<void> addWorkOrder(
    String id, {
    required List<String> reportIds,
    required WorkOrderStatus status,
    List<String> assignedPersonnelIds = const ['personnel-1'],
  }) => firestore
      .collection(FirestorePaths.workOrders)
      .doc(id)
      .set(
        WorkOrder(
          id: id,
          reportIds: reportIds,
          title: 'Flickering lights',
          description: 'Lights in Room 101 flicker constantly.',
          category: DamageCategory.electrical,
          priority: PriorityLevel.high,
          status: status,
          assignedPersonnelIds: assignedPersonnelIds,
          createdBy: 'admin-1',
          createdAt: DateTime.utc(2026, 9),
          updatedAt: DateTime.utc(2026, 9),
        ).toFirestore(),
      );

  Future<Map<String, dynamic>> doc(String collection, String id) async =>
      (await firestore.collection(collection).doc(id).get()).data() ?? {};

  Future<List<Map<String, dynamic>>> auditEntries() async =>
      (await firestore.collection(FirestorePaths.auditLogs).get()).docs
          .map((doc) => doc.data())
          .toList();

  Future<int> count(String collection) async =>
      (await firestore.collection(collection).get()).size;
}

/// `Timestamp` values read back from the fake, for assertions that a
/// server timestamp was written without depending on the clock.
bool isTimestamp(Object? value) => value is Timestamp;
