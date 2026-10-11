import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/repository_providers.dart';
import '../../../../core/di/service_providers.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/result.dart';
import '../../data/models/damage_report.dart';
import '../../data/models/status_change.dart';

/// The signed-in requestor's reports, newest first, live (Objective 3.B).
///
/// One listener feeds the home screen's counts and recent list and the
/// whole of My Reports, so the three always agree, and an administrator's
/// decision shows on them without a refresh. Auto-disposed: the listener
/// closes when the last screen using it does, and signing out swaps it for
/// an empty list before the rules would start refusing it.
final myReportsProvider =
    StreamProvider.autoDispose<Result<List<DamageReport>>>((ref) {
      // The live auth state first, falling back to the service's cached
      // user: the stream has not necessarily emitted by the first read.
      final user =
          ref.watch(authStateProvider).value ??
          ref.read(authServiceProvider).currentUser;
      if (user == null) {
        return Stream.value(const Result.success(<DamageReport>[]));
      }
      return ref
          .watch(damageReportRepositoryProvider)
          .watchByReporter(user.uid);
    });

/// One of the requestor's reports, live, for its detail page. The rules
/// let a requestor open only their own.
final myReportProvider = StreamProvider.autoDispose
    .family<Result<DamageReport>, String>(
      (ref, reportId) =>
          ref.watch(damageReportRepositoryProvider).watchById(reportId),
    );

/// The report's status history, oldest first, live — the detail page's
/// timeline (Objective 3.B).
final myReportHistoryProvider = StreamProvider.autoDispose
    .family<Result<List<StatusChange>>, String>(
      (ref, reportId) => ref
          .watch(damageReportRepositoryProvider)
          .watchStatusHistory(reportId),
    );

/// The banner's three counts on the home screen (Figma `170:2050`: "8
/// Active • 2 In-Progress • 10 Completed"): reports awaiting the
/// administrator, being worked, and finished. Reports that ended without
/// the work being done — merged, rejected, archived — are in none of them.
@immutable
class ReportOverview {
  const ReportOverview({
    required this.active,
    required this.inProgress,
    required this.completed,
  });

  factory ReportOverview.of(Iterable<DamageReport> reports) {
    var active = 0;
    var inProgress = 0;
    var completed = 0;
    for (final report in reports) {
      switch (report.status.progress) {
        case ReportProgress.pending:
          active++;
        case ReportProgress.inProgress:
          inProgress++;
        case ReportProgress.completed:
          completed++;
        case ReportProgress.closedOut:
          break;
      }
    }
    return ReportOverview(
      active: active,
      inProgress: inProgress,
      completed: completed,
    );
  }

  final int active;
  final int inProgress;
  final int completed;

  /// The banner line, worded as drawn.
  String get summary =>
      '$active Active • $inProgress In-Progress • $completed Completed';
}

/// My Reports' search and filter (Figma `169:1251`).
@immutable
class MyReportsView {
  const MyReportsView({this.progress, this.search = ''});

  /// Null is "All".
  final ReportProgress? progress;
  final String search;

  /// The filters the design draws, in order after "All". A report that
  /// ended without the work being done appears under "All" only.
  static const List<ReportProgress> filters = [
    ReportProgress.pending,
    ReportProgress.inProgress,
    ReportProgress.completed,
  ];

  /// Whether [report] survives the filter and the search. The search
  /// matches the location the card shows, the title the requestor gave,
  /// the damage type, and the report number.
  bool matches(DamageReport report) {
    if (progress != null && report.status.progress != progress) return false;

    final query = search.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      report.title,
      report.locationDescription,
      report.facilityName,
      report.category?.label,
      report.requestorCategory?.label,
      DisplayId.report(report.id),
    ].any((text) => text != null && text.toLowerCase().contains(query));
  }
}

class MyReportsViewController extends Notifier<MyReportsView> {
  @override
  MyReportsView build() => const MyReportsView();

  void setProgress(ReportProgress? progress) =>
      state = MyReportsView(progress: progress, search: state.search);

  void setSearch(String search) =>
      state = MyReportsView(progress: state.progress, search: search);
}

final myReportsViewProvider =
    NotifierProvider<MyReportsViewController, MyReportsView>(
      MyReportsViewController.new,
    );
