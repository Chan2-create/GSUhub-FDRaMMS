import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../data/models/damage_report.dart';
import '../report_providers.dart';

/// What the Map View has to draw: the reports that carry a geo-tag, and
/// how many do not.
///
/// The geo-tag is supplementary (manuscript §1.5, §2 "Geo-Tagging and
/// Location-Based Reporting"): a report is complete without one, so the
/// reports left off the map are counted rather than hidden silently.
class ReportMapData {
  const ReportMapData({required this.located, required this.withoutGeoTag});

  /// Splits [reports] for the map. Archived reports are out of the
  /// console's lists and stay off the map too; finished and discarded
  /// ones join only when [includeFinished] is set.
  factory ReportMapData.from(
    List<DamageReport> reports, {
    required bool includeFinished,
  }) {
    final located = <DamageReport>[];
    var withoutGeoTag = 0;
    for (final report in reports) {
      if (report.isArchived) continue;
      if (!includeFinished && !report.status.isOpen) continue;
      if (report.coordinates == null) {
        withoutGeoTag++;
      } else {
        located.add(report);
      }
    }
    located.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return ReportMapData(
      located: List.unmodifiable(located),
      withoutGeoTag: withoutGeoTag,
    );
  }

  /// Reports with a geo-tag, newest first.
  final List<DamageReport> located;

  /// Reports in the same scope that were filed without a geo-tag.
  final int withoutGeoTag;
}

/// Whether the map also shows reports that are finished or discarded.
/// Off by default: the geo-tag is there "for verification and response"
/// (manuscript §2), and those are the open reports.
class MapFinishedController extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: avoid_positional_boolean_parameters, a FilterChip's callback
  void set(bool includeFinished) => state = includeFinished;
}

final mapIncludesFinishedProvider =
    NotifierProvider<MapFinishedController, bool>(MapFinishedController.new);

/// The report whose pin is selected, by id; null when none is.
class MapSelectionController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? reportId) => state = reportId;
}

final selectedMapReportProvider =
    NotifierProvider<MapSelectionController, String?>(
      MapSelectionController.new,
    );

/// The open reports only, whatever the Map View's filter says: the
/// Damage Reports page's "Campus View" preview.
final openReportMapProvider = Provider<AsyncValue<Result<ReportMapData>>>(
  (ref) => ref
      .watch(reportsStreamProvider)
      .whenData(
        (result) => result.map(
          (reports) => ReportMapData.from(reports, includeFinished: false),
        ),
      ),
);

/// The Map View's reports, live from the same feed as the reports table.
final reportMapProvider = Provider<AsyncValue<Result<ReportMapData>>>((ref) {
  final includeFinished = ref.watch(mapIncludesFinishedProvider);
  return ref
      .watch(reportsStreamProvider)
      .whenData(
        (result) => result.map(
          (reports) =>
              ReportMapData.from(reports, includeFinished: includeFinished),
        ),
      );
});
