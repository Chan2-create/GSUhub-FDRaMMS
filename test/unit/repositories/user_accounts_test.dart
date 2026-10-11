import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/personnel_availability.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/audit/data/models/audit_actor.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';

import '../../support/fake_firestore_repositories.dart';

/// Account management (Objective 2.C): every change audited, and the two
/// changes that could lock the system out refused inside the transaction.
void main() {
  late FirestoreHarness harness;

  const admin = FirestoreHarness.admin;

  setUp(() => harness = FirestoreHarness());

  AppUser technician({
    String id = 'personnel-1',
    String fullName = 'Juan Luna',
    UserRole role = UserRole.maintenancePersonnel,
    int activeTaskCount = 0,
    DamageCategory? specialization = DamageCategory.plumbing,
    PersonnelAvailability? availability = PersonnelAvailability.available,
    String? department = 'General Services Unit',
  }) => AppUser(
    id: id,
    fullName: fullName,
    email: '$id@dorsu.edu.ph',
    role: role,
    accountStatus: AccountStatus.active,
    department: department,
    specialization: specialization,
    availability: availability,
    activeTaskCount: activeTaskCount,
    createdAt: DateTime.utc(2026, 9),
    updatedAt: DateTime.utc(2026, 9),
  );

  Future<void> store(AppUser user) => harness.firestore
      .collection(FirestorePaths.users)
      .doc(user.id)
      .set(user.toFirestore());

  Failure failureOf(Result<void> result) =>
      result.fold((_) => fail('expected a failure'), (failure) => failure);

  group('createAccount', () {
    test('saves the profile and its audit entry together', () async {
      final result = await harness.users.createAccount(
        user: technician(),
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final saved = await harness.doc(FirestorePaths.users, 'personnel-1');
      expect(saved['fullName'], 'Juan Luna');
      expect(saved['role'], 'maintenancePersonnel');
      expect(isTimestamp(saved['createdAt']), isTrue);

      final audit = await harness.auditEntries();
      expect(audit, hasLength(1));
      expect(audit.single['action'], 'created');
      expect(audit.single['entityId'], 'personnel-1');
      expect(audit.single['actorId'], admin.id);
    });

    test('refuses to overwrite a profile that already exists', () async {
      await store(technician());

      final result = await harness.users.createAccount(
        user: technician(fullName: 'Someone Else'),
        actor: admin,
      );

      expect(failureOf(result), isA<ValidationFailure>());
      final stored = await harness.doc(FirestorePaths.users, 'personnel-1');
      expect(stored['fullName'], 'Juan Luna');
      expect(await harness.auditEntries(), isEmpty);
    });
  });

  group('updateAccount', () {
    test('writes only what changed, and audits it', () async {
      await store(technician());

      final result = await harness.users.updateAccount(
        updated: technician(department: 'Physical Plant Division'),
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final stored = await harness.doc(FirestorePaths.users, 'personnel-1');
      expect(stored['department'], 'Physical Plant Division');

      final audit = await harness.auditEntries();
      expect(audit.single['action'], 'updated');
      final changes = audit.single['changes'] as Map<String, dynamic>;
      expect(changes.keys, ['department']);
    });

    test('an edit that changes nothing writes nothing', () async {
      await store(technician());

      final result = await harness.users.updateAccount(
        updated: technician(),
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      expect(await harness.auditEntries(), isEmpty);
    });

    test('an administrator cannot change their own role', () async {
      // The last administrator demoting themselves would leave nobody able
      // to manage accounts.
      await store(
        technician(
          id: admin.id,
          role: UserRole.admin,
          specialization: null,
          availability: null,
        ),
      );

      final result = await harness.users.updateAccount(
        updated: technician(
          id: admin.id,
          role: UserRole.requestor,
          specialization: null,
          availability: null,
        ),
        actor: admin,
      );

      expect(failureOf(result).message, contains('your own role'));
      final stored = await harness.doc(FirestorePaths.users, admin.id);
      expect(stored['role'], 'admin');
    });

    test('refuses a role change for someone still holding work', () async {
      await store(technician(activeTaskCount: 2));

      final result = await harness.users.updateAccount(
        updated: technician(activeTaskCount: 2, role: UserRole.requestor),
        actor: admin,
      );

      final message = failureOf(result).message;
      expect(message, contains('2 active work orders'));
    });

    test('leaving maintenance clears the trade and leave status', () async {
      await store(technician());

      final result = await harness.users.updateAccount(
        updated: technician(role: UserRole.admin),
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final stored = await harness.doc(FirestorePaths.users, 'personnel-1');
      expect(stored['role'], 'admin');
      expect(stored['specialization'], isNull);
      expect(stored['availability'], isNull);

      final audit = await harness.auditEntries();
      expect(audit.single['description'], contains('to Administrator'));
    });
  });

  group('setAccountStatus', () {
    test('deactivates another account and audits it', () async {
      await store(technician());

      final result = await harness.users.setAccountStatus(
        'personnel-1',
        AccountStatus.inactive,
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      final stored = await harness.doc(FirestorePaths.users, 'personnel-1');
      expect(stored['accountStatus'], 'inactive');

      final audit = await harness.auditEntries();
      expect(audit.single['action'], 'statusChanged');
      expect(audit.single['changes'], {'from': 'active', 'to': 'inactive'});
    });

    test('an administrator cannot deactivate their own account', () async {
      await store(
        technician(
          id: admin.id,
          role: UserRole.admin,
          specialization: null,
          availability: null,
        ),
      );

      final result = await harness.users.setAccountStatus(
        admin.id,
        AccountStatus.inactive,
        actor: const AuditActor(id: 'admin-1', name: 'Ramon Dela Cruz'),
      );

      expect(failureOf(result).message, contains('your own account'));
      final stored = await harness.doc(FirestorePaths.users, admin.id);
      expect(stored['accountStatus'], 'active');
    });

    test(
      'approving a sign-up request activates it, worded as approval',
      () async {
        await store(
          technician(
            id: 'faculty-9',
            role: UserRole.requestor,
            specialization: null,
            availability: null,
          ).copyWith(accountStatus: AccountStatus.pending),
        );

        final result = await harness.users.setAccountStatus(
          'faculty-9',
          AccountStatus.active,
          actor: admin,
        );

        expect(result.isSuccess, isTrue);
        final stored = await harness.doc(FirestorePaths.users, 'faculty-9');
        expect(stored['accountStatus'], 'active');
        final audit = await harness.auditEntries();
        expect(audit.single['description'], startsWith('Approved the account'));
        expect(audit.single['changes'], {'from': 'pending', 'to': 'active'});
      },
    );

    test('declining a sign-up request leaves it inactive', () async {
      await store(
        technician(
          id: 'faculty-9',
          role: UserRole.requestor,
          specialization: null,
          availability: null,
        ).copyWith(accountStatus: AccountStatus.pending),
      );

      await harness.users.setAccountStatus(
        'faculty-9',
        AccountStatus.inactive,
        actor: admin,
      );

      final stored = await harness.doc(FirestorePaths.users, 'faculty-9');
      expect(stored['accountStatus'], 'inactive');
      final audit = await harness.auditEntries();
      expect(audit.single['description'], startsWith('Declined the account'));
    });

    test('setting the status it already has does nothing', () async {
      await store(technician());

      final result = await harness.users.setAccountStatus(
        'personnel-1',
        AccountStatus.active,
        actor: admin,
      );

      expect(result.isSuccess, isTrue);
      expect(await harness.auditEntries(), isEmpty);
    });
  });

  group('createSelfRegistration', () {
    test(
      'saves a pending requestor with server time and no audit entry',
      () async {
        final result = await harness.users.createSelfRegistration(
          AppUser(
            id: 'new-faculty',
            fullName: 'Liza Mae Tan',
            email: 'liza.tan@dorsu.edu.ph',
            role: UserRole.requestor,
            accountStatus: AccountStatus.pending,
            // A device clock years out: the stored times must not be these.
            createdAt: DateTime.utc(2001),
            updatedAt: DateTime.utc(2001),
          ),
        );

        expect(result.isSuccess, isTrue);
        final stored = await harness.doc(FirestorePaths.users, 'new-faculty');
        expect(stored['role'], 'requestor');
        expect(stored['accountStatus'], 'pending');
        expect(stored['email'], 'liza.tan@dorsu.edu.ph');
        final created = (stored['createdAt'] as dynamic).toDate() as DateTime;
        expect(created.year, isNot(2001));
        // The rules let only an active account write the audit trail; the
        // administrator's approval is what gets recorded.
        expect(await harness.auditEntries(), isEmpty);
      },
    );
  });
}
