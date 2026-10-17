import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/task_status.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/services/firebase/firebase_call_guard.dart';
import 'package:gsuhub/core/services/firebase/firestore_service_impl.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/accomplishment_report_repository_firestore.dart';
import 'package:gsuhub/features/accomplishment/data/repositories/material_usage_repository_firestore.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/facilities/data/repositories/facility_repository_firestore.dart';
import 'package:gsuhub/features/feedback/data/repositories/feedback_repository_firestore.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item.dart';
import 'package:gsuhub/features/inventory/data/repositories/inventory_repository_firestore.dart';
import 'package:gsuhub/features/inventory/data/repositories/material_allocation_repository_firestore.dart';
import 'package:gsuhub/features/inventory/data/repositories/material_request_repository_firestore.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository_firestore.dart';
import 'package:gsuhub/features/tasks/data/models/maintenance_task.dart';
import 'package:gsuhub/features/tasks/data/repositories/task_repository_firestore.dart';
import 'package:gsuhub/features/tools/data/models/tool.dart';
import 'package:gsuhub/features/tools/data/repositories/tool_repository_firestore.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository_firestore.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/data/repositories/work_order_repository_firestore.dart';

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
    reports = FirestoreDamageReportRepository(db: db, guard: guard);
    workOrders = FirestoreWorkOrderRepository(db: db, guard: guard);
    users = FirestoreUserRepository(db: db, guard: guard);
    feedback = FirestoreFeedbackRepository(db: db, guard: guard);
    tasks = FirestoreTaskRepository(db: db, guard: guard);
    accomplishments = FirestoreAccomplishmentReportRepository(
      db: db,
      guard: guard,
    );
    materials = FirestoreMaterialUsageRepository(db: db, guard: guard);
    tools = FirestoreToolRepository(db: db, guard: guard);
    inventory = FirestoreInventoryRepository(db: db, guard: guard);
    requests = FirestoreMaterialRequestRepository(db: db, guard: guard);
    allocations = FirestoreMaterialAllocationRepository(db: db, guard: guard);
    facilities = FirestoreFacilityRepository(db: db, guard: guard);
  }

  final FakeFirebaseFirestore firestore;
  late final FirestoreDamageReportRepository reports;
  late final FirestoreWorkOrderRepository workOrders;
  late final FirestoreUserRepository users;
  late final FirestoreFeedbackRepository feedback;
  late final FirestoreTaskRepository tasks;
  late final FirestoreAccomplishmentReportRepository accomplishments;
  late final FirestoreMaterialUsageRepository materials;
  late final FirestoreToolRepository tools;
  late final FirestoreInventoryRepository inventory;
  late final FirestoreMaterialRequestRepository requests;
  late final FirestoreMaterialAllocationRepository allocations;
  late final FirestoreFacilityRepository facilities;

  static const admin = AuditActor(id: 'admin-1', name: 'Ramon Dela Cruz');

  /// The technician [addWorkOrder] assigns by default (Objective 5).
  static const technician = AuditActor(
    id: 'personnel-1',
    name: 'Marcus Wright',
  );

  /// A material in stock (Objective 5.C).
  Future<void> addInventoryItem(
    String id, {
    String name = 'LED Bulbs',
    double quantity = 10,
    String unit = 'units',
    double minimum = 2,
    double? unitCost,
  }) => firestore
      .collection(FirestorePaths.inventoryItems)
      .doc(id)
      .set(
        InventoryItem(
          id: id,
          name: name,
          category: 'Electrical',
          quantityAvailable: quantity,
          unitOfMeasurement: unit,
          storageLocation: 'GSU Store',
          qrCode: 'INV-${id.toUpperCase()}',
          minimumThreshold: minimum,
          unitCost: unitCost,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ).toFirestore(),
      );

  /// A tool on the shelf, or out (Objective 5.C).
  Future<void> addTool(
    String id, {
    ToolStatus status = ToolStatus.available,
    ItemCondition condition = ItemCondition.good,
  }) => firestore
      .collection(FirestorePaths.tools)
      .doc(id)
      .set(
        Tool(
          id: id,
          toolCode: 'TL-0001',
          name: 'Fluke Multimeter',
          status: status,
          condition: condition,
          qrCode: 'TOOL-TL-0001',
          currentHolderId: status == ToolStatus.borrowed ? 'personnel-2' : null,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ).toFirestore(),
      );

  /// A task on a work order (Objective 5.A).
  Future<void> addTask(
    String id, {
    required String workOrderId,
    TaskStatus status = TaskStatus.pending,
    String assignedTo = 'personnel-1',
    DateTime? dueDate,
  }) => firestore
      .collection(FirestorePaths.tasks)
      .doc(id)
      .set(
        MaintenanceTask(
          id: id,
          workOrderId: workOrderId,
          title: 'Replace the ballast',
          assignedTo: assignedTo,
          status: status,
          dueDate: dueDate,
          completedAt: status == TaskStatus.completed
              ? DateTime.utc(2026, 9, 2)
              : null,
          createdAt: DateTime.utc(2026, 9),
          updatedAt: DateTime.utc(2026, 9),
        ).toFirestore(),
      );

  Future<void> addReport(
    String id, {
    ReportStatus status = ReportStatus.approved,
    DamageCategory? category = DamageCategory.electrical,
    PriorityLevel? officialPriority = PriorityLevel.high,
    String? workOrderId,
    String reporterId = 'faculty-1',
    DateTime? submittedAt,
  }) => firestore
      .collection(FirestorePaths.damageReports)
      .doc(id)
      .set(
        DamageReport(
          id: id,
          reporterId: reporterId,
          reporterName: 'Maria Santos',
          title: 'Flickering lights',
          description: 'Lights in Room 101 flicker constantly.',
          requestorPriority: PriorityLevel.high,
          status: status,
          category: category,
          officialPriority: officialPriority,
          facilityId: 'fac-engineering',
          facilityName: 'Engineering Building',
          workOrderId: workOrderId,
          submittedAt: submittedAt ?? DateTime.utc(2026, 9),
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

  /// Every notification written, in no particular order.
  Future<List<Map<String, dynamic>>> notifications() async =>
      (await firestore.collection(FirestorePaths.notifications).get()).docs
          .map((doc) => doc.data())
          .toList();

  /// A report's status history entries, in no particular order.
  Future<List<Map<String, dynamic>>> history(String reportId) async =>
      (await firestore
              .collection(FirestorePaths.damageReports)
              .doc(reportId)
              .collection(FirestorePaths.statusHistory)
              .get())
          .docs
          .map((doc) => doc.data())
          .toList();

  Future<int> count(String collection) async =>
      (await firestore.collection(collection).get()).size;
}

/// `Timestamp` values read back from the fake, for assertions that a
/// server timestamp was written without depending on the clock.
bool isTimestamp(Object? value) => value is Timestamp;
