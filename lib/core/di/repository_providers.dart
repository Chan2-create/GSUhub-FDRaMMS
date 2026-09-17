import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/accomplishment/data/repositories/accomplishment_report_repository.dart';
import '../../features/accomplishment/data/repositories/accomplishment_report_repository_impl.dart';
import '../../features/audit/data/repositories/audit_log_repository.dart';
import '../../features/audit/data/repositories/audit_log_repository_impl.dart';
import '../../features/classification/data/repositories/config_repository.dart';
import '../../features/classification/data/repositories/config_repository_impl.dart';
import '../../features/facilities/data/repositories/facility_repository.dart';
import '../../features/facilities/data/repositories/facility_repository_impl.dart';
import '../../features/feedback/data/repositories/feedback_repository.dart';
import '../../features/feedback/data/repositories/feedback_repository_impl.dart';
import '../../features/inventory/data/repositories/inventory_repository.dart';
import '../../features/inventory/data/repositories/inventory_repository_impl.dart';
import '../../features/notifications/data/repositories/notification_repository.dart';
import '../../features/notifications/data/repositories/notification_repository_impl.dart';
import '../../features/reporting/data/repositories/damage_report_repository.dart';
import '../../features/reporting/data/repositories/damage_report_repository_impl.dart';
import '../../features/tasks/data/repositories/task_repository.dart';
import '../../features/tasks/data/repositories/task_repository_impl.dart';
import '../../features/tools/data/repositories/tool_repository.dart';
import '../../features/tools/data/repositories/tool_repository_impl.dart';
import '../../features/user_management/data/repositories/user_repository.dart';
import '../../features/user_management/data/repositories/user_repository_impl.dart';
import '../../features/work_orders/data/repositories/work_order_repository.dart';
import '../../features/work_orders/data/repositories/work_order_repository_impl.dart';
import 'service_providers.dart';

/// Repository dependency injection.
///
/// Every provider is typed as the **interface**, never the
/// implementation, so features built in Objectives 2–6 depend on the
/// contract and can be tested against a fake without Firebase. Swapping
/// the backend would mean changing this file and nothing else.

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final facilityRepositoryProvider = Provider<FacilityRepository>(
  (ref) => FacilityRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final damageReportRepositoryProvider = Provider<DamageReportRepository>(
  (ref) => DamageReportRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final workOrderRepositoryProvider = Provider<WorkOrderRepository>(
  (ref) => WorkOrderRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final accomplishmentReportRepositoryProvider =
    Provider<AccomplishmentReportRepository>(
      (ref) => AccomplishmentReportRepositoryImpl(
        db: ref.watch(firestoreServiceImplProvider),
        guard: ref.watch(firebaseCallGuardProvider),
      ),
    );

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final toolRepositoryProvider = Provider<ToolRepository>(
  (ref) => ToolRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final auditLogRepositoryProvider = Provider<AuditLogRepository>(
  (ref) => AuditLogRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepositoryImpl(
    db: ref.watch(firestoreServiceImplProvider),
    guard: ref.watch(firebaseCallGuardProvider),
  ),
);
