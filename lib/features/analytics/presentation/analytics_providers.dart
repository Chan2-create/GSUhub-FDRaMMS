import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums/date_range_filter.dart';
import '../../../core/utils/result.dart';
import '../../reporting/presentation/report_providers.dart';
import '../../work_orders/presentation/work_order_providers.dart';
import 'analytics_summary.dart';

/// The period Analytics covers — the top bar's "Last 30 Days" control
/// (Figma `87:4308`). The export uses the same period, so the file matches
/// the screen.
class AnalyticsRangeController extends Notifier<DateRangeFilter> {
  @override
  DateRangeFilter build() => DateRangeFilter.last30;

  void set(DateRangeFilter range) => state = range;
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeController, DateRangeFilter>(
      AnalyticsRangeController.new,
    );

/// The Analytics figures, recomputed whenever a report, a work order or
/// the range changes.
///
/// Needs both feeds: nearly every figure crosses reports with work orders,
/// so rather than show half a screen of numbers that quietly exclude the
/// other feed, it waits for both and fails if either does.
final analyticsSummaryProvider = Provider<AsyncValue<Result<AnalyticsSummary>>>(
  (ref) {
    final range = ref.watch(analyticsRangeProvider);
    final reports = ref.watch(reportsStreamProvider);
    final workOrders = ref.watch(workOrdersStreamProvider);

    if (reports case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(error, stackTrace);
    }
    if (workOrders case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(error, stackTrace);
    }

    final reportResult = reports.value;
    final workOrderResult = workOrders.value;
    if (reportResult == null || workOrderResult == null) {
      return const AsyncLoading();
    }

    return AsyncData(
      reportResult.fold(
        (reportList) => workOrderResult.map(
          (workOrderList) => AnalyticsSummary.compute(
            reports: reportList,
            workOrders: workOrderList,
            context: DateFilterContext(range: range, now: DateTime.now()),
          ),
        ),
        Result<AnalyticsSummary>.failure,
      ),
    );
  },
);
