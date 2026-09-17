import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/report_status.dart';

void main() {
  group('ReportStatus transitions', () {
    test('forward happy path is allowed step by step', () {
      const path = [
        ReportStatus.submitted,
        ReportStatus.underReview,
        ReportStatus.approved,
        ReportStatus.assigned,
        ReportStatus.inProgress,
        ReportStatus.forReview,
        ReportStatus.completed,
        ReportStatus.closed,
      ];
      for (var i = 0; i < path.length - 1; i++) {
        expect(
          path[i].canTransitionTo(path[i + 1]),
          isTrue,
          reason: '${path[i]} -> ${path[i + 1]} should be allowed',
        );
      }
    });

    test('underReview may branch to merged, rejected, or archived', () {
      expect(
        ReportStatus.underReview.canTransitionTo(ReportStatus.merged),
        isTrue,
      );
      expect(
        ReportStatus.underReview.canTransitionTo(ReportStatus.rejected),
        isTrue,
      );
      expect(
        ReportStatus.underReview.canTransitionTo(ReportStatus.archived),
        isTrue,
      );
    });

    test('cannot skip stages', () {
      expect(
        ReportStatus.submitted.canTransitionTo(ReportStatus.assigned),
        isFalse,
      );
    });

    test('terminal statuses accept no further transitions', () {
      for (final status in [
        ReportStatus.closed,
        ReportStatus.merged,
        ReportStatus.rejected,
        ReportStatus.archived,
      ]) {
        expect(status.isTerminal, isTrue);
        for (final other in ReportStatus.values) {
          expect(status.canTransitionTo(other), isFalse);
        }
      }
    });

    test('id round-trips through fromId', () {
      for (final status in ReportStatus.values) {
        expect(ReportStatus.fromId(status.id), status);
      }
    });

    test('fromId throws on unknown value', () {
      expect(() => ReportStatus.fromId('not_a_status'), throwsArgumentError);
    });
  });
}
