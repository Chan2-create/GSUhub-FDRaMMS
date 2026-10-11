import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/feedback/data/models/service_feedback.dart';

import '../../support/fake_firestore_repositories.dart';

/// Rating the service (Objective 3.C), against the real repository over an
/// in-memory Firestore: one transaction files the rating, closes the
/// report, and records both — or writes nothing.
void main() {
  late FirestoreHarness h;
  const requestor = AuditActor(id: 'faculty-1', name: 'Maria Santos');

  setUp(() => h = FirestoreHarness());

  String? failureMessage(Result<Object?> result) =>
      result.fold((_) => null, (failure) => failure.message);

  Future<Result<void>> rate({
    String reportId = 'r1',
    AuditActor rater = requestor,
    String? comments = '  Quick and tidy.  ',
  }) => h.feedback.rate(
    reportId: reportId,
    rater: rater,
    responseTime: 4,
    serviceQuality: 5,
    overallSatisfaction: 3,
    comments: comments,
  );

  Future<void> completed() =>
      h.addReport('r1', status: ReportStatus.completed, workOrderId: 'w1');

  test('files the three ratings under the report and closes it', () async {
    await completed();

    final result = await rate();

    expect(result.isSuccess, isTrue);
    final feedback = await h.doc(FirestorePaths.feedback, 'r1');
    expect(feedback['reportId'], 'r1');
    expect(feedback['workOrderId'], 'w1');
    expect(feedback['submittedBy'], requestor.id);
    // Three ratings, kept apart (§1.5), not averaged into one.
    expect(feedback['responseTimeRating'], 4);
    expect(feedback['serviceQualityRating'], 5);
    expect(feedback['overallSatisfactionRating'], 3);
    expect(feedback['comments'], 'Quick and tidy.');
    expect(isTimestamp(feedback['submittedAt']), isTrue);

    expect(
      (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
      'closed',
    );
  });

  test('closing is on the timeline and in the audit trail', () async {
    await completed();

    await rate();

    final history = await h.history('r1');
    expect(history.map((entry) => entry['status']), ['closed']);
    expect(history.single['changedBy'], requestor.id);

    final audit = await h.auditEntries();
    expect(audit, hasLength(1));
    expect(audit.single['actorId'], requestor.id);
    expect(audit.single['changes'], {
      'from': 'completed',
      'to': 'closed',
      'feedbackId': 'r1',
    });
    // Closing tells the requestor nothing they did not just do.
    expect(await h.notifications(), isEmpty);
  });

  test('blank comments are stored as none', () async {
    await completed();

    await rate(comments: '   ');

    expect((await h.doc(FirestorePaths.feedback, 'r1'))['comments'], isNull);
  });

  test('a report that is not completed cannot be rated', () async {
    await h.addReport('r1', status: ReportStatus.inProgress, workOrderId: 'w1');

    final result = await rate();

    expect(failureMessage(result), contains('Only completed work'));
    expect(await h.count(FirestorePaths.feedback), 0);
    expect(
      (await h.doc(FirestorePaths.damageReports, 'r1'))['status'],
      'inProgress',
    );
  });

  test("someone else's report cannot be rated", () async {
    await completed();

    final result = await rate(
      rater: const AuditActor(id: 'faculty-2', name: 'Ana Gomez'),
    );

    expect(failureMessage(result), contains('Only the person who filed'));
    expect(await h.count(FirestorePaths.feedback), 0);
  });

  test(
    'a retry of a rating that went through succeeds and writes nothing',
    () async {
      await completed();
      await rate();

      final retry = await rate();

      expect(retry.isSuccess, isTrue);
      expect(await h.count(FirestorePaths.feedback), 1);
      expect(await h.history('r1'), hasLength(1));
      expect(await h.auditEntries(), hasLength(1));
    },
  );

  test('a report already rated by someone else is refused', () async {
    // Rated, but the report never closed — a state only a fault leaves.
    await completed();
    await h.firestore.collection(FirestorePaths.feedback).doc('r1').set({
      'submittedBy': 'faculty-2',
    });

    final result = await rate();

    expect(failureMessage(result), contains('already been rated'));
  });

  test('an open listener hears the rating arrive', () async {
    await completed();
    final ratings = h.feedback
        .watchForReport('r1')
        .map(
          (result) => result.fold((rating) => rating, (f) => fail(f.message)),
        );
    final heard = expectLater(
      ratings,
      emitsInOrder([
        isNull,
        isA<ServiceFeedback>().having(
          (rating) => rating.overallSatisfactionRating,
          'overall satisfaction',
          3,
        ),
      ]),
    );

    await rate();

    await heard;
  });
}
