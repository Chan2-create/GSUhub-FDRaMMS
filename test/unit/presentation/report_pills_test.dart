import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/presentation/my_reports/widgets/report_pills.dart';

import '../../support/fake_requestor_app.dart';

/// Which damage type a requestor is shown as GSU's (Objective 3.B), and
/// how the room is read out of a report's location.
void main() {
  DamageReport classified(
    ReportStatus status, {
    String? reviewedBy = 'admin-1',
    bool automatic = true,
  }) {
    final report = fakeMyReport(
      'r1',
      status: status,
      category: DamageCategory.plumbing,
      reviewedBy: reviewedBy,
    );
    // fakeMyReport leaves classifiedAutomatically at its default; rebuild
    // with the flag this case needs.
    return DamageReport(
      id: report.id,
      reporterId: report.reporterId,
      reporterName: report.reporterName,
      title: report.title,
      description: report.description,
      requestorPriority: report.requestorPriority,
      requestorCategory: report.requestorCategory,
      status: report.status,
      category: report.category,
      classifiedAutomatically: automatic,
      reviewedBy: report.reviewedBy,
      submittedAt: report.submittedAt,
      updatedAt: report.updatedAt,
    );
  }

  group('confirmedCategoryOf', () {
    test('an unreviewed category is nobody’s decision yet', () {
      expect(
        confirmedCategoryOf(
          classified(ReportStatus.underReview, reviewedBy: null),
        ),
        isNull,
      );
    });

    test('approval makes the category GSU’s', () {
      expect(
        confirmedCategoryOf(classified(ReportStatus.approved)),
        DamageCategory.plumbing,
      );
      expect(
        confirmedCategoryOf(classified(ReportStatus.completed)),
        DamageCategory.plumbing,
      );
    });

    test('a turned-down report keeps the classifier’s guess unconfirmed', () {
      expect(confirmedCategoryOf(classified(ReportStatus.rejected)), isNull);
      expect(confirmedCategoryOf(classified(ReportStatus.merged)), isNull);
    });

    test('a category an administrator set by hand counts at any stage', () {
      expect(
        confirmedCategoryOf(
          classified(ReportStatus.underReview, automatic: false),
        ),
        DamageCategory.plumbing,
      );
    });

    test("a card falls back to the requestor's own suggestion", () {
      final report = classified(ReportStatus.underReview, reviewedBy: null);
      expect(shownCategoryOf(report), DamageCategory.electrical);
    });
  });

  group('roomOf', () {
    test('reads what follows the building', () {
      expect(
        roomOf(fakeMyReport('r1', location: 'Science Building, Room 204')),
        'Room 204',
      );
    });

    test('is null when the location is only the building', () {
      expect(roomOf(fakeMyReport('r1', location: 'Science Building')), isNull);
    });

    test('keeps free text that does not start with the building', () {
      expect(
        roomOf(fakeMyReport('r1', location: '3rd Floor, West Wing')),
        '3rd Floor, West Wing',
      );
    });
  });
}
