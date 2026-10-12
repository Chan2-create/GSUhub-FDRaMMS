import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/features/classification/data/models/duplicate_detection_config.dart';
import 'package:gsuhub/features/classification/domain/duplicate_detector.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';

/// Duplicate report detection (manuscript §3.4; Objective 4.C).
void main() {
  final now = DateTime.utc(2026, 10, 12, 9);
  final config = DuplicateDetectionConfig.defaults(
    updatedAt: now,
    updatedBy: 'admin-1',
  );
  final detector = DuplicateDetector(config);

  DamageReport report(
    String id, {
    String title = 'Flickering lights',
    String description = 'The lights flicker all day.',
    DamageCategory? category = DamageCategory.electrical,
    String? facilityId = 'fac-engineering',
    String? facilityName = 'Engineering Building',
    String? location = 'Room 101',
    ReportStatus status = ReportStatus.submitted,
    Duration filedAgo = Duration.zero,
    String? duplicateOf,
    String? workOrderId,
    List<String> keptSeparateFrom = const [],
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: title,
    description: description,
    category: category,
    facilityId: facilityId,
    facilityName: facilityName,
    locationDescription: location,
    requestorPriority: PriorityLevel.medium,
    status: status,
    duplicateOf: duplicateOf,
    workOrderId: workOrderId,
    dismissedDuplicateIds: keptSeparateFrom,
    submittedAt: now.subtract(filedAgo),
    updatedAt: now,
  );

  List<String> flaggedAgainst(
    DamageReport subject,
    List<DamageReport> others,
  ) => [
    for (final candidate in detector.candidatesFor(subject, others))
      candidate.report.id,
  ];

  /// Different words for a different problem, of another type.
  DamageReport unrelated(String id, {Duration filedAgo = Duration.zero}) =>
      report(
        id,
        title: 'Clogged drain',
        description: 'Water will not go down the sink.',
        category: DamageCategory.plumbing,
        filedAgo: filedAgo,
      );

  group('flags', () {
    test('two open reports of one damage type, at one facility, close '
        'together', () {
      final first = report('a', filedAgo: const Duration(hours: 5));
      final second = report(
        'b',
        title: 'No power in the room',
        description: 'Nothing switches on.',
      );

      final candidates = detector.candidatesFor(second, [first]);

      expect(candidates, hasLength(1));
      expect(candidates.single.report.id, 'a');
      expect(candidates.single.sameCategory, isTrue);
      expect(candidates.single.apart, const Duration(hours: 5));
    });

    test('reports of different types whose wording is alike', () {
      // One unclassified: the wording carries it.
      final first = report(
        'a',
        title: 'Water leaking from the ceiling',
        description: 'Leaks onto the desks.',
        category: DamageCategory.plumbing,
      );
      final second = report(
        'b',
        title: 'Ceiling leaks water',
        description: 'Desks are wet.',
        category: null,
      );

      final candidates = detector.candidatesFor(second, [first]);

      expect(candidates.single.sameCategory, isFalse);
      expect(
        candidates.single.similarity,
        greaterThanOrEqualTo(config.descriptionSimilarityThreshold),
      );
    });

    test('a report with no facility, at the same stated location', () {
      final first = report(
        'a',
        facilityId: null,
        location: 'Science Building, Laboratory 3',
      );
      final second = report(
        'b',
        facilityId: null,
        location: 'science building — laboratory 3',
      );

      expect(flaggedAgainst(second, [first]), ['a']);
    });

    test('up to the end of the time window, and not beyond', () {
      final subject = report('s');

      expect(
        flaggedAgainst(subject, [report('in', filedAgo: config.timeWindow)]),
        ['in'],
      );
      expect(
        flaggedAgainst(subject, [
          report('out', filedAgo: config.timeWindow + const Duration(hours: 1)),
        ]),
        isEmpty,
      );
    });

    test('most alike first, then nearest in time', () {
      final subject = report('s');
      final candidates = detector.candidatesFor(subject, [
        report('far-same-words', filedAgo: const Duration(hours: 30)),
        report(
          'other-words',
          title: 'Lamp broken',
          description: 'No light at the front.',
          filedAgo: const Duration(hours: 1),
        ),
        report('near-same-words', filedAgo: const Duration(hours: 2)),
      ]);

      expect(candidates.map((c) => c.report.id), [
        'near-same-words',
        'far-same-words',
        'other-words',
      ]);
    });

    test('flagsFor marks both reports of a pair, in one pass', () {
      final flags = detector.flagsFor([
        report('a'),
        report('b', filedAgo: const Duration(hours: 3)),
        report('elsewhere', facilityId: 'fac-library', location: 'Lobby'),
      ]);

      expect(flags.keys, unorderedEquals(['a', 'b']));
      expect(flags['a']!.single.report.id, 'b');
      expect(flags['b']!.single.report.id, 'a');
    });
  });

  group('does not flag', () {
    test('different damage with different wording at the same place', () {
      expect(flaggedAgainst(report('a'), [unrelated('b')]), isEmpty);
    });

    test('the same damage at another place', () {
      final other = report(
        'b',
        facilityId: 'fac-library',
        facilityName: 'Library',
        location: 'Reading Area',
      );

      expect(flaggedAgainst(report('a'), [other]), isEmpty);
    });

    test('reports that are finished, discarded or already merged', () {
      final subject = report('s');

      for (final status in [
        ReportStatus.completed,
        ReportStatus.closed,
        ReportStatus.rejected,
        ReportStatus.archived,
      ]) {
        expect(
          flaggedAgainst(subject, [report('x', status: status)]),
          isEmpty,
          reason: '$status was flagged',
        );
      }
      expect(
        flaggedAgainst(subject, [
          report('m', status: ReportStatus.merged, duplicateOf: 'p'),
        ]),
        isEmpty,
      );
      // Nor is a closed report given candidates of its own.
      expect(
        detector.candidatesFor(report('c', status: ReportStatus.closed), [
          report('x'),
        ]),
        isEmpty,
      );
    });

    test('a pair an administrator kept separate, from either side', () {
      expect(
        flaggedAgainst(report('a', keptSeparateFrom: ['b']), [report('b')]),
        isEmpty,
      );
      expect(
        flaggedAgainst(report('a'), [
          report('b', keptSeparateFrom: ['a']),
        ]),
        isEmpty,
      );
    });

    test('different types that share a single word', () {
      // {broken, window} and {broken, light} are half alike, and two jobs.
      // (The room is the place, compared on its own, not wording.)
      final window = report(
        'window',
        title: 'Broken window',
        description: 'Room 101.',
        category: DamageCategory.carpentry,
      );
      final light = report(
        'light',
        title: 'Broken light',
        description: 'Room 101.',
      );

      expect(
        DuplicateDetector.similarity('Broken window', 'Broken light'),
        0.5,
      );
      expect(flaggedAgainst(window, [light]), isEmpty);
    });

    test('two problems in one room, just because both name the room', () {
      // Without the place's own words set aside, "room" and "101" alone
      // would make these two-thirds alike.
      final chair = report(
        'chair',
        title: 'Broken chair',
        description: 'Room 101.',
        category: DamageCategory.carpentry,
      );
      final aircon = report(
        'aircon',
        title: 'Aircon',
        description: 'Room 101 aircon.',
        category: DamageCategory.airConditioning,
      );

      expect(flaggedAgainst(chair, [aircon]), isEmpty);
    });

    test('anything, when detection is turned off', () {
      final off = DuplicateDetector(config.copyWith(enabled: false));

      expect(off.candidatesFor(report('a'), [report('b')]), isEmpty);
      expect(off.flagsFor([report('a'), report('b')]), isEmpty);
    });
  });

  group('wording', () {
    test('leaks, leaking and leaked count as one word', () {
      expect(DuplicateDetector.keyWords('leaks leaking leaked'), {'leak'});
    });

    test('common and short words are left out, numbers kept', () {
      expect(DuplicateDetector.keyWords('The CR on the 2nd floor is dirty'), {
        '2nd',
        'floor',
        'dirty',
      });
    });

    test("similarity is the share of the shorter text's key words shared", () {
      // {pipe, burst} against {pipe, burst, kitchen, sink}: both of the
      // shorter one's words.
      expect(
        DuplicateDetector.similarity(
          'Burst pipe',
          'The pipe burst under the kitchen sink',
        ),
        1.0,
      );
      expect(DuplicateDetector.similarity('Burst pipe', 'Broken door'), 0.0);
      expect(DuplicateDetector.similarity('', 'Broken door'), 0.0);
    });
  });

  group('mergePlanFor', () {
    test('keeps the earlier report when both await review', () {
      final earlier = report('a', filedAgo: const Duration(hours: 4));
      final later = report('b');

      for (final plan in [
        DuplicateDetector.mergePlanFor(earlier, later)!,
        DuplicateDetector.mergePlanFor(later, earlier)!,
      ]) {
        expect(plan.parent.id, 'a');
        expect(plan.duplicate.id, 'b');
      }
    });

    test('keeps the report already approved, whichever came first', () {
      final approved = report('a', status: ReportStatus.approved);
      final waiting = report(
        'b',
        status: ReportStatus.underReview,
        filedAgo: const Duration(hours: 4),
      );

      final plan = DuplicateDetector.mergePlanFor(waiting, approved)!;

      expect(plan.parent.id, 'a');
      expect(plan.duplicate.id, 'b');
    });

    test('has no plan when neither can be closed as a duplicate', () {
      expect(
        DuplicateDetector.mergePlanFor(
          report('a', status: ReportStatus.approved),
          report('b', status: ReportStatus.assigned, workOrderId: 'wo-1'),
        ),
        isNull,
      );
    });

    test('a report with a work order is never the one closed', () {
      expect(
        DuplicateDetector.canBeMerged(report('a', workOrderId: 'wo-1')),
        isFalse,
      );
      expect(DuplicateDetector.canBeMerged(report('a')), isTrue);
      expect(
        DuplicateDetector.canBeMerged(
          report('a', status: ReportStatus.underReview),
        ),
        isTrue,
      );
    });
  });
}
