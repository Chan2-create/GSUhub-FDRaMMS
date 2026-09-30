import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/audit_action.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/account_provisioning_service.dart';
import 'package:gsuhub/core/services/auth_service.dart';
import 'package:gsuhub/core/services/file_download_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/audit/data/models/audit_log_entry.dart';
import 'package:gsuhub/features/audit/data/repositories/audit_log_repository.dart';
import 'package:gsuhub/features/notifications/data/repositories/notification_repository.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/reporting/data/repositories/damage_report_repository.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/user_management/data/repositories/user_repository.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';
import 'package:gsuhub/features/work_orders/data/repositories/work_order_repository.dart';

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
  Result<List<WorkOrder>> workOrders = const Result.success(<WorkOrder>[]),
  Result<List<AppUser>> personnel = const Result.success(<AppUser>[]),
  FakeWorkOrderRepository? workOrderRepository,
  FakeUserRepository? userRepository,
  FakeAccountProvisioningService? provisioning,
  FakeFileDownloadService? downloads,
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
    workOrderRepositoryProvider.overrideWithValue(
      workOrderRepository ?? FakeWorkOrderRepository(workOrders),
    ),
    userRepositoryProvider.overrideWithValue(
      userRepository ??
          FakeUserRepository(personnel: personnel, signedIn: user),
    ),
    accountProvisioningServiceProvider.overrideWithValue(
      provisioning ?? FakeAccountProvisioningService(),
    ),
    fileDownloadServiceProvider.overrideWithValue(
      downloads ?? FakeFileDownloadService(),
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

class FakeWorkOrderRepository implements WorkOrderRepository {
  FakeWorkOrderRepository(
    this._workOrders, {
    this.assignResult = const Result.success('wo-new'),
    this.statusResult = const Result.success(null),
  });

  final Result<List<WorkOrder>> _workOrders;

  /// What an assignment or a Kanban move returns. Set a failure to check
  /// that the screen surfaces the message rather than pretending it worked.
  final Result<String> assignResult;
  final Result<void> statusResult;

  final List<({String reportId, String personnelId, DateTime? scheduledFor})>
  assignments = [];
  final List<({String workOrderId, WorkOrderStatus status})> moves = [];

  @override
  Stream<Result<List<WorkOrder>>> watchAll({
    WorkOrderStatus? status,
    String? categoryId,
  }) => Stream.value(_workOrders);

  @override
  Future<Result<String>> assignFromReport({
    required String reportId,
    required String personnelId,
    required AuditActor actor,
    DateTime? scheduledFor,
  }) async {
    assignments.add((
      reportId: reportId,
      personnelId: personnelId,
      scheduledFor: scheduledFor,
    ));
    return assignResult;
  }

  @override
  Future<Result<void>> setStatus(
    String workOrderId,
    WorkOrderStatus status, {
    required AuditActor actor,
  }) async {
    moves.add((workOrderId: workOrderId, status: status));
    return statusResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserRepository implements UserRepository {
  FakeUserRepository({
    required this.personnel,
    this.signedIn,
    Result<List<AppUser>>? accounts,
    this.writeResult = const Result.success(null),
  }) : accounts = accounts ?? personnel;

  final Result<List<AppUser>> personnel;
  final AuthUser? signedIn;

  /// Every account, for User Accounts. Defaults to [personnel].
  final Result<List<AppUser>> accounts;

  /// What the account writes answer.
  final Result<void> writeResult;

  final created = <AppUser>[];
  final updated = <AppUser>[];
  final statusChanges = <({String uid, AccountStatus status})>[];

  @override
  Stream<Result<List<AppUser>>> watchAll() => Stream.value(accounts);

  @override
  Future<Result<void>> createAccount({
    required AppUser user,
    required AuditActor actor,
  }) async {
    created.add(user);
    return writeResult;
  }

  @override
  Future<Result<void>> updateAccount({
    required AppUser updated,
    required AuditActor actor,
  }) async {
    this.updated.add(updated);
    return writeResult;
  }

  @override
  Future<Result<void>> setAccountStatus(
    String uid,
    AccountStatus status, {
    required AuditActor actor,
  }) async {
    statusChanges.add((uid: uid, status: status));
    return writeResult;
  }

  @override
  Stream<Result<List<AppUser>>> watchPersonnel() => Stream.value(personnel);

  /// Backs `currentActorProvider`, which names the actor on every audit
  /// entry.
  @override
  Future<Result<AppUser>> getById(String uid) async => Result.success(
    AppUser(
      id: uid,
      fullName: 'Ramon Dela Cruz',
      email: signedIn?.email ?? 'admin@dorsu.edu.ph',
      role: UserRole.admin,
      accountStatus: AccountStatus.active,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A maintenance-personnel account for the assignment panel.
AppUser fakePersonnel({
  required String id,
  required String fullName,
  DamageCategory? specialization = DamageCategory.electrical,
  AccountStatus accountStatus = AccountStatus.active,
  int activeTaskCount = 0,
}) => AppUser(
  id: id,
  fullName: fullName,
  email: '$id@dorsu.edu.ph',
  role: UserRole.maintenancePersonnel,
  accountStatus: accountStatus,
  specialization: specialization,
  activeTaskCount: activeTaskCount,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// Provisions without Firebase: hands back a uid and runs the profile
/// write, as the real service does, unless told to refuse first.
class FakeAccountProvisioningService implements AccountProvisioningService {
  FakeAccountProvisioningService({this.refusal, this.setupEmailSent = true});

  /// When set, provisioning fails with this before any profile is written
  /// — as an email already in use does.
  final Failure? refusal;
  final bool setupEmailSent;

  final emails = <String>[];

  @override
  Future<Result<ProvisionedAccount>> provision({
    required String email,
    required Future<Result<void>> Function(String uid) writeProfile,
  }) async {
    emails.add(email);
    if (refusal case final failure?) return Result.failure(failure);
    const uid = 'new-uid';
    return (await writeProfile(
      uid,
    )).map((_) => ProvisionedAccount(uid: uid, setupEmailSent: setupEmailSent));
  }
}

class FakeFileDownloadService implements FileDownloadService {
  final saved = <({String fileName, String contents})>[];

  @override
  Future<Result<void>> saveText({
    required String fileName,
    required String contents,
    String mimeType = 'text/csv',
  }) async {
    saved.add((fileName: fileName, contents: contents));
    return const Result.success(null);
  }
}
