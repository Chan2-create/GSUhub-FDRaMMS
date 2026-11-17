import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/accomplishment/data/repositories/accomplishment_report_repository.dart';
import '../../features/accomplishment/data/repositories/accomplishment_report_repository_impl.dart';
import '../../features/accomplishment/data/repositories/material_usage_repository.dart';
import '../../features/accomplishment/data/repositories/material_usage_repository_impl.dart';
import '../../features/audit/data/repositories/audit_log_repository.dart';
import '../../features/audit/data/repositories/audit_log_repository_impl.dart';
import '../../features/auth/data/repositories/session_repository.dart';
import '../../features/auth/data/repositories/session_repository_impl.dart';
import '../../features/classification/data/repositories/config_repository.dart';
import '../../features/classification/data/repositories/config_repository_impl.dart';
import '../../features/damage_reports/data/repositories/damage_report_repository.dart';
import '../../features/damage_reports/data/repositories/damage_report_repository_impl.dart';
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
import '../../features/tasks/data/repositories/task_repository.dart';
import '../../features/tasks/data/repositories/task_repository_impl.dart';
import '../../features/tools/data/repositories/tool_repository.dart';
import '../../features/tools/data/repositories/tool_repository_impl.dart';
import '../../features/user_management/data/repositories/user_repository.dart';
import '../../features/user_management/data/repositories/user_repository_impl.dart';
import '../../features/work_orders/data/repositories/work_order_repository.dart';
import '../../features/work_orders/data/repositories/work_order_repository_impl.dart';
import '../data/live_sync.dart';
import 'service_providers.dart';

/// Repository dependency injection.
///
/// Every provider is typed as the **interface**, never the
/// implementation, so features built in Objectives 2–6 depend on the
/// contract and can be tested against a fake without Firebase. Swapping
/// the backend means changing this file and nothing else, which is how
/// Objective 1 moved the data to Supabase.
///
/// Every repository is rebuilt when the signed-in person changes
/// ([sessionScopeProvider]), and with it every provider that reads through
/// one: what was loaded for one sign-in is dropped, and read again for the
/// next (2026-11-16). Before that, a list loaded once stayed in memory
/// across a sign-out, with a live connection the sign-out had closed.

/// What keeps a repository's live views current.
LiveSync _liveFor(Ref ref) {
  ref.watch(sessionScopeProvider);
  return ref.watch(liveSyncProvider);
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

/// The session's keep-alive (2026-11-14): tells the database the signed-in
/// person is active, so it does not end their session as idle.
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final facilityRepositoryProvider = Provider<FacilityRepository>(
  (ref) => FacilityRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final damageReportRepositoryProvider = Provider<DamageReportRepository>(
  (ref) => DamageReportRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final workOrderRepositoryProvider = Provider<WorkOrderRepository>(
  (ref) => WorkOrderRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final accomplishmentReportRepositoryProvider =
    Provider<AccomplishmentReportRepository>(
      (ref) => AccomplishmentReportRepositoryImpl(
        client: ref.watch(supabaseClientProvider),
        guard: ref.watch(supabaseCallGuardProvider),
        live: _liveFor(ref),
      ),
    );

final materialUsageRepositoryProvider = Provider<MaterialUsageRepository>(
  (ref) => MaterialUsageRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final materialRequestRepositoryProvider = Provider<MaterialRequestRepository>(
  (ref) => MaterialRequestRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final materialAllocationRepositoryProvider =
    Provider<MaterialAllocationRepository>(
      (ref) => MaterialAllocationRepositoryImpl(
        client: ref.watch(supabaseClientProvider),
        guard: ref.watch(supabaseCallGuardProvider),
        live: _liveFor(ref),
      ),
    );

final toolRepositoryProvider = Provider<ToolRepository>(
  (ref) => ToolRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final auditLogRepositoryProvider = Provider<AuditLogRepository>(
  (ref) => AuditLogRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
    guard: ref.watch(supabaseCallGuardProvider),
    live: _liveFor(ref),
  ),
);
