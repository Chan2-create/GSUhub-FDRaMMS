import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/reporting/data/models/report_assessment.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository_impl.dart';

import '../../support/fake_firestore_repositories.dart';

/// The administrator's review of a report (Objectives 4.A–4.C), against
/// the real repository over an in-memory Firestore: the classification
/// and priority, the Frequency count, and the duplicate decisions.
void main() {
  late FirestoreHarness h;
  const admin = FirestoreHarness.admin;

  setUp(() => h = FirestoreHarness());

  String? failureMessage(Result<Object?> result) =>
      result.fold((_) => null, (failure) => failure.message);

  Future<Map<String, dynamic>> report(String id) =>
      h.doc(FirestorePaths.damageReports, id);

  Future<void> setFields(String id, Map<String, Object?> fields) => h.firestore
      .collection(FirestorePaths.damageReports)
      .doc(id)
      .update(fields);

  ReportAssessment assessment({
    DamageCategory category = DamageCategory.plumbing,
    bool automatic = false,
    PriorityLevel official = PriorityLevel.critical,
  }) => ReportAssessment(
    category: category,
    classifiedAutomatically: automatic,
    severityRating: 4,
    safetyRiskRating: 4,
    frequencyRating: 2,
    locationImportanceRating: 3,
    priorityScore: 3.50,
    recommendedPriority: PriorityLevel.critical,
    officialPriority: official,
  );

  group('recordAssessment', () {
    test('stores the type, the ratings, the score and both levels', () async {
      await h.addReport(
        'r1',
        status: ReportStatus.underReview,
        category: null,
        officialPriority: null,
      );

      final result = await h.reports.recordAssessment(
        reportId: 'r1',
        assessment: assessment(),
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final saved = await report('r1');
      expect(saved['category'], 'plumbing');
      expect(saved['classifiedAutomatically'], isFalse);
      expect(saved['severityRating'], 4);
      expect(saved['safetyRiskRating'], 4);
      expect(saved['frequencyRating'], 2);
      expect(saved['locationImportanceRating'], 3);
      expect(saved['priorityScore'], 3.50);
      expect(saved['recommendedPriority'], 'critical');
      expect(saved['officialPriority'], 'critical');
      expect(saved['reviewedBy'], admin.id);
      expect(isTimestamp(saved['reviewedAt']), isTrue);
      // A review decision, not a status move: the timeline is untouched.
      expect(saved['status'], 'underReview');
      expect(await h.history('r1'), isEmpty);
    });

    test('audits it, saying when the level departs from the score', () async {
      await h.addReport(
        'r1',
        status: ReportStatus.underReview,
        officialPriority: null,
      );

      await h.reports.recordAssessment(
        reportId: 'r1',
        assessment: assessment(official: PriorityLevel.high),
        actor: admin,
      );

      final audit = (await h.auditEntries()).single;
      expect(audit['action'], 'updated');
      expect(audit['entityType'], FirestorePaths.damageReports);
      expect(audit['entityId'], 'r1');
      expect(audit['actorId'], admin.id);
      expect(
        audit['description'],
        'Classified as Plumbing; official priority HIGH, lowered from the '
        'recommended CRITICAL (score 3.50)',
      );
      final changes = audit['changes'] as Map<String, dynamic>;
      expect(changes['category'], {'from': 'electrical', 'to': 'plumbing'});
      expect(changes['officialPriority'], {'from': null, 'to': 'high'});
      expect(changes['ratings'], {
        'severity': 4,
        'safetyRisk': 4,
        'frequency': 2,
        'locationImportance': 3,
      });
    });

    test('describes a confirmed recommendation as confirmed', () {
      expect(
        DamageReportRepositoryImpl.describeAssessment(assessment()),
        'Classified as Plumbing; official priority CRITICAL as recommended '
        '(score 3.50)',
      );
      expect(
        DamageReportRepositoryImpl.describeAssessment(
          ReportAssessment(
            category: DamageCategory.electrical,
            classifiedAutomatically: true,
            severityRating: 2,
            safetyRiskRating: 2,
            frequencyRating: 1,
            locationImportanceRating: 3,
            priorityScore: 1.90,
            recommendedPriority: PriorityLevel.medium,
            officialPriority: PriorityLevel.critical,
          ),
        ),
        'Classified as Electrical; official priority CRITICAL, raised from '
        'the recommended MEDIUM (score 1.90)',
      );
    });

    test('may be revised until the work is assigned', () async {
      // Approved, electrical, official HIGH.
      await h.addReport('r1');

      final result = await h.reports.recordAssessment(
        reportId: 'r1',
        assessment: assessment(),
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      expect((await report('r1'))['officialPriority'], 'critical');
    });

    test('is refused once a work order is raised', () async {
      await h.addReport(
        'r1',
        status: ReportStatus.assigned,
        workOrderId: 'wo-1',
      );

      final result = await h.reports.recordAssessment(
        reportId: 'r1',
        assessment: assessment(),
        actor: admin,
      );

      expect(failureMessage(result), contains('cannot change now'));
      expect((await report('r1'))['officialPriority'], 'high');
      expect(await h.auditEntries(), isEmpty);
    });

    test('is refused on a report merged into another', () async {
      await h.addReport('r1', status: ReportStatus.merged);
      await setFields('r1', {'duplicateOf': 'parent'});

      final result = await h.reports.recordAssessment(
        reportId: 'r1',
        assessment: assessment(),
        actor: admin,
      );

      expect(failureMessage(result), contains('merged into another'));
      expect(await h.auditEntries(), isEmpty);
    });

    test('is refused for a report that does not exist', () async {
      final result = await h.reports.recordAssessment(
        reportId: 'missing',
        assessment: assessment(),
        actor: admin,
      );

      expect(result.isSuccess, isFalse);
      expect(await h.auditEntries(), isEmpty);
    });
  });

  test('countSimilarReports counts one damage type at one facility since '
      'a date (4.B)', () async {
    await h.addReport('in-1', submittedAt: DateTime.utc(2026, 10));
    await h.addReport('in-2', submittedAt: DateTime.utc(2026, 10, 10));
    await h.addReport('too-old', submittedAt: DateTime.utc(2026, 8));
    await h.addReport(
      'other-type',
      category: DamageCategory.plumbing,
      submittedAt: DateTime.utc(2026, 10, 5),
    );
    await h.addReport('elsewhere', submittedAt: DateTime.utc(2026, 10, 5));
    await setFields('elsewhere', {'facilityId': 'fac-library'});

    final result = await h.reports.countSimilarReports(
      facilityId: 'fac-engineering',
      category: DamageCategory.electrical,
      since: DateTime.utc(2026, 9, 12),
    );

    expect(result.fold((count) => count, (f) => fail(f.message)), 2);
  });

  group('mergeDuplicates (4.C)', () {
    test('merges a report still awaiting its first review', () async {
      // New in 4.C: a duplicate is often spotted the moment it arrives.
      await h.addReport('parent', status: ReportStatus.underReview);
      await h.addReport('dup', status: ReportStatus.submitted);

      final result = await h.reports.mergeDuplicates(
        parentReportId: 'parent',
        duplicateReportIds: ['dup'],
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final merged = await report('dup');
      expect(merged['status'], 'merged');
      expect(merged['duplicateOf'], 'parent');
      expect(merged['reviewedBy'], admin.id);

      final audit = (await h.auditEntries()).single;
      expect(audit['action'], 'merged');
      expect(audit['entityId'], 'dup');
      expect(audit['description'], 'Merged into #DR-PARENT as a duplicate');
      expect(audit['changes'], {
        'from': 'submitted',
        'to': 'merged',
        'parent': 'parent',
      });
    });

    test('refuses to merge a report that is past review', () async {
      await h.addReport('parent', status: ReportStatus.underReview);
      await h.addReport('dup');

      final result = await h.reports.mergeDuplicates(
        parentReportId: 'parent',
        duplicateReportIds: ['dup'],
        actor: admin,
      );

      expect(failureMessage(result), contains('#DR-DUP is APPROVED'));
      expect((await report('dup'))['status'], 'approved');
      expect(await h.auditEntries(), isEmpty);
    });

    test('refuses a parent that is closed or itself merged', () async {
      await h.addReport('closed', status: ReportStatus.closed);
      await h.addReport('merged', status: ReportStatus.merged);
      await setFields('merged', {'duplicateOf': 'elsewhere'});
      await h.addReport('dup', status: ReportStatus.underReview);

      for (final parent in ['closed', 'merged']) {
        final result = await h.reports.mergeDuplicates(
          parentReportId: parent,
          duplicateReportIds: ['dup'],
          actor: admin,
        );
        expect(
          failureMessage(result),
          contains('no report can be merged into it'),
          reason: parent,
        );
      }
      expect((await report('dup'))['status'], 'underReview');
    });

    test('refuses an empty list, and a report merged into itself', () async {
      await h.addReport('parent', status: ReportStatus.underReview);

      expect(
        failureMessage(
          await h.reports.mergeDuplicates(
            parentReportId: 'parent',
            duplicateReportIds: [],
            actor: admin,
          ),
        ),
        'Choose the reports to merge.',
      );
      expect(
        failureMessage(
          await h.reports.mergeDuplicates(
            parentReportId: 'parent',
            duplicateReportIds: ['parent'],
            actor: admin,
          ),
        ),
        'A report cannot be merged into itself.',
      );
    });
  });

  group('keepSeparate (4.C)', () {
    test('records the ruling on both reports, and audits it', () async {
      await h.addReport('a', status: ReportStatus.submitted);
      await h.addReport('b', status: ReportStatus.underReview);

      final result = await h.reports.keepSeparate(
        reportId: 'a',
        otherReportId: 'b',
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      expect((await report('a'))['dismissedDuplicateIds'], ['b']);
      expect((await report('b'))['dismissedDuplicateIds'], ['a']);
      // Neither report moves.
      expect((await report('a'))['status'], 'submitted');

      final audit = (await h.auditEntries()).single;
      expect(audit['action'], 'updated');
      expect(audit['description'], 'Kept separate from #DR-B: not a duplicate');
    });

    test('adds to earlier rulings rather than replacing them', () async {
      await h.addReport('a', status: ReportStatus.submitted);
      await h.addReport('b', status: ReportStatus.submitted);
      await h.addReport('c', status: ReportStatus.submitted);

      for (final other in ['b', 'c', 'b']) {
        await h.reports.keepSeparate(
          reportId: 'a',
          otherReportId: other,
          actor: admin,
        );
      }

      expect((await report('a'))['dismissedDuplicateIds'], ['b', 'c']);
    });

    test('refuses a report compared with itself, or a missing one', () async {
      await h.addReport('a', status: ReportStatus.submitted);

      expect(
        failureMessage(
          await h.reports.keepSeparate(
            reportId: 'a',
            otherReportId: 'a',
            actor: admin,
          ),
        ),
        'A report cannot be compared with itself.',
      );
      expect(
        (await h.reports.keepSeparate(
          reportId: 'a',
          otherReportId: 'missing',
          actor: admin,
        )).isSuccess,
        isFalse,
      );
      expect((await report('a'))['dismissedDuplicateIds'], isEmpty);
    });
  });
}
