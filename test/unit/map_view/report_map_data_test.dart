import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/data/geo_coordinates.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/map_view/presentation/report_map.dart';
import 'package:gsuhub/features/map_view/presentation/report_map_providers.dart';

/// Which reports the Map View draws (2026-11-12). The geo-tag is
/// supplementary (manuscript §1.5, §2), so a report without one is
/// counted, never dropped silently.
void main() {
  const point = GeoCoordinates(latitude: 7.2048, longitude: 126.5354);

  DamageReport report(
    String id, {
    ReportStatus status = ReportStatus.approved,
    GeoCoordinates? coordinates = point,
    DateTime? archivedAt,
    DateTime? submittedAt,
    String? facilityName = 'Engineering Building',
    String? locationDescription,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: 'Flickering lights',
    description: 'Lights flicker.',
    requestorPriority: PriorityLevel.high,
    status: status,
    facilityName: facilityName,
    locationDescription: locationDescription,
    coordinates: coordinates,
    archivedAt: archivedAt,
    submittedAt: submittedAt ?? DateTime.utc(2026, 11),
    updatedAt: DateTime.utc(2026, 11),
  );

  List<String> ids(ReportMapData data) => [
    for (final located in data.located) located.id,
  ];

  group('ReportMapData.from', () {
    test('keeps the open geo-tagged reports, newest first', () {
      final data = ReportMapData.from([
        report('older', submittedAt: DateTime.utc(2026, 11, 2)),
        report('newer', submittedAt: DateTime.utc(2026, 11, 5)),
      ], includeFinished: false);

      expect(ids(data), ['newer', 'older']);
      expect(data.withoutGeoTag, 0);
    });

    test('counts a report without a geo-tag instead of drawing it', () {
      final data = ReportMapData.from([
        report('tagged'),
        report('untagged', coordinates: null),
      ], includeFinished: false);

      expect(ids(data), ['tagged']);
      expect(data.withoutGeoTag, 1);
    });

    test('leaves finished and discarded reports out unless asked', () {
      final reports = [
        for (final status in ReportStatus.values)
          report(status.name, status: status),
      ];

      final open = ReportMapData.from(reports, includeFinished: false);
      expect(ids(open).toSet(), {
        for (final status in ReportStatus.values)
          if (status.isOpen) status.name,
      });

      final all = ReportMapData.from(reports, includeFinished: true);
      expect(all.located, hasLength(ReportStatus.values.length));
    });

    test('an untagged finished report is not counted among the open', () {
      final data = ReportMapData.from([
        report('closed', status: ReportStatus.closed, coordinates: null),
      ], includeFinished: false);

      expect(data.located, isEmpty);
      expect(data.withoutGeoTag, 0);
    });

    test('never shows an archived report', () {
      final data = ReportMapData.from([
        report(
          'archived',
          status: ReportStatus.closed,
          archivedAt: DateTime.utc(2026, 11, 8),
        ),
      ], includeFinished: true);

      expect(data.located, isEmpty);
      expect(data.withoutGeoTag, 0);
    });
  });

  group('placeOf', () {
    test('reads the facility with the requestor\'s own words', () {
      expect(
        placeOf(report('r', locationDescription: 'Room 302, by the door')),
        'Engineering Building · Room 302, by the door',
      );
    });

    test('does not say the same thing twice', () {
      expect(
        placeOf(report('r', locationDescription: 'Engineering Building')),
        'Engineering Building',
      );
    });

    test('says so when the report gives neither', () {
      expect(
        placeOf(report('r', facilityName: null)),
        'No location details given',
      );
    });
  });
}
