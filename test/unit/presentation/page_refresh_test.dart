import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/data/live_sync.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/audit/data/repositories/audit_log_repository.dart';
import 'package:gsuhub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:gsuhub/shells/page_refresh.dart';

import '../../support/fake_live_sync.dart';

/// The audit log the dashboard's recent activity reads once, counting
/// its reads.
class _CountingAuditLog implements AuditLogRepository {
  int queries = 0;
  Result<List<AuditLogEntry>> answer = const Result.success([]);

  @override
  Future<Result<List<AuditLogEntry>>> query({
    AuditAction? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    queries++;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The refresh a navigation button starts on its own page (2026-11-25).
void main() {
  late LiveSync sync;
  late _CountingAuditLog audit;
  late ProviderContainer container;
  var reads = 0;
  Object? failure;

  /// Runs [body] with a fresh LiveSync and container, let go of inside
  /// the test, before its timers are checked (as in live_sync_test.dart).
  void refreshTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        reads = 0;
        failure = null;
        sync = LiveSync(openChannel: openFakeChangeChannel);
        audit = _CountingAuditLog();
        container = ProviderContainer(
          overrides: [
            liveSyncProvider.overrideWithValue(sync),
            auditLogRepositoryProvider.overrideWithValue(audit),
          ],
        );
        try {
          await body(tester);
        } finally {
          container.dispose();
          sync.dispose();
        }
      });

  /// A live view on screen, as a page would watch it.
  void watchOne() => sync
      .watchRows(
        tables: {'damage_reports'},
        fetch: () async {
          reads++;
          final failed = failure;
          if (failed != null) throw failed;
          return const [];
        },
      )
      .listen((_) {}, onError: (_) {});

  PageRefreshController controller() =>
      container.read(pageRefreshProvider.notifier);

  refreshTest('reads the page again, busy meanwhile, at least a moment', (
    tester,
  ) async {
    watchOne();
    await tester.pump();
    final before = reads;

    final done = controller().refresh();
    await tester.pump();
    expect(container.read(pageRefreshProvider).busy, isTrue);

    await tester.pump(PageRefreshController.minimumShown);
    expect(await done, isTrue);
    expect(reads, before + 1);
    expect(container.read(pageRefreshProvider).busy, isFalse);
    expect(container.read(pageRefreshProvider).failures, 0);
  });

  refreshTest('pressed again meanwhile, it is the same refresh', (
    tester,
  ) async {
    watchOne();
    await tester.pump();
    final before = reads;

    final first = controller().refresh();
    final second = controller().refresh();
    final third = controller().refresh();
    expect(identical(first, second), isTrue);
    expect(identical(first, third), isTrue);
    await tester.pump(PageRefreshController.minimumShown);
    await first;
    expect(reads, before + 1, reason: 'one read, not three');

    // Once it is over, the next press is a refresh of its own.
    final fourth = controller().refresh();
    expect(identical(first, fourth), isFalse);
    await tester.pump(PageRefreshController.minimumShown);
    await fourth;
  });

  refreshTest('a failed read counts as a failed refresh', (tester) async {
    watchOne();
    await tester.pump();

    failure = const NetworkFailure('Cannot reach the server.');
    final done = controller().refresh();
    await tester.pump(PageRefreshController.minimumShown);
    expect(await done, isFalse);
    expect(container.read(pageRefreshProvider).failures, 1);
    expect(container.read(pageRefreshProvider).busy, isFalse);
  });

  refreshTest("the dashboard's recent activity, read once, is read again "
      'when it is on screen', (tester) async {
    container.listen(recentActivityProvider, (_, _) {});
    await container.read(recentActivityProvider.future);
    expect(audit.queries, 1);

    final done = controller().refresh();
    await tester.pump(PageRefreshController.minimumShown);
    expect(await done, isTrue);
    expect(audit.queries, 2);

    // And its failure is the refresh's.
    audit.answer = const Result.failure(NetworkFailure('offline'));
    final again = controller().refresh();
    await tester.pump(PageRefreshController.minimumShown);
    expect(await again, isFalse);
  });

  refreshTest('a view read once that is not on screen is not read', (
    tester,
  ) async {
    final done = controller().refresh();
    await tester.pump(PageRefreshController.minimumShown);
    expect(await done, isTrue);
    expect(audit.queries, 0);
  });
}
