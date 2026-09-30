import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/enums/date_range_filter.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../reporting/presentation/report_providers.dart';
import '../../user_management/data/models/app_user.dart';
import '../../user_management/presentation/personnel_providers.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/work_order_providers.dart';
import 'analytics_providers.dart';
import 'analytics_summary.dart';

/// The Export Data file: the Analytics summary for the selected period,
/// then every report submitted in it with its work order.
///
/// CSV because it opens in Excel on any GSU machine without a new
/// dependency here, and because a spreadsheet is what someone preparing an
/// accomplishment report will want to reshape (decided for 2.C).
abstract final class AnalyticsExport {
  static final DateFormat _stamp = DateFormat('yyyy-MM-dd HH:mm');

  /// `gsuhub-analytics-last-30-days-2026-09-25.csv`
  static String fileName(DateRangeFilter range, DateTime now) {
    final slug = range.label.toLowerCase().replaceAll(' ', '-');
    return 'gsuhub-analytics-$slug-${DateFormat('yyyy-MM-dd').format(now)}.csv';
  }

  static const List<String> reportColumns = [
    'Report ID',
    'Title',
    'Category',
    'Priority',
    'Status',
    'Location',
    'Reported By',
    'Submitted',
    'Reviewed',
    'Work Order',
    'Assigned To',
    'Completed',
    'Resolution (days)',
  ];

  static String buildCsv({
    required AnalyticsSummary summary,
    required List<DamageReport> reports,
    required List<WorkOrder> workOrders,
    required Map<String, String> personnelNames,
    required DateTime now,
  }) {
    final workOrderById = {for (final w in workOrders) w.id: w};
    final inRange =
        reports
            .where((r) => summary.range.includes(r.submittedAt, now))
            .toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    String days(double? value) => value == null ? '' : value.toStringAsFixed(1);
    String when(DateTime? moment) =>
        moment == null ? '' : _stamp.format(moment.toLocal());

    List<String> rowFor(DamageReport report) {
      final workOrder = report.workOrderId == null
          ? null
          : workOrderById[report.workOrderId];
      final completed = workOrder?.completedAt;
      return [
        DisplayId.report(report.id),
        report.title,
        report.category?.label ?? 'Unclassified',
        report.isPriorityConfirmed
            ? report.effectivePriority.label
            : '${report.effectivePriority.label} (unconfirmed)',
        report.status.label,
        report.facilityName ?? report.locationDescription ?? '',
        report.reporterName,
        when(report.submittedAt),
        when(report.reviewedAt),
        workOrder == null ? '' : DisplayId.workOrder(workOrder.id),
        workOrder == null
            ? ''
            : workOrder.assignedPersonnelIds
                  .map((id) => personnelNames[id] ?? id)
                  .join('; '),
        when(completed),
        completed == null
            ? ''
            : days(
                completed.difference(report.submittedAt).inMinutes /
                    Duration.minutesPerDay,
              ),
      ];
    }

    final rows = <List<String>>[
      ['GSUhub Analytics Export'],
      ['Period', summary.range.label],
      ['Generated', _stamp.format(now.toLocal())],
      [],
      ['Total reports', '${summary.totalReports}'],
      ['Average resolution time (days)', days(summary.averageResolutionDays)],
      [
        'Completion rate',
        summary.completionRate == null
            ? ''
            : '${(summary.completionRate! * 100).round()}%',
      ],
      ['Pending / overdue (now)', '${summary.pendingOrOverdue}'],
      [],
      reportColumns,
      for (final report in inRange) rowFor(report),
    ];

    return rows.map((row) => row.map(escape).join(',')).join('\r\n');
  }

  /// One CSV field, quoted per RFC 4180 when it has to be, and defused
  /// when it would otherwise run as a spreadsheet formula.
  ///
  /// Report titles are typed by requestors. A title beginning `=`, `+`,
  /// `-` or `@` would execute in Excel when an administrator opened the
  /// export, so such a field gets a leading apostrophe, which spreadsheets
  /// read as "this is text".
  static String escape(String value) {
    var field = value;
    if (field.isNotEmpty && '=+-@\t\r'.contains(field[0])) field = "'$field";
    final needsQuotes =
        field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r');
    if (!needsQuotes) return field;
    return '"${field.replaceAll('"', '""')}"';
  }
}

/// Runs the export from the top bar's Export Data button.
class AnalyticsExportController {
  const AnalyticsExportController(this._ref);

  final Ref _ref;

  Future<void> export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final reports = await _latest(reportsStreamProvider);
    final workOrders = await _latest(workOrdersStreamProvider);
    final personnel = await _latest(personnelStreamProvider);

    final List<DamageReport> reportList;
    final List<WorkOrder> workOrderList;
    switch ((reports, workOrders)) {
      case (Success(value: final r), Success(value: final w)):
        reportList = r;
        workOrderList = w;
      case (Error(:final failure), _) || (_, Error(:final failure)):
        messenger.showSnackBar(_errorBar(failure.message));
        return;
    }

    final range = _ref.read(analyticsRangeProvider);
    final now = DateTime.now();
    final summary = AnalyticsSummary.compute(
      reports: reportList,
      workOrders: workOrderList,
      context: DateFilterContext(range: range, now: now),
    );
    final csv = AnalyticsExport.buildCsv(
      summary: summary,
      reports: reportList,
      workOrders: workOrderList,
      personnelNames: {
        for (final AppUser person in personnel.fold(
          (list) => list,
          (_) => const <AppUser>[],
        ))
          person.id: person.fullName,
      },
      now: now,
    );

    final name = AnalyticsExport.fileName(range, now);
    final saved = await _ref
        .read(fileDownloadServiceProvider)
        .saveText(fileName: name, contents: csv);

    saved.fold(
      (_) => messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${summary.totalReports} report'
            '${summary.totalReports == 1 ? '' : 's'} '
            '(${range.label.toLowerCase()}) to $name.',
          ),
        ),
      ),
      (failure) => messenger.showSnackBar(_errorBar(failure.message)),
    );
  }

  /// The feed's current value, waiting for its first one if the screen on
  /// show has not needed it yet — Export Data sits in the top bar of every
  /// page, not only Analytics.
  ///
  /// Listened to while waiting, not just read: Riverpod pauses a provider
  /// nobody listens to, and a paused stream never delivers the first value
  /// a bare `read(provider.future)` would wait on.
  Future<Result<T>> _latest<T>(StreamProvider<Result<T>> provider) async {
    if (_ref.read(provider) case AsyncData(:final value)) return value;
    final subscription = _ref.listen(provider, (_, _) {});
    try {
      return await _ref
          .read(provider.future)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return const Result.failure(
        UnknownFailure('The data took too long to load. Try again.'),
      );
    } on Object {
      return const Result.failure(
        UnknownFailure('The data could not be loaded for the export.'),
      );
    } finally {
      subscription.close();
    }
  }

  static SnackBar _errorBar(String message) =>
      SnackBar(content: Text(message), backgroundColor: AppColors.error);
}

final analyticsExportControllerProvider = Provider(
  AnalyticsExportController.new,
);
