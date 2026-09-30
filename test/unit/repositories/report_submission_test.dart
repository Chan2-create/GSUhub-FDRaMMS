import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/services/location_service.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';

import '../../support/fake_firestore_repositories.dart';

/// Filing a report from the mobile form (Objective 3.C): one transaction
/// that writes the report and its audit entry, and that a retry cannot
/// turn into a second report.
void main() {
  late FirestoreHarness harness;

  setUp(() => harness = FirestoreHarness());

  const requestor = AuditActor(id: 'faculty-1', name: 'Maria Santos');

  ReportSubmission submission({
    AuditActor reporter = requestor,
    GeoCoordinates? coordinates = const GeoCoordinates(
      latitude: 7.2048,
      longitude: 126.5354,
      accuracyMeters: 12,
    ),
  }) => ReportSubmission(
    reporter: reporter,
    title: '  Cracked window pane ',
    description: 'The pane beside the door is cracked across. ',
    requestorPriority: PriorityLevel.high,
    requestorCategory: DamageCategory.carpentry,
    facilityId: 'fac-engineering',
    facilityName: 'Engineering Building',
    locationDescription: 'Engineering Building, Room 101',
    assetId: 'asset-aircon-01',
    coordinates: coordinates,
    photoUrls: const [
      'https://storage.test/a.jpg',
      'https://storage.test/b.jpg',
    ],
  );

  test('reserves distinct ids without writing anything', () async {
    final first = harness.reports.newReportId();
    final second = harness.reports.newReportId();

    expect(first, isNot(second));
    expect(await harness.count(FirestorePaths.damageReports), 0);
  });

  test('files the report as submitted, stamped with server time', () async {
    final id = harness.reports.newReportId();

    final result = await harness.reports.submit(
      reportId: id,
      submission: submission(),
    );

    expect(result.isSuccess, isTrue);
    final saved = await harness.doc(FirestorePaths.damageReports, id);
    expect(saved['status'], 'submitted');
    expect(saved['reporterId'], 'faculty-1');
    expect(saved['reporterName'], 'Maria Santos');
    expect(saved['title'], 'Cracked window pane', reason: 'trimmed');
    expect(saved['requestorPriority'], 'high');
    // The requestor's suggested type is kept beside the category, which
    // stays unset for the classifier or an administrator.
    expect(saved['requestorCategory'], 'carpentry');
    expect(saved['facilityId'], 'fac-engineering');
    expect(saved['assetId'], 'asset-aircon-01');
    expect(saved['photoUrls'], hasLength(2));
    expect(saved['coordinates'], const GeoPoint(7.2048, 126.5354));
    expect(isTimestamp(saved['submittedAt']), isTrue);
    expect(isTimestamp(saved['updatedAt']), isTrue);

    // Everything an administrator decides is left for them.
    for (final field in [
      'category',
      'officialPriority',
      'recommendedPriority',
      'priorityScore',
      'duplicateOf',
      'workOrderId',
      'reviewedBy',
      'reviewedAt',
      'rejectionReason',
    ]) {
      expect(saved[field], isNull, reason: field);
    }

    // And it reads back as a report the admin console can show.
    final report = await harness.reports.getById(id);
    expect(report.fold((r) => r.title, (_) => null), 'Cracked window pane');
  });

  test('stores no coordinates when the geo-tag is off', () async {
    final id = harness.reports.newReportId();

    await harness.reports.submit(
      reportId: id,
      submission: submission(coordinates: null),
    );

    final saved = await harness.doc(FirestorePaths.damageReports, id);
    expect(saved.containsKey('coordinates'), isTrue);
    expect(saved['coordinates'], isNull);
  });

  test('writes the audit entry in the same transaction', () async {
    final id = harness.reports.newReportId();

    await harness.reports.submit(reportId: id, submission: submission());

    final audit = await harness.auditEntries();
    expect(audit, hasLength(1));
    expect(audit.single['action'], 'created');
    expect(audit.single['entityType'], FirestorePaths.damageReports);
    expect(audit.single['entityId'], id);
    expect(audit.single['actorId'], 'faculty-1');
    expect(audit.single['description'], 'Submitted "Cracked window pane"');
  });

  test('a retry of the same submission files nothing twice', () async {
    // The case the transaction exists for: the first attempt reached the
    // server, the device timed out waiting, and the form tries again.
    final id = harness.reports.newReportId();
    await harness.reports.submit(reportId: id, submission: submission());

    final retry = await harness.reports.submit(
      reportId: id,
      submission: submission(),
    );

    expect(retry.isSuccess, isTrue);
    expect(await harness.count(FirestorePaths.damageReports), 1);
    expect(await harness.auditEntries(), hasLength(1));
  });

  test("refuses an id that is someone else's report", () async {
    await harness.addReport('rep-existing');

    final result = await harness.reports.submit(
      reportId: 'rep-existing',
      submission: submission(
        reporter: const AuditActor(id: 'faculty-2', name: 'Other Faculty'),
      ),
    );

    expect(result.isFailure, isTrue);
    final kept = DamageReport.fromFirestore(
      await harness.firestore
          .collection(FirestorePaths.damageReports)
          .doc('rep-existing')
          .get(),
    );
    expect(kept.reporterId, 'faculty-1', reason: 'left untouched');
  });
}
