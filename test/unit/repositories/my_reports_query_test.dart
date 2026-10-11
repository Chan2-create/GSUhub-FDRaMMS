import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository.dart';

import '../../support/fake_firestore_repositories.dart';

/// The requestor's own-report query (Objectives 3.A and 3.B) against the real
/// repository over fake_cloud_firestore: their reports only, newest first,
/// and never more than the rules allow a requestor to ask for.
void main() {
  late FirestoreHarness harness;

  setUp(() => harness = FirestoreHarness());

  List<String> idsOf(Result<List<DamageReport>> result) => result.fold(
    (reports) => [for (final report in reports) report.id],
    (failure) => fail('expected reports, got $failure'),
  );

  test("returns the requestor's own reports, newest first", () async {
    await harness.addReport('older', submittedAt: DateTime.utc(2026, 9, 3));
    await harness.addReport('newer', submittedAt: DateTime.utc(2026, 9, 20));
    await harness.addReport(
      'someone-else',
      reporterId: 'faculty-2',
      submittedAt: DateTime.utc(2026, 9, 25),
    );

    final result = await harness.reports.watchByReporter('faculty-1').first;

    expect(idsOf(result), ['newer', 'older']);
  });

  test('stops at the limit the security rules allow', () async {
    const limit = DamageReportRepository.reporterQueryLimit;
    for (var i = 0; i < limit + 5; i++) {
      await harness.addReport(
        'r$i',
        submittedAt: DateTime.utc(2026).add(Duration(hours: i)),
      );
    }

    final result = await harness.reports.watchByReporter('faculty-1').first;

    expect(idsOf(result), hasLength(limit));
    // The newest are the ones kept.
    expect(idsOf(result).first, 'r${limit + 4}');
  });
}
