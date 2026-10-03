import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gsuhub/app.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/connectivity_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/notifications/data/models/app_notification.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/models/report_submission.dart';
import 'package:gsuhub/features/reporting/data/models/status_change.dart';
import 'package:gsuhub/features/reporting/presentation/submission/qr_scanner_screen.dart';
import 'package:gsuhub/features/reporting/presentation/submission/widgets/geo_tag_map.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository.dart';

import 'fake_notifications.dart';
import 'fake_report_form_backend.dart';
import 'test_app_config.dart';

/// Stands up the faculty and staff app (Objective 3.A) without Firebase:
/// the real router, shell and screens, over an auth service whose session
/// can change and a report store that the form files into.

const fakeRequestor = AuthUser(
  uid: 'faculty-1',
  email: 'faculty@dorsu.edu.ph',
  role: UserRole.requestor,
);

/// The signed-in requestor's profile, as `users/faculty-1` would hold it.
AppUser fakeRequestorProfile({String? department = 'College of Engineering'}) =>
    AppUser(
      id: fakeRequestor.uid,
      fullName: 'Maria Santos',
      email: fakeRequestor.email,
      role: UserRole.requestor,
      accountStatus: AccountStatus.active,
      department: department,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// A report the requestor filed.
DamageReport fakeMyReport(
  String id, {
  ReportStatus status = ReportStatus.submitted,
  String location = 'Science Building, Laboratory 1',
  String title = 'Broken ceiling fan',
  DamageCategory? requestorCategory = DamageCategory.electrical,
  DateTime? submittedAt,
  String? rejectionReason,
  DamageCategory? category,
  PriorityLevel? officialPriority,
  String? reviewedBy,
  String? workOrderId,
  String? duplicateOf,
}) => DamageReport(
  id: id,
  reporterId: fakeRequestor.uid,
  reporterName: 'Maria Santos',
  title: title,
  description: 'The fan wobbles and sparks at the switch.',
  requestorPriority: PriorityLevel.high,
  requestorCategory: requestorCategory,
  status: status,
  facilityId: 'fac-science-lab1',
  facilityName: 'Science Building',
  locationDescription: location,
  rejectionReason: rejectionReason,
  category: category,
  officialPriority: officialPriority,
  reviewedBy: reviewedBy,
  workOrderId: workOrderId,
  duplicateOf: duplicateOf,
  submittedAt: submittedAt ?? DateTime.now().subtract(const Duration(hours: 3)),
  updatedAt: DateTime.now(),
);

/// An [AuthService] whose session changes as a real one would: signing in
/// emits the user, signing out emits null.
class ScriptedAuthService implements AuthService {
  ScriptedAuthService({AuthUser? signedIn}) : _user = signedIn;

  AuthUser? _user;
  final _changes = StreamController<AuthUser?>.broadcast();

  /// What the next sign-in answers. Defaults to the requestor.
  Result<AuthUser> signInResult = const Result.success(fakeRequestor);

  /// What [register] answers before writing the profile.
  Result<void> registerResult = const Result.success(null);

  final registered = <String>[];
  int signInCalls = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<Result<AuthUser>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    final result = signInResult;
    if (result case Success(:final value)) {
      _user = value;
      _changes.add(value);
    }
    return result;
  }

  @override
  Future<Result<void>> register({
    required String email,
    required String password,
    required Future<Result<void>> Function(String uid) writeProfile,
  }) async {
    registered.add(email);
    if (registerResult case Error()) return registerResult;
    // Signs nobody in, as the real one leaves things.
    return writeProfile('new-faculty-${registered.length}');
  }

  @override
  Future<Result<void>> signOut() async {
    _user = null;
    _changes.add(null);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail({required String email}) async =>
      const Result.success(null);

  Future<void> dispose() => _changes.close();
}

/// The requestor's reports, live: answers the home screen, My Reports and
/// the detail page, takes what the form files, and lets a test change a
/// report or its history as an administrator would — every open listener
/// hears of it, as Firestore's would.
class FakeRequestorReportRepository extends FakeSubmittingReportRepository {
  FakeRequestorReportRepository({List<DamageReport>? reports, this.failure})
    : _reports = {
        for (final report in reports ?? const <DamageReport>[])
          report.id: report,
      };

  final Map<String, DamageReport> _reports;
  final Map<String, List<StatusChange>> _histories = {};
  final _changes = StreamController<void>.broadcast();

  /// When set, listening to the requestor's reports fails with this.
  Failure? failure;

  /// When set, listening to a report's status history fails with this.
  Failure? historyFailure;

  final reporterQueries = <String>[];

  /// How many listeners are open on reports or histories right now — zero
  /// once every screen using them has gone.
  int get openListeners => _open;
  int _open = 0;

  /// Saves [report] over its earlier version, as an administrator's change
  /// would land.
  void put(DamageReport report) {
    _reports[report.id] = report;
    _changes.add(null);
  }

  /// Appends to a report's status history.
  void record(String reportId, StatusChange change) {
    (_histories[reportId] ??= []).add(change);
    _changes.add(null);
  }

  /// The current answer, then a fresh one after every change.
  Stream<T> _live<T>(T Function() read) => Stream.multi((listener) {
    _open++;
    listener.add(read());
    final changes = _changes.stream.listen((_) => listener.add(read()));
    listener.onCancel = () {
      _open--;
      return changes.cancel();
    };
  });

  @override
  Stream<Result<List<DamageReport>>> watchByReporter(String reporterId) {
    reporterQueries.add(reporterId);
    if (failure case final failure?) {
      return Stream.value(Result.failure(failure));
    }
    return _live(
      () => Result.success(
        _reports.values
            .where((report) => report.reporterId == reporterId)
            .toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
      ),
    );
  }

  @override
  Stream<Result<DamageReport>> watchById(String id) => _live(
    () => switch (_reports[id]) {
      final report? => Result.success(report),
      null => const Result.failure(NotFoundFailure('No such report.')),
    },
  );

  @override
  Stream<Result<List<StatusChange>>> watchStatusHistory(String reportId) {
    if (historyFailure case final failure?) {
      return Stream.value(Result.failure(failure));
    }
    return _live(
      () => Result.success(
        (_histories[reportId] ?? const <StatusChange>[]).toList()
          ..sort((a, b) => a.changedAt.compareTo(b.changedAt)),
      ),
    );
  }

  Future<void> dispose() => _changes.close();

  @override
  Future<Result<void>> submit({
    required String reportId,
    required ReportSubmission submission,
  }) async {
    final result = await super.submit(
      reportId: reportId,
      submission: submission,
    );
    if (result.isSuccess) {
      final coordinates = submission.coordinates;
      put(
        DamageReport(
          id: reportId,
          reporterId: submission.reporter.id,
          reporterName: submission.reporter.name,
          title: submission.title,
          description: submission.description,
          requestorPriority: submission.requestorPriority,
          requestorCategory: submission.requestorCategory,
          status: ReportStatus.submitted,
          facilityId: submission.facilityId,
          facilityName: submission.facilityName,
          locationDescription: submission.locationDescription,
          coordinates: coordinates == null
              ? null
              : GeoPoint(coordinates.latitude, coordinates.longitude),
          photoUrls: submission.photoUrls,
          submittedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
    return result;
  }
}

/// Users: the signed-in profile, and what sign-up writes.
class FakeRequestorUserRepository implements UserRepository {
  FakeRequestorUserRepository({AppUser? profile, this.writeResult})
    : profile = profile ?? fakeRequestorProfile();

  final AppUser profile;
  final Result<void>? writeResult;
  final created = <AppUser>[];

  /// Every push token written to the account, null for a cleared one.
  final tokens = <String?>[];

  @override
  Future<Result<AppUser>> getById(String uid) async => uid == profile.id
      ? Result.success(profile)
      : const Result.failure(NotFoundFailure('No such account.'));

  @override
  Future<Result<void>> setFcmToken(String uid, String? token) async {
    tokens.add(token);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> createSelfRegistration(AppUser user) async {
    created.add(user);
    return writeResult ?? const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Backend reachability a test can switch, for the offline banner.
class FakeConnectivityService implements ConnectivityService {
  final _changes = StreamController<BackendReachability>.broadcast();
  BackendReachability _current = BackendReachability.online;

  void set(BackendReachability reachability) {
    _current = reachability;
    _changes.add(reachability);
  }

  @override
  BackendReachability get current => _current;

  @override
  Stream<BackendReachability> get reachability async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<Result<bool>> checkReachable() async =>
      Result.success(_current == BackendReachability.online);

  Future<void> dispose() => _changes.close();
}

/// The fakes one test works with.
class RequestorHarness {
  RequestorHarness({
    AuthUser? signedIn = fakeRequestor,
    List<DamageReport>? reports,
    AppUser? profile,
    List<AppNotification> notices = const [],
  }) : auth = ScriptedAuthService(signedIn: signedIn),
       reports = FakeRequestorReportRepository(reports: reports),
       users = FakeRequestorUserRepository(profile: profile),
       notifications = FakeNotificationRepository(notices);

  final ScriptedAuthService auth;
  final FakeRequestorReportRepository reports;
  final FakeRequestorUserRepository users;
  final FakeNotificationRepository notifications;
  final push = FakeNotificationService();
  final location = FakeLocationService();
  final picker = FakePhotoPicker();
  final storage = FakeStorageService();
  final facilities = FakeFacilityRepository();
  final connectivity = FakeConnectivityService();

  /// Boots the app at [start] on a phone-sized screen.
  Future<void> pump(
    WidgetTester tester, {
    String start = RoutePaths.staffHome,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(auth.dispose);
    addTearDown(reports.dispose);
    addTearDown(connectivity.dispose);
    addTearDown(notifications.dispose);
    addTearDown(push.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig()),
          startLocationProvider.overrideWithValue(start),
          authServiceProvider.overrideWithValue(auth),
          damageReportRepositoryProvider.overrideWithValue(reports),
          userRepositoryProvider.overrideWithValue(users),
          facilityRepositoryProvider.overrideWithValue(facilities),
          photoPickerServiceProvider.overrideWithValue(picker),
          locationServiceProvider.overrideWithValue(location),
          storageServiceProvider.overrideWithValue(storage),
          connectivityServiceProvider.overrideWithValue(connectivity),
          notificationRepositoryProvider.overrideWithValue(notifications),
          notificationServiceProvider.overrideWithValue(push),
          mapTileLayerProvider.overrideWithValue(const SizedBox.shrink()),
          qrScanLauncherProvider.overrideWithValue((_) async => null),
          mapPinLauncherProvider.overrideWithValue((_, _) async => null),
        ],
        child: const GsuhubApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Where the app currently is — the page on top, pushed pages included.
String currentPath(WidgetTester tester) {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  final router = app.routerConfig! as GoRouter;
  return router.state.uri.path;
}
