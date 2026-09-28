import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/location_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/reporting/presentation/submission/qr_scanner_screen.dart';
import 'package:gsuhub/features/reporting/presentation/submission/submit_report_screen.dart';
import 'package:gsuhub/features/reporting/presentation/submission/widgets/geo_tag_map.dart';

import '../support/fake_admin_backend.dart';
import '../support/fake_report_form_backend.dart';

/// The Report Damage screen (Figma `165:137`, Objective 3.C), end to end
/// against scripted camera, GPS, Storage and Firestore.
void main() {
  const requestor = AuthUser(
    uid: 'faculty-1',
    email: 'faculty@dorsu.edu.ph',
    role: UserRole.requestor,
  );

  late FakePhotoPicker picker;
  late FakeLocationService location;
  late FakeStorageService storage;
  late FakeSubmittingReportRepository reports;
  late FakeFacilityRepository facilities;
  String? scannedCode;
  GeoCoordinates? pinnedPoint;

  setUp(() {
    picker = FakePhotoPicker();
    location = FakeLocationService();
    storage = FakeStorageService();
    reports = FakeSubmittingReportRepository();
    facilities = FakeFacilityRepository();
    scannedCode = null;
    pinnedPoint = null;
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // A phone, as the design is drawn.
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            FakeAuthService(user: requestor),
          ),
          userRepositoryProvider.overrideWithValue(
            FakeUserRepository(
              personnel: const Result.success([]),
              signedIn: requestor,
            ),
          ),
          photoPickerServiceProvider.overrideWithValue(picker),
          locationServiceProvider.overrideWithValue(location),
          storageServiceProvider.overrideWithValue(storage),
          damageReportRepositoryProvider.overrideWithValue(reports),
          facilityRepositoryProvider.overrideWithValue(facilities),
          // No network in tests: an empty tile layer, and a scanner and
          // pin picker that answer at once.
          mapTileLayerProvider.overrideWithValue(const SizedBox.shrink()),
          qrScanLauncherProvider.overrideWithValue((_) async => scannedCode),
          mapPinLauncherProvider.overrideWithValue(
            (_, start) async => pinnedPoint,
          ),
        ],
        child: const MaterialApp(home: SubmitReportScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Opens the select showing [current] and picks [choice].
  Future<void> choose(
    WidgetTester tester,
    String current,
    String choice,
  ) async {
    await tapVisible(tester, find.text(current));
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g., Broken Ceiling Fan'),
      'Cracked window pane',
    );
    await choose(tester, 'Select Level', 'High');
    await choose(tester, 'Select Type', 'Carpentry');
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Describe the facility damage in detail...',
      ),
      'The pane beside the door is cracked across.',
    );
    await tapVisible(
      tester,
      find.text('Tap to take photo or upload from gallery'),
    );
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await choose(tester, 'Select Building', 'Engineering Building');
    await choose(tester, 'Select Room', 'Room 203');
  }

  testWidgets("shows the design's sections and labels", (tester) async {
    await pumpScreen(tester);

    for (final text in [
      'Report Damage',
      'FACILITY / ISSUE TITLE',
      'DAMAGE TYPE',
      'URGENCY LEVEL',
      'DAMAGE DESCRIPTION',
      'PHOTO EVIDENCE',
      'Tap to take photo or upload from gallery',
      'BUILDING',
      'ROOM',
      'GPS LOCATION',
      'AUTO-CAPTURE',
      'Submit Report',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Select Type'), findsOneWidget);
  });

  testWidgets('an empty submission marks what is missing and sends nothing', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tapVisible(tester, find.text('Submit Report'));

    for (final message in [
      'Give the damage a short title.',
      'Choose how urgent this is.',
      'Describe the damage.',
      'Add at least one photo.',
      'Choose the building.',
    ]) {
      expect(find.text(message), findsOneWidget, reason: message);
    }
    expect(storage.uploadedPaths, isEmpty);
    expect(reports.submissions, isEmpty);
  });

  testWidgets('a completed form uploads, files, confirms and starts over', (
    tester,
  ) async {
    await pumpScreen(tester);
    await fillIn(tester);
    expect(find.byType(Image), findsWidgets, reason: 'photo thumbnail shown');

    await tapVisible(tester, find.text('Submit Report'));

    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.textContaining('#DR-'), findsOneWidget);
    final filed = reports.submissions.single.submission;
    expect(filed.title, 'Cracked window pane');
    expect(filed.requestorPriority, PriorityLevel.high);
    expect(filed.requestorCategory, DamageCategory.carpentry);
    expect(filed.facilityId, 'fac-eng-203');
    expect(filed.photoUrls, hasLength(1));
    expect(filed.coordinates, isNull, reason: 'the geo-tag was left off');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Cracked window pane'), findsNothing);
    expect(find.text('Select Building'), findsOneWidget);
  });

  testWidgets('auto-capture attaches the position and shows it on the map', (
    tester,
  ) async {
    await pumpScreen(tester);
    await choose(tester, 'Select Building', 'Engineering Building');

    await tapVisible(tester, find.text('AUTO-CAPTURE'));

    expect(find.byType(GeoTagMapPreview), findsOneWidget);
    expect(find.text('Engineering Building, DOrSU'), findsOneWidget);
    expect(find.text('Lat: 7.2048, Long: 126.5354'), findsOneWidget);
    expect(find.text('Tap to adjust location on map'), findsOneWidget);
  });

  testWidgets('the pin picker moves the geo-tag', (tester) async {
    pinnedPoint = const GeoCoordinates(latitude: 7.2051, longitude: 126.5360);
    await pumpScreen(tester);
    await tapVisible(tester, find.text('AUTO-CAPTURE'));

    await tapVisible(tester, find.text('Tap to adjust location on map'));

    expect(find.text('Lat: 7.2051, Long: 126.5360'), findsOneWidget);
  });

  testWidgets('a refused location explains itself and offers a retry', (
    tester,
  ) async {
    location.result = const Result.failure(
      PermissionFailure('Location access was not allowed.'),
    );
    await pumpScreen(tester);

    await tapVisible(tester, find.text('AUTO-CAPTURE'));

    expect(find.text('Location access was not allowed.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(GeoTagMapPreview), findsNothing);
  });

  testWidgets('a scanned QR code fills in the building and room', (
    tester,
  ) async {
    scannedCode = 'FAC-FAC-ENG-203';
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Scan a facility QR code'));
    await tester.pumpAndSettle();

    expect(find.text('Found Engineering Building, Room 203.'), findsOneWidget);
    expect(find.text('Engineering Building'), findsOneWidget);
    expect(find.text('Room 203'), findsOneWidget);
  });

  testWidgets('an unregistered QR code says so and changes nothing', (
    tester,
  ) async {
    scannedCode = 'SOMETHING-ELSE';
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Scan a facility QR code'));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't registered"), findsOneWidget);
    expect(find.text('Select Building'), findsOneWidget);
  });

  testWidgets('buildings that fail to load say so, with a retry', (
    tester,
  ) async {
    facilities = FakeFacilityRepository(
      failure: const NetworkFailure('The request timed out.'),
    );
    await pumpScreen(tester);

    expect(find.text('The request timed out.'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a failed filing is shown and can be retried', (tester) async {
    reports.submitResult = const Result.failure(
      NetworkFailure('The request timed out.'),
    );
    await pumpScreen(tester);
    await fillIn(tester);

    await tapVisible(tester, find.text('Submit Report'));
    expect(find.text('The request timed out.'), findsOneWidget);
    expect(find.text('Report submitted'), findsNothing);

    reports.submitResult = const Result.success(null);
    await tapVisible(tester, find.text('Submit Report'));

    expect(find.text('Report submitted'), findsOneWidget);
    expect(storage.uploadedPaths, hasLength(1), reason: 'not sent twice');
  });

  testWidgets('a photo can be removed', (tester) async {
    await pumpScreen(tester);
    await tapVisible(
      tester,
      find.text('Tap to take photo or upload from gallery'),
    );
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Remove photo')), findsOneWidget);

    await tapVisible(tester, find.bySemanticsLabel(RegExp('Remove photo')));

    expect(find.bySemanticsLabel(RegExp('Remove photo')), findsNothing);
  });
}
