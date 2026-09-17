import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/audit/data/repositories/audit_log_repository.dart';
import 'package:gsuhub/features/notifications/data/repositories/notification_repository.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository.dart';

import 'test_app_config.dart';

/// Stand-ins for the auth service and the three repositories the admin
/// shell and dashboard read from.
///
/// The alternative — a `fake_cloud_firestore` instance behind the real
/// repositories — would exercise Firestore's query semantics, which 1.C
/// already covers. What is under test here is the widget layer, so the
/// backend is reduced to "here is a value, here is an empty list, here is
/// a failure" and nothing more.

const fakeAdminUser = AuthUser(
  uid: 'admin-1',
  email: 'admin@dorsu.edu.ph',
  role: UserRole.admin,
);

/// Wraps [child] in a scope that stands the admin UI up without Firebase.
///
/// Returns the scope rather than a list of overrides because Riverpod's
/// `Override` type is sealed and unexported, so a helper cannot name it.
///
/// The defaults describe the empty case: signed in, no reports, no
/// activity, no notifications. Pass arguments to describe a fuller — or a
/// broken — backend.
ProviderScope fakeAdminScope({
  required Widget child,
  AuthUser? user = fakeAdminUser,
  FakeAuthService? authService,
  Result<List<DamageReport>> reports = const Result.success(<DamageReport>[]),
  Result<List<AuditLogEntry>> activity = const Result.success(
    <AuditLogEntry>[],
  ),
  Result<int> unreadCount = const Result.success(0),
  bool useEmulator = false,
}) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWithValue(
      testAppConfig(useEmulator: useEmulator),
    ),
    authServiceProvider.overrideWithValue(
      authService ?? FakeAuthService(user: user),
    ),
    damageReportRepositoryProvider.overrideWithValue(
      FakeDamageReportRepository(reports),
    ),
    auditLogRepositoryProvider.overrideWithValue(
      FakeAuditLogRepository(activity),
    ),
    notificationRepositoryProvider.overrideWithValue(
      FakeNotificationRepository(unreadCount),
    ),
  ],
  child: child,
);

/// Each repository fake implements its interface through `noSuchMethod`,
/// so it carries only the members the UI actually calls. Hand-writing
/// stubs for all twenty-odd methods would be noise, and would need editing
/// every time an unrelated method joined a contract.

class FakeAuthService implements AuthService {
  FakeAuthService({this.user});

  final AuthUser? user;

  int signInCallCount = 0;
  int signOutCallCount = 0;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(user);

  @override
  Future<Result<AuthUser>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCallCount++;
    final signedIn = user;
    return signedIn == null
        ? const Result.failure(PermissionFailure('No user configured.'))
        : Result.success(signedIn);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail({required String email}) async =>
      const Result.success(null);

  @override
  Future<Result<void>> signOut() async {
    signOutCallCount++;
    return const Result.success(null);
  }
}

class FakeDamageReportRepository implements DamageReportRepository {
  FakeDamageReportRepository(this._reports);

  final Result<List<DamageReport>> _reports;

  @override
  Stream<Result<List<DamageReport>>> watchAll({
    ReportStatus? status,
    PriorityLevel? priority,
    String? categoryId,
    bool excludeDuplicates = true,
  }) => Stream.value(_reports);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuditLogRepository implements AuditLogRepository {
  FakeAuditLogRepository(this._entries);

  final Result<List<AuditLogEntry>> _entries;

  @override
  Future<Result<List<AuditLogEntry>>> query({
    AuditAction? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async => _entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository(this._unread);

  final Result<int> _unread;

  @override
  Stream<Result<int>> watchUnreadCount(String userId) => Stream.value(_unread);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
