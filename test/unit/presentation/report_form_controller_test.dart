import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/photo_picker_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/facilities/data/models/asset.dart';
import 'package:gsuhub/features/reporting/presentation/submission/report_form_controller.dart';
import 'package:gsuhub/features/reporting/presentation/submission/report_form_state.dart';

import '../../support/fake_admin_backend.dart';
import '../../support/fake_report_form_backend.dart';

/// The report form's behaviour (Objective 3.C), with the camera, GPS,
/// Storage and Firestore all scripted.
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
  late ProviderContainer container;

  final aircon = Asset(
    id: 'asset-aircon-01',
    name: 'Split-Type Aircon Unit',
    qrCode: 'AST-AIRCON',
    facilityId: 'fac-eng-203',
    condition: ItemCondition.good,
    isActive: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  setUp(() {
    picker = FakePhotoPicker();
    location = FakeLocationService();
    storage = FakeStorageService();
    reports = FakeSubmittingReportRepository();
    facilities = FakeFacilityRepository(assets: [aircon]);
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService(user: requestor)),
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
      ],
    );
    // The provider is autoDispose; hold it open as the screen would.
    container.listen(reportFormControllerProvider, (_, _) {});
    addTearDown(container.dispose);
  });

  ReportFormController form() =>
      container.read(reportFormControllerProvider.notifier);
  ReportFormState state() => container.read(reportFormControllerProvider);

  /// Everything filled in but the photos.
  void fillIn() {
    form()
      ..setTitle('Cracked window pane')
      ..setUrgency(PriorityLevel.high)
      ..setDescription('The pane beside the door is cracked across.')
      ..selectRoom(facilities.facilities.first);
  }

  group('validation', () {
    test('an untouched form shows no errors', () {
      expect(state().errorFor(ReportField.title), isNull);
      expect(state().errors, isNotEmpty);
    });

    test('submitting an empty form reveals every missing field and sends '
        'nothing', () async {
      await form().submit();

      expect(state().showErrors, isTrue);
      for (final field in [
        ReportField.title,
        ReportField.urgency,
        ReportField.description,
        ReportField.photos,
        ReportField.building,
      ]) {
        expect(state().errorFor(field), isNotNull, reason: '$field');
      }
      expect(storage.uploadedPaths, isEmpty);
      expect(reports.submissions, isEmpty);
    });

    test('a building without a room asks for the room', () async {
      form().selectBuilding('Engineering Building');
      await form().submit();

      expect(state().errorFor(ReportField.building), isNull);
      expect(state().errorFor(ReportField.room), 'Choose the room.');
    });

    test('whitespace is not a title or a description', () async {
      form()
        ..setTitle('   ')
        ..setDescription('\n ');
      await form().submit();

      expect(state().errorFor(ReportField.title), isNotNull);
      expect(state().errorFor(ReportField.description), isNotNull);
    });
  });

  group('photos', () {
    test('are added from the chosen source, up to the limit', () async {
      picker.photos = List.generate(8, (i) => fakePhoto(name: 'p$i.jpg'));

      await form().addPhotos(PhotoSource.gallery);

      expect(state().photos, hasLength(ReportFormController.maxPhotos));
      expect(picker.requests.single.source, PhotoSource.gallery);
      expect(picker.requests.single.limit, ReportFormController.maxPhotos);
    });

    test('ask the picker only for the room left', () async {
      picker.photos = [fakePhoto(), fakePhoto()];
      await form().addPhotos(PhotoSource.camera);
      await form().addPhotos(PhotoSource.camera);

      expect(picker.requests.last.limit, ReportFormController.maxPhotos - 2);
    });

    test('say so once the limit is reached', () async {
      picker.photos = List.generate(5, (_) => fakePhoto());
      await form().addPhotos(PhotoSource.gallery);

      final message = await form().addPhotos(PhotoSource.camera);

      expect(message, contains('up to ${ReportFormController.maxPhotos}'));
      expect(picker.requests, hasLength(1));
    });

    test('over 10 MB are left out, with a reason', () async {
      picker.photos = [
        fakePhoto(),
        fakePhoto(bytes: ReportFormController.maxPhotoBytes),
      ];

      final message = await form().addPhotos(PhotoSource.gallery);

      expect(state().photos, hasLength(1));
      expect(message, 'That photo is over 10 MB, so it was left out.');
    });

    test('a refused permission comes back as the message to show', () async {
      picker.failure = const PermissionFailure('Camera access is blocked.');

      final message = await form().addPhotos(PhotoSource.camera);

      expect(message, 'Camera access is blocked.');
      expect(state().photos, isEmpty);
    });

    test('can be removed', () async {
      picker.photos = [fakePhoto(), fakePhoto()];
      await form().addPhotos(PhotoSource.gallery);

      form().removePhoto(state().photos.first.id);

      expect(state().photos, hasLength(1));
    });
  });

  group('geo-tag', () {
    test('attaches the device position when switched on', () async {
      await form().setGeoTag(enabled: true);

      expect(state().geoTagStatus, GeoTagStatus.attached);
      expect(state().coordinates, FakeLocationService.campus);
    });

    test('explains itself when the device cannot say', () async {
      location.result = const Result.failure(
        PermissionFailure('Location access was not allowed.'),
      );

      await form().setGeoTag(enabled: true);

      expect(state().geoTagStatus, GeoTagStatus.unavailable);
      expect(state().geoTagMessage, 'Location access was not allowed.');
      expect(state().coordinates, isNull);
    });

    test('switched off while locating, stays off', () async {
      location.gate = Completer();
      final locating = form().setGeoTag(enabled: true);
      expect(state().geoTagStatus, GeoTagStatus.locating);

      await form().setGeoTag(enabled: false);
      location.gate!.complete();
      await locating;

      expect(state().geoTagStatus, GeoTagStatus.off);
      expect(state().coordinates, isNull);
    });
  });

  group('QR lookup', () {
    test("a facility's code fills in the building and room", () async {
      final result = await form().applyQrCode(' FAC-FAC-ENG-203 ');

      expect(result.isSuccess, isTrue);
      expect(state().building, 'Engineering Building');
      expect(state().facility?.id, 'fac-eng-203');
      expect(state().asset, isNull);
    });

    test("an asset's code fills in its room and names the asset", () async {
      await form().applyQrCode('AST-AIRCON');

      expect(state().facility?.id, 'fac-eng-203');
      expect(state().asset?.id, 'asset-aircon-01');
    });

    test('an unknown code changes nothing', () async {
      form().selectRoom(facilities.facilities.last);

      final result = await form().applyQrCode('NOT-A-CODE');

      expect(result, isA<Error<Object>>());
      expect(state().facility?.id, 'fac-library');
    });

    test('choosing another room drops a scanned asset', () async {
      await form().applyQrCode('AST-AIRCON');

      form().selectRoom(facilities.facilities.first);

      expect(state().asset, isNull);
    });

    test('choosing another building clears the room', () async {
      form().selectRoom(facilities.facilities.first);

      form().selectBuilding('Main Library');

      expect(state().facility, isNull);
      expect(state().building, 'Main Library');
    });
  });

  group('submitting', () {
    test('uploads each photo under the new report, then files it', () async {
      picker.photos = [fakePhoto(), fakePhoto()];
      await form().addPhotos(PhotoSource.gallery);
      await form().setGeoTag(enabled: true);
      fillIn();

      await form().submit();

      expect(state().phase, isA<SubmissionDone>());
      expect(storage.uploadedPaths, hasLength(2));
      for (final path in storage.uploadedPaths) {
        expect(
          path,
          startsWith(
            'damage_reports/${FakeSubmittingReportRepository.idFor(1)}/',
          ),
        );
        expect(path, endsWith('.jpg'));
      }

      final filed = reports.submissions.single;
      expect(filed.reportId, FakeSubmittingReportRepository.idFor(1));
      expect(filed.submission.reporter.id, 'faculty-1');
      expect(filed.submission.title, 'Cracked window pane');
      expect(filed.submission.requestorPriority, PriorityLevel.high);
      expect(filed.submission.facilityId, 'fac-eng-101');
      expect(
        filed.submission.locationDescription,
        'Engineering Building, Room 101',
      );
      expect(filed.submission.coordinates, FakeLocationService.campus);
      expect(filed.submission.photoUrls, [
        for (final path in storage.uploadedPaths) 'https://storage.test/$path',
      ]);
    });

    test('files no coordinates when the geo-tag is off', () async {
      await form().addPhotos(PhotoSource.camera);
      fillIn();

      await form().submit();

      expect(reports.submissions.single.submission.coordinates, isNull);
    });

    test('files no coordinates when the device could not give any', () async {
      location.result = const Result.failure(
        ValidationFailure('Location is turned off.'),
      );
      await form().addPhotos(PhotoSource.camera);
      await form().setGeoTag(enabled: true);
      fillIn();

      await form().submit();

      expect(state().phase, isA<SubmissionDone>());
      expect(reports.submissions.single.submission.coordinates, isNull);
    });

    test(
      'a failed upload stops before filing, and the retry resumes',
      () async {
        picker.photos = [fakePhoto(), fakePhoto()];
        await form().addPhotos(PhotoSource.gallery);
        fillIn();
        storage.failures[(path) =>
            path.contains('/photo-2-')] = const NetworkFailure(
          'The request timed out.',
        );

        await form().submit();

        final failed = state().phase;
        expect(failed, isA<SubmissionFailed>());
        expect((failed as SubmissionFailed).message, contains('Photo 2 of 2'));
        expect(reports.submissions, isEmpty);
        expect(storage.uploadedPaths, hasLength(1));

        storage.failures.clear();
        await form().submit();

        expect(state().phase, isA<SubmissionDone>());
        // The first photo was not sent again, and both went under one id.
        expect(storage.uploadedPaths, hasLength(2));
        expect(
          storage.uploadedPaths.every(
            (path) => path.startsWith(
              'damage_reports/${FakeSubmittingReportRepository.idFor(1)}/',
            ),
          ),
          isTrue,
        );
        expect(reports.submissions.single.submission.photoUrls, hasLength(2));
      },
    );

    test('a failed filing keeps the report id for the retry', () async {
      await form().addPhotos(PhotoSource.camera);
      fillIn();
      reports.submitResult = const Result.failure(
        NetworkFailure('The request timed out.'),
      );

      await form().submit();
      expect(state().phase, isA<SubmissionFailed>());

      reports.submitResult = const Result.success(null);
      await form().submit();

      expect(state().phase, isA<SubmissionDone>());
      expect(reports.submissions.map((s) => s.reportId).toSet(), {
        FakeSubmittingReportRepository.idFor(1),
      });
      expect(storage.uploadedPaths, hasLength(1), reason: 'no re-upload');
    });

    test('once filed, the form no longer changes or sends again', () async {
      await form().addPhotos(PhotoSource.camera);
      fillIn();
      await form().submit();

      form().setTitle('Changed');
      await form().submit();

      expect(state().title, 'Cracked window pane');
      expect(reports.submissions, hasLength(1));
    });

    test('editing after a failure returns the form to editing', () async {
      await form().addPhotos(PhotoSource.camera);
      fillIn();
      reports.submitResult = const Result.failure(
        NetworkFailure('The request timed out.'),
      );
      await form().submit();

      form().setTitle('Cracked window pane, Room 101');

      expect(state().phase, isA<SubmissionEditing>());
    });
  });
}
