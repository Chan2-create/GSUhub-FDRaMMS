import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/repository_providers.dart';
import '../../../../core/di/service_providers.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/utils/result.dart';
import '../../../accomplishment/data/models/accomplishment_report.dart';
import '../../../accomplishment/data/models/recorded_material.dart';
import '../../../inventory/data/models/material_request.dart';
import '../../../tasks/data/models/maintenance_task.dart';
import '../../../tasks/domain/task_day.dart';
import '../../../tools/data/models/tool.dart';
import '../../../tools/data/models/tool_loan.dart';
import '../../data/models/work_order.dart';

// Every inventory item by name, and a work order's pre-assigned materials:
// one definition each, shared with the console (Objective 6).
export '../../../inventory/presentation/inventory_providers.dart'
    show allocatedMaterialsProvider, inventoryItemsProvider;

/// What the personnel app reads (Objective 5). Every list is the signed-in
/// technician's own — the rules allow nothing else — and live.

/// The signed-in person's uid: the live auth state first, then the
/// service's cached user — the stream has not necessarily emitted by the
/// first read.
String? signedInUid(Ref ref) =>
    (ref.watch(authStateProvider).value ??
            ref.read(authServiceProvider).currentUser)
        ?.uid;

/// [signedInUid], for widgets.
final signedInUidProvider = Provider.autoDispose<String?>(signedInUid);

/// The technician's work orders, newest first.
final myWorkOrdersProvider =
    StreamProvider.autoDispose<Result<List<WorkOrder>>>((ref) {
      final uid = signedInUid(ref);
      if (uid == null) return Stream.value(const Result.success([]));
      return ref.watch(workOrderRepositoryProvider).watchByAssignee(uid);
    });

/// The technician's tasks, soonest due first.
final myTasksProvider =
    StreamProvider.autoDispose<Result<List<MaintenanceTask>>>((ref) {
      final uid = signedInUid(ref);
      if (uid == null) return Stream.value(const Result.success([]));
      return ref.watch(taskRepositoryProvider).watchByAssignee(uid);
    });

/// The technician's work, put together for the dashboard and the Tasks
/// tab: work orders by id, and the tasks of the day.
class MyWork {
  MyWork({
    required List<WorkOrder> workOrders,
    required this.tasks,
    required DateTime now,
  }) : workOrders = {for (final order in workOrders) order.id: order},
       today = TaskDay.today(
         tasks,
         openWorkOrderIds: {
           for (final order in workOrders)
             if (isOpen(order.status)) order.id,
         },
         now: now,
       ),
       upcoming = TaskDay.upcoming(
         tasks,
         openWorkOrderIds: {
           for (final order in workOrders)
             if (isOpen(order.status)) order.id,
         },
         now: now,
       );

  /// The technician's work orders, by id.
  final Map<String, WorkOrder> workOrders;

  final List<MaintenanceTask> tasks;

  /// Today's to-do (Figure 24).
  final List<MaintenanceTask> today;

  /// Open tasks due after today.
  final List<MaintenanceTask> upcoming;

  /// Work still with the technician: not yet signed off.
  int get pendingWork => workOrders.values
      .where((order) => order.status != WorkOrderStatus.completed)
      .length;

  int get completedWork => workOrders.values
      .where((order) => order.status == WorkOrderStatus.completed)
      .length;

  /// Work the technician can still act on.
  static bool isOpen(WorkOrderStatus status) =>
      status == WorkOrderStatus.pending || status == WorkOrderStatus.inProgress;
}

/// [MyWork], once both its lists have loaded.
final myWorkProvider = Provider.autoDispose<AsyncValue<Result<MyWork>>>((ref) {
  final orders = ref.watch(myWorkOrdersProvider);
  final tasks = ref.watch(myTasksProvider);
  return switch ((orders, tasks)) {
    (AsyncData(value: final o), AsyncData(value: final t)) => AsyncData(
      switch ((o, t)) {
        (Success(value: final workOrders), Success(value: final list)) =>
          Result.success(
            MyWork(workOrders: workOrders, tasks: list, now: DateTime.now()),
          ),
        (Error(:final failure), _) ||
        (_, Error(:final failure)) => Result.failure(failure),
      },
    ),
    (AsyncError(:final error, :final stackTrace), _) ||
    (
      _,
      AsyncError(:final error, :final stackTrace),
    ) => AsyncError(error, stackTrace),
    _ => const AsyncLoading(),
  };
});

/// One work order, live.
final personnelWorkOrderProvider = StreamProvider.autoDispose
    .family<Result<WorkOrder>, String>(
      (ref, id) => ref.watch(workOrderRepositoryProvider).watchById(id),
    );

/// The materials recorded on a work order (5.C).
final recordedMaterialsProvider = StreamProvider.autoDispose
    .family<Result<List<RecordedMaterial>>, String>(
      (ref, workOrderId) => ref
          .watch(materialUsageRepositoryProvider)
          .watchForWorkOrder(workOrderId),
    );

/// The technician's accomplishment reports for a work order, newest
/// first (5.B).
final myAccomplishmentReportsProvider = StreamProvider.autoDispose
    .family<Result<List<AccomplishmentReport>>, String>((ref, workOrderId) {
      final uid = signedInUid(ref);
      if (uid == null) return Stream.value(const Result.success([]));
      return ref
          .watch(accomplishmentReportRepositoryProvider)
          .watchByWorkOrder(workOrderId, submittedBy: uid);
    });

/// The tools the technician has out (5.C).
final myToolLoansProvider = StreamProvider.autoDispose<Result<List<ToolLoan>>>((
  ref,
) {
  final uid = signedInUid(ref);
  if (uid == null) return Stream.value(const Result.success([]));
  return ref.watch(toolRepositoryProvider).watchOpenLoansFor(uid);
});

/// The technician's requests for materials on one work order, newest
/// first (Objective 6.B). Only their own: the rules list nothing else.
final myMaterialRequestsProvider = StreamProvider.autoDispose
    .family<Result<List<MaterialRequest>>, String>((ref, workOrderId) {
      final uid = signedInUid(ref);
      if (uid == null) return Stream.value(const Result.success([]));
      return ref
          .watch(materialRequestRepositoryProvider)
          .watchForWorkOrder(workOrderId, requestedBy: uid);
    });

/// Tools on the shelf, ready to borrow.
final availableToolsProvider = StreamProvider.autoDispose<Result<List<Tool>>>(
  (ref) => ref
      .watch(toolRepositoryProvider)
      .watchTools(status: ToolStatus.available),
);
