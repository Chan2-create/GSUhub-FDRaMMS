import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/core/widgets/stat_card.dart';
import 'package:gsuhub/features/dashboard/presentation/dashboard_screen.dart';

import '../support/fake_admin_backend.dart';

/// Dashboard states (Objective 2.A).
///
/// The standing UI rule is that every data-backed element shows loading,
/// empty and error states, and the seeded-versus-bare database is exactly
/// where that gets tested by hand and forgotten. These pin it down.
void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    bool failing = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      fakeAdminScope(
        reports: failing
            ? const Result.failure(NetworkFailure('Cannot reach the server.'))
            : const Result.success([]),
        activity: failing
            ? const Result.failure(NetworkFailure('Cannot reach the server.'))
            : const Result.success([]),
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('empty database', () {
    testWidgets('renders empty states rather than looking broken', (
      tester,
    ) async {
      await pumpDashboard(tester);

      expect(
        find.text('No damage reports have been submitted yet.'),
        findsOneWidget,
      );
      expect(find.text('No reports to categorize yet.'), findsOneWidget);
      expect(find.text('No recorded activity yet.'), findsOneWidget);
      expect(
        find.text('No reports recorded this month or last.'),
        findsOneWidget,
      );
    });

    testWidgets('stat cards read zero, not a dash', (tester) async {
      await pumpDashboard(tester);

      // Zero reports is a fact about the database. A dash would say "we
      // could not read this", which is a different claim.
      final cards = tester.widgetList<StatCard>(find.byType(StatCard));
      expect(cards, hasLength(4));
      for (final card in cards) {
        expect(card.value, 0, reason: '${card.label} did not read zero');
        expect(card.hasError, isFalse);
      }
    });
  });

  group('backend failure', () {
    testWidgets('surfaces the failure instead of showing zeroes', (
      tester,
    ) async {
      await pumpDashboard(tester, failing: true);

      final cards = tester.widgetList<StatCard>(find.byType(StatCard));
      for (final card in cards) {
        expect(card.hasError, isTrue, reason: '${card.label} hid the error');
        expect(card.value, isNull);
      }
    });

    testWidgets('offers a retry on the failed panels', (tester) async {
      await pumpDashboard(tester, failing: true);

      expect(find.text('Try again'), findsWidgets);
      expect(find.textContaining('Cannot reach the server.'), findsWidgets);
    });
  });
}
