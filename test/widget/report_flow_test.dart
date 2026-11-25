import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/core/constants/app_colors.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/core/widgets/working_day_picker.dart';
import 'package:gsuhub/features/damage_reports/data/models/damage_report.dart';
import 'package:gsuhub/features/damage_reports/presentation/report_detail_screen.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../support/fake_admin_backend.dart';

/// A report handled from start to finish on its own page (2026-11-26, the
/// adviser's consultation): Start review shows Under Review at once,
/// Approve waits for the confirmed type and priority, and an approved
/// report is assigned, to its trade only, or rescheduled, right there.
void main() {
  final now = DateTime.now();

  DamageReport report({
    ReportStatus status = ReportStatus.submitted,
    DamageCategory? category = DamageCategory.electrical,
    PriorityLevel? officialPriority,
    String? workOrderId,
    DamageCategory? requestorCategory,
  }) => DamageReport(
    id: 'rep-1',
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: 'Lights flickering in Room 203',
    description: 'The lights flicker and buzz.',
    category: category,
    classifiedAutomatically: true,
    requestorCategory: requestorCategory,
    facilityId: 'fac-1',
    facilityName: 'Science Building',
    requestorPriority: PriorityLevel.medium,
    officialPriority: officialPriority,
    reviewedBy: officialPriority == null ? null : 'admin-1',
    reviewedAt: officialPriority == null ? null : now,
    status: status,
    workOrderId: workOrderId,
    submittedAt: now.subtract(const Duration(hours: 5)),
    updatedAt: now,
  );

  final electrician = fakePersonnel(id: 'p-elec', fullName: 'Ana Reyes');
  final busyElectrician = fakePersonnel(id: 'p-busy', fullName: 'Ben Cruz');
  final plumber = fakePersonnel(
    id: 'p-plumb',
    fullName: 'Carlo Luna',
    specialization: DamageCategory.plumbing,
  );
  final technician = fakePersonnel(
    id: 'p-air',
    fullName: 'Dina Sison',
    specialization: DamageCategory.airConditioning,
  );
  final held = WorkOrder(
    id: 'wo-9',
    reportIds: const ['rep-9'],
    title: 'Dead outlet in the library',
    description: '',
    category: DamageCategory.electrical,
    priority: PriorityLevel.medium,
    status: WorkOrderStatus.inProgress,
    assignedPersonnelIds: const ['p-busy'],
    createdBy: 'admin-1',
    createdAt: now,
    updatedAt: now,
  );

  Future<({FakeDamageReportRepository reports, FakeWorkOrderRepository work})>
  open(
    WidgetTester tester,
    DamageReport subject, {
    List<AppUser>? personnel,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 3600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final reports = FakeDamageReportRepository(Result.success([subject]));
    final work = FakeWorkOrderRepository(Result.success([held]));
    final router = GoRouter(
      initialLocation: RoutePaths.adminReportDetailFor(subject.id),
      routes: [
        GoRoute(
          path: RoutePaths.adminReportDetail,
          builder: (context, state) => Scaffold(
            body: ReportDetailScreen(
              reportId: state.pathParameters['reportId']!,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      fakeAdminScope(
        reportRepository: reports,
        workOrderRepository: work,
        personnel: Result.success(
          personnel ?? [electrician, busyElectrician, plumber, technician],
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return (reports: reports, work: work);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('Start review shows UNDER REVIEW at once, apart from PENDING', (
    tester,
  ) async {
    final backend = await open(tester, report());

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.textContaining('Press Start review'), findsOneWidget);
    expect(find.text('Classification and priority'), findsNothing);

    await tapVisible(tester, find.text('Start review'));

    expect(backend.reports.transitions.single.to, ReportStatus.underReview);
    expect(find.text('PENDING'), findsNothing);
    expect(find.text('UNDER REVIEW'), findsOneWidget);
    // In its own colour: PENDING's red made it read as not started.
    final chip = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('UNDER REVIEW'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (chip.decoration as BoxDecoration).color,
      AppColors.statusReviewBackground,
    );
    // The review of the type and priority is open, on the same page.
    expect(find.text('Classification and priority'), findsOneWidget);
    expect(
      find.textContaining('Review started: the report is Under Review'),
      findsOneWidget,
    );
  });

  testWidgets("the damage type starts as the reporter's choice, and changing "
      'it says so (2026-11-26)', (tester) async {
    await open(
      tester,
      report(
        status: ReportStatus.underReview,
        // The keywords found Electrical; the reporter chose Plumbing.
        requestorCategory: DamageCategory.plumbing,
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reporter-type')),
        matching: find.text('Plumbing'),
      ),
      findsOneWidget,
    );
    final note = find.byKey(const ValueKey('type-change-note'));
    expect(
      tester.widget<Text>(note).data,
      "Filled in with the reporter's choice, Plumbing. Confirm it, or choose "
      'another type.',
    );

    final dropdown = find.byType(DropdownButtonFormField<DamageCategory>);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Electrical').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(note).data,
      startsWith("Changed from the reporter's Plumbing to Electrical."),
    );
  });

  testWidgets('Approve waits for the confirmed official priority, not for a '
      'type that is already there', (tester) async {
    await open(tester, report(status: ReportStatus.underReview));
    FilledButton approve() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('approve-report')),
    );
    expect(approve().onPressed, isNull);
  });

  testWidgets('once confirmed, Approve opens the assignment on the same page', (
    tester,
  ) async {
    final backend = await open(
      tester,
      report(
        status: ReportStatus.underReview,
        officialPriority: PriorityLevel.high,
      ),
    );
    expect(find.text('Assign personnel'), findsNothing);

    await tapVisible(tester, find.byKey(const ValueKey('approve-report')));

    expect(backend.reports.transitions.single.to, ReportStatus.approved);
    expect(find.text('Assign personnel'), findsOneWidget);
  });

  testWidgets('an approved report lists its trade only, with availability '
      'and workload, and is assigned from here', (tester) async {
    final backend = await open(
      tester,
      report(
        status: ReportStatus.approved,
        officialPriority: PriorityLevel.high,
      ),
    );
    final section = find.byKey(const ValueKey('report-assignment'));
    Finder inSection(String text) =>
        find.descendant(of: section, matching: find.text(text));

    expect(
      find.descendant(
        of: section,
        matching: find.textContaining(
          'Electrical reports go to Electrician (Table 3.3)',
        ),
      ),
      findsOneWidget,
    );
    // Electricians only: a lights report.
    expect(inSection('Ana Reyes'), findsOneWidget);
    expect(inSection('Ben Cruz'), findsOneWidget);
    expect(inSection('Carlo Luna'), findsNothing);
    expect(inSection('Dina Sison'), findsNothing);
    // What each holds now.
    expect(inSection('Available'), findsOneWidget);
    expect(inSection('Busy'), findsOneWidget);
    expect(inSection('No current tasks'), findsOneWidget);
    expect(
      inSection('1 current task: Dead outlet in the library'),
      findsOneWidget,
    );

    await tapVisible(tester, find.byKey(const ValueKey('assign-p-elec')));
    expect(find.text('Assign this report'), findsOneWidget);
    expect(
      find.textContaining('The technician and the requestor are notified'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Assign').last);
    await tester.pumpAndSettle();

    expect(backend.work.assignments.single.reportId, 'rep-1');
    expect(backend.work.assignments.single.personnelId, 'p-elec');
    expect(
      find.textContaining('assigned to Ana Reyes. They and the requestor'),
      findsOneWidget,
    );
  });

  testWidgets('with nobody of its trade, the page says to reschedule', (
    tester,
  ) async {
    await open(
      tester,
      report(
        status: ReportStatus.approved,
        officialPriority: PriorityLevel.high,
      ),
      personnel: [plumber],
    );
    expect(
      find.textContaining('No Electrician account is registered'),
      findsOneWidget,
    );
  });

  testWidgets('Schedule (not Reschedule, on the report page) needs a reason '
      'and a date, and shows both', (tester) async {
    final backend = await open(
      tester,
      report(
        status: ReportStatus.approved,
        officialPriority: PriorityLevel.high,
      ),
    );

    await tapVisible(tester, find.byKey(const ValueKey('schedule-report')));
    await tester.tap(find.byKey(const ValueKey('schedule-save')));
    await tester.pumpAndSettle();
    expect(find.text('Give the reason the work has to wait.'), findsOneWidget);
    expect(find.text('Choose the date it is scheduled for.'), findsOneWidget);
    expect(backend.reports.reschedules, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('schedule-reason')),
      'The only electrician is on leave.',
    );
    await tester.tap(find.byKey(const ValueKey('schedule-date')));
    await tester.pumpAndSettle();
    // The picker opens on the next working day; OK keeps it.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-save')));
    await tester.pumpAndSettle();

    final asked = backend.reports.reschedules.single;
    expect(asked.reason, 'The only electrician is on leave.');
    // Tomorrow, or the next working day when tomorrow is a weekend
    // (2026-11-26).
    final expected = WorkingDays.firstFrom(
      DateUtils.dateOnly(now).add(const Duration(days: 1)),
      const {},
      last: now.add(const Duration(days: 30)),
    );
    expect(asked.rescheduledTo, expected);
    expect(
      find.textContaining('The requestor has been told why'),
      findsOneWidget,
    );
    // The page shows it, and offers to reschedule again.
    expect(
      find.textContaining(': The only electrician is on leave.'),
      findsOneWidget,
    );
    expect(find.text('Change schedule'), findsOneWidget);
  });

  testWidgets('an assigned report leads to its work order', (tester) async {
    await open(
      tester,
      report(
        status: ReportStatus.assigned,
        officialPriority: PriorityLevel.high,
        workOrderId: 'wo-1',
      ),
    );
    expect(find.text('Assign personnel'), findsNothing);
    expect(find.text('Open work order'), findsOneWidget);
    expect(find.text('Assigned'), findsOneWidget);
  });
}
