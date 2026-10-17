import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/accomplishment/data/repositories/accomplishment_report_repository.dart';
import '../../features/accomplishment/data/repositories/accomplishment_report_repository_impl.dart';
import '../../features/accomplishment/data/repositories/material_usage_repository.dart';
import '../../features/accomplishment/data/repositories/material_usage_repository_impl.dart';
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
import '../../features/inventory/data/repositories/material_allocation_repository.dart';
import '../../features/inventory/data/repositories/material_allocation_repository_impl.dart';
import '../../features/inventory/data/repositories/material_request_repository.dart';
import '../../features/inventory/data/repositories/material_request_repository_impl.dart';
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
/// the backend means changing this file and nothing else, which is how
/// Objective 1 moved the data to Supabase.

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final facilityRepositoryProvider = Provider<FacilityRepository>(
  (ref) => FacilityRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final damageReportRepositoryProvider = Provider<DamageReportRepository>(
  (ref) => DamageReportRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final workOrderRepositoryProvider = Provider<WorkOrderRepository>(
  (ref) => WorkOrderRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final accomplishmentReportRepositoryProvider =
    Provider<AccomplishmentReportRepository>(
      (ref) => AccomplishmentReportRepositoryImpl(
        client: ref.watch(supabaseClientProvider),
        guard: ref.watch(supabaseCallGuardProvider),
      ),
    );

final materialUsageRepositoryProvider = Provider<MaterialUsageRepository>(
  (ref) => MaterialUsageRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final materialRequestRepositoryProvider = Provider<MaterialRequestRepository>(
  (ref) => MaterialRequestRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final materialAllocationRepositoryProvider =
    Provider<MaterialAllocationRepository>(
      (ref) => MaterialAllocationRepositoryImpl(
        client: ref.watch(supabaseClientProvider),
        guard: ref.watch(supabaseCallGuardProvider),
      ),
    );

final toolRepositoryProvider = Provider<ToolRepository>(
  (ref) => ToolRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final auditLogRepositoryProvider = Provider<AuditLogRepository>(
  (ref) => AuditLogRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
  ),
);
