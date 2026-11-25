import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/core/widgets/working_day_picker.dart';
import 'package:gsuhub/features/facilities/data/models/asset.dart';
import 'package:gsuhub/features/facilities/data/models/building.dart';
import 'package:gsuhub/features/facilities/data/models/facility.dart';
import 'package:gsuhub/features/facilities/data/repositories/facility_repository.dart';
import 'package:gsuhub/features/facilities/presentation/facilities_screen.dart';
import 'package:gsuhub/features/settings/data/models/holiday.dart';
import 'package:gsuhub/features/settings/presentation/holidays_settings_section.dart';

import '../support/fake_admin_backend.dart';
import '../support/fake_holidays.dart';

/// The pieces of the second brief of 2026-11-26 that stand on their own:
/// the date picker that offers working days only, Settings → Holidays, and
/// the Facilities page on a database without the buildings update.
void main() {
  group('the working-day date picker', () {
    Future<void> open(
      WidgetTester tester, {
      required DateTime initial,
      required DateTime first,
      Set<DateTime> holidays = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWorkingDayPicker(
                context,
                holidays: holidays,
                initial: initial,
                first: first,
              ),
              child: const Text('Pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
    }

    testWidgets('asked to open on a Saturday, it opens on the next working '
        'day instead of throwing, past a holiday', (tester) async {
      // Saturday 28 Nov 2026; Monday 30 Nov a holiday.
      await open(
        tester,
        initial: DateTime(2026, 11, 28),
        first: DateTime(2026, 11, 26),
        holidays: {DateTime(2026, 11, 30)},
      );
      expect(tester.takeException(), isNull);
      // Past the weekend and the Monday holiday: Tuesday 1 Dec.
      expect(
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2026, 12),
      );
    });

    testWidgets('a weekend or a holiday cannot be chosen; a weekday can', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWorkingDayPicker(
                context,
                holidays: {DateTime(2026, 11, 30)},
                initial: DateTime(2026, 11, 27),
                first: DateTime(2026, 11, 26),
              ),
              child: const Text('Pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      final allowed = picker.selectableDayPredicate!;
      expect(allowed(DateTime(2026, 11, 27)), isTrue, reason: 'Friday');
      expect(allowed(DateTime(2026, 11, 28)), isFalse, reason: 'Saturday');
      expect(allowed(DateTime(2026, 11, 29)), isFalse, reason: 'Sunday');
      expect(allowed(DateTime(2026, 11, 30)), isFalse, reason: 'holiday');
      expect(allowed(DateTime(2026, 12)), isTrue, reason: 'Tuesday');
      expect(picker.initialDate, DateTime(2026, 11, 27));
    });
  });

  group('Settings → Holidays', () {
    Future<FakeHolidayRepository> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final holidays = FakeHolidayRepository([
        Holiday(day: DateTime(2026, 12, 25), name: 'Christmas Day'),
      ]);
      await tester.pumpWidget(
        fakeAdminScope(
          holidays: holidays,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: HolidaysSettingsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return holidays;
    }

    testWidgets('lists them, and nothing is entered for the administrator', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Christmas Day'), findsOneWidget);
      expect(find.text('Fri, Dec 25, 2026'), findsOneWidget);
    });

    testWidgets('a holiday is added with its date and name', (tester) async {
      final holidays = await pump(tester);

      await tester.tap(find.byKey(const ValueKey('new-holiday-day')));
      await tester.pumpAndSettle();
      // The picker opens on today; OK takes it.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-holiday-name')),
        'Bonifacio Day',
      );
      await tester.tap(find.byKey(const ValueKey('add-holiday')));
      await tester.pumpAndSettle();

      expect(holidays.all.map((h) => h.name), contains('Bonifacio Day'));
      expect(find.text('Bonifacio Day'), findsOneWidget);
    });

    testWidgets('without a date or a name, nothing is added', (tester) async {
      final holidays = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('add-holiday')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose the date and name the holiday.'),
        findsOneWidget,
      );
      expect(holidays.all, hasLength(1));
    });

    testWidgets('a holiday is removed', (tester) async {
      final holidays = await pump(tester);
      await tester.tap(find.byTooltip('Remove Christmas Day'));
      await tester.pumpAndSettle();
      expect(holidays.all, isEmpty);
      expect(find.text('Christmas Day'), findsNothing);
    });
  });

  testWidgets('Facilities on a database without the buildings update says so '
      'plainly, and offers nothing that would fail', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Its own scope: a nested one would not reach the providers built on
    // the repository.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          facilityRepositoryProvider.overrideWithValue(_NotUpdatedFacilities()),
        ],
        child: const MaterialApp(home: Scaffold(body: FacilitiesScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('buildings-need-update')), findsOneWidget);
    expect(
      find.text('Buildings are not set up on this system yet'),
      findsOneWidget,
    );
    expect(find.textContaining('schema cache'), findsNothing);
    final add = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Add Building'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(add.onPressed, isNull);
  });
}

/// The facilities of a database that has rooms but not the buildings table:
/// what the live project answered before the migration was pushed.
class _NotUpdatedFacilities implements FacilityRepository {
  @override
  Stream<Result<List<Building>>> watchBuildings() =>
      Stream.value(const Result.failure(DatabaseUpdateFailure()));

  @override
  Stream<Result<List<Facility>>> watchFacilities() =>
      Stream.value(const Result.success(<Facility>[]));

  @override
  Stream<Result<List<Asset>>> watchAssets() =>
      Stream.value(const Result.success(<Asset>[]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
