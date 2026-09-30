import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/audit_action.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/utils/result.dart';
import '../../audit/data/models/audit_log_entry.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/presentation/report_providers.dart';

/// The four summary counts shown on the stat cards.
///
/// Statuses are grouped by what an administrator does about them, not by
/// enum order: anything awaiting a decision is one number, anything being
/// worked is another.
class DashboardCounts {
  const DashboardCounts({
    required this.total,
    required this.needsReview,
    required this.inProgress,
    required this.completed,
  });

  factory DashboardCounts.from(List<DamageReport> reports) {
    var needsReview = 0;
    var inProgress = 0;
    var completed = 0;
    var total = 0;

    for (final report in reports) {
      switch (report.status) {
        case ReportStatus.submitted:
        case ReportStatus.underReview:
          needsReview++;
          total++;
        case ReportStatus.approved:
        case ReportStatus.assigned:
        case ReportStatus.inProgress:
        case ReportStatus.forReview:
          inProgress++;
          total++;
        case ReportStatus.completed:
        case ReportStatus.closed:
          completed++;
          total++;
        case ReportStatus.merged:
        case ReportStatus.rejected:
        case ReportStatus.archived:
          break;
      }
    }

    return DashboardCounts(
      total: total,
      needsReview: needsReview,
      inProgress: inProgress,
      completed: completed,
    );
  }

  /// Every active report — excludes merged, rejected and archived, which
  /// are outcomes rather than work.
  final int total;

  /// `submitted` + `underReview` — the administrator's action queue.
  final int needsReview;

  /// `approved` + `assigned` + `inProgress` + `forReview`.
  final int inProgress;

  /// `completed` + `closed`.
  final int completed;
}

final dashboardCountsProvider = Provider<AsyncValue<Result<DashboardCounts>>>(
  (ref) => ref
      .watch(reportsStreamProvider)
      .whenData((result) => result.map(DashboardCounts.from)),
);

/// The five most recent reports, for the Recent Reports table.
final recentReportsProvider = Provider<AsyncValue<Result<List<DamageReport>>>>(
  (ref) => ref
      .watch(reportsStreamProvider)
      .whenData((result) => result.map((reports) => reports.take(5).toList())),
);

/// One slice of the category donut.
class CategorySlice {
  const CategorySlice({
    required this.label,
    required this.count,
    required this.share,
  });

  final String label;
  final int count;

  /// 0.0–1.0 share of the total.
  final double share;
}

/// Report counts per damage category.
///
/// Unclassified reports are counted under "Unclassified" rather than
/// dropped: manuscript §3.4 routes anything the keyword matcher cannot
/// place to the Administrator, so how many are waiting is exactly the kind
/// of thing this chart should surface.
final reportsByCategoryProvider =
    Provider<AsyncValue<Result<List<CategorySlice>>>>(
      (ref) => ref
          .watch(reportsStreamProvider)
          .whenData(
            (result) => result.map((reports) {
              if (reports.isEmpty) return const <CategorySlice>[];

              final counts = <String, int>{};
              for (final report in reports) {
                final label = report.category?.label ?? 'Unclassified';
                counts[label] = (counts[label] ?? 0) + 1;
              }

              final ordered = counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return [
                for (final entry in ordered)
                  CategorySlice(
                    label: entry.key,
                    count: entry.value,
                    share: entry.value / reports.length,
                  ),
              ];
            }),
          ),
    );

/// One bar in "Monthly Report Volume by Building".
class BuildingVolume {
  const BuildingVolume({
    required this.facilityName,
    required this.currentMonth,
    required this.previousMonth,
  });

  final String facilityName;
  final int currentMonth;
  final int previousMonth;

  int get total => currentMonth + previousMonth;
}

/// Report volume per facility, split into this month and last.
///
/// Computed from the same stream rather than a dedicated aggregate query:
/// Firestore cannot group-by, so either way the grouping happens client
/// side, and reusing the stream avoids a second read of the same
/// documents.
final reportVolumeByBuildingProvider =
    Provider<AsyncValue<Result<List<BuildingVolume>>>>(
      (ref) => ref
          .watch(reportsStreamProvider)
          .whenData(
            (result) => result.map((reports) {
              final now = DateTime.now().toUtc();
              final currentMonthStart = DateTime.utc(now.year, now.month);
              final previousMonthStart = DateTime.utc(now.year, now.month - 1);

              final current = <String, int>{};
              final previous = <String, int>{};

              for (final report in reports) {
                final name = report.facilityName ?? 'Unspecified location';
                final submitted = report.submittedAt;

                if (!submitted.isBefore(currentMonthStart)) {
                  current[name] = (current[name] ?? 0) + 1;
                } else if (!submitted.isBefore(previousMonthStart)) {
                  previous[name] = (previous[name] ?? 0) + 1;
                }
              }

              final names = {...current.keys, ...previous.keys};
              final volumes = [
                for (final name in names)
                  BuildingVolume(
                    facilityName: name,
                    currentMonth: current[name] ?? 0,
                    previousMonth: previous[name] ?? 0,
                  ),
              ]..sort((a, b) => b.currentMonth.compareTo(a.currentMonth));

              // The design shows a short list, not every building on campus.
              return volumes.take(5).toList();
            }),
          ),
    );

/// Recent activity feed.
///
/// Filtered to the lifecycle events an administrator would want to see —
/// a report arriving, a decision being taken, work finishing — rather than
/// every field edit the audit log records. Dumping the raw log would bury
/// "a critical report came in" under a dozen `updated` rows.
final recentActivityProvider = FutureProvider<Result<List<AuditLogEntry>>>((
  ref,
) async {
  final repository = ref.watch(auditLogRepositoryProvider);

  // Pull more than is displayed, because the filter below discards
  // some of what comes back.
  final result = await repository.query(limit: 40);

  return result.map(
    (entries) => entries
        .where(
          (entry) => const {
            AuditAction.created,
            AuditAction.statusChanged,
            AuditAction.assigned,
            AuditAction.merged,
          }.contains(entry.action),
        )
        .take(3)
        .toList(),
  );
});

/// Unread notification badge count for the signed-in user.
final unreadNotificationCountProvider =
    StreamProvider.family<Result<int>, String>(
      (ref, userId) =>
          ref.watch(notificationRepositoryProvider).watchUnreadCount(userId),
    );

/// Re-runs every dashboard query. Wired to the retry action on error
/// states.
void refreshDashboard(WidgetRef ref) {
  ref
    ..invalidate(reportsStreamProvider)
    ..invalidate(recentActivityProvider);
}

/// Category display labels, exposed so the donut legend and the table's
/// category subtitle read identically.
String categoryLabel(DamageCategory? category) =>
    category?.label ?? 'Unclassified';
