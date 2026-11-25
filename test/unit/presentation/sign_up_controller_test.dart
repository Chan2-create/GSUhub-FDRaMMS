import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/di/repository_providers.dart';
import 'package:gsuhub/core/di/service_providers.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/auth/presentation/sign_up_controller.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';

import '../../support/fake_admin_backend.dart';

/// Self-registration (Objective 3.A): what the form refuses, and that a
/// complete one creates an account awaiting approval in the role chosen,
/// Faculty or Utility (2026-11-26) — never an active account, never an
/// administrator. No department is asked for.
void main() {
  late FakeAuthService auth;
  late FakeUserRepository users;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthService();
    users = FakeUserRepository(personnel: const Result.success(<AppUser>[]));
    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(users),
      ],
    );
    addTearDown(container.dispose);
  });

  SignUpController controller() =>
      container.read(signUpControllerProvider.notifier);

  Future<bool> register({
    String fullName = '  Liza Mae Tan ',
    String email = ' Liza.Tan@DORSU.edu.ph ',
    String password = 'Horse#Bat12',
    String? confirm,
    UserRole? role = UserRole.requestor,
    String contactNumber = '',
    bool acceptedTerms = true,
  }) => controller().register(
    fullName: fullName,
    email: email,
    password: password,
    confirmPassword: confirm ?? password,
    role: role,
    contactNumber: contactNumber,
    acceptedTerms: acceptedTerms,
  );

  group('validate', () {
    test('an empty form names every required field', () {
      expect(
        SignUpController.validate(
          fullName: ' ',
          email: '',
          password: '',
          confirmPassword: '',
        ).keys,
        unorderedEquals({
          SignUpField.fullName,
          SignUpField.email,
          SignUpField.role,
          SignUpField.password,
          SignUpField.confirmPassword,
          SignUpField.terms,
        }),
      );
    });

    test('Faculty or Utility must be chosen, and nothing else', () {
      Map<SignUpField, String> errors(UserRole? role) =>
          SignUpController.validate(
            fullName: 'Liza Mae Tan',
            email: 'liza.tan@dorsu.edu.ph',
            password: 'Horse#Bat12',
            confirmPassword: 'Horse#Bat12',
            role: role,
            acceptedTerms: true,
          );
      expect(errors(null), {SignUpField.role: 'Choose Faculty or Utility.'});
      expect(errors(UserRole.admin), {
        SignUpField.role: 'Choose Faculty or Utility.',
      });
      expect(errors(UserRole.requestor), isEmpty);
      expect(errors(UserRole.maintenancePersonnel), isEmpty);
    });

    test('a mobile number, when given, is a Philippine one', () {
      final errors = SignUpController.validate(
        fullName: 'Liza Mae Tan',
        email: 'liza.tan@dorsu.edu.ph',
        password: 'Horse#Bat12',
        confirmPassword: 'Horse#Bat12',
        contactNumber: '12345',
        role: UserRole.requestor,
        acceptedTerms: true,
      );
      expect(errors.keys, [SignUpField.contactNumber]);
    });

    test('a password must meet every requirement', () {
      for (final (password, missing) in [
        ('Horsebat12', 'one special character'),
        ('Horse-bat12', 'one special character'),
        ('horse#bat12', 'one uppercase letter'),
        ('HORSE#BAT12', 'one lowercase letter'),
        ('Horse#Batty', 'one number'),
        ('Ho#1', '8–12 characters'),
        ('Horse#Bat1234', 'no more than 12 characters'),
        ('Horse #Bat12', 'cannot contain spaces'),
      ]) {
        expect(
          SignUpController.validate(
            fullName: 'Liza Mae Tan',
            email: 'liza.tan@dorsu.edu.ph',
            password: password,
            confirmPassword: password,
          )[SignUpField.password],
          contains(missing),
          reason: password,
        );
      }
    });

    test('refuses a malformed email, a short password and a mismatch', () {
      final errors = SignUpController.validate(
        fullName: 'Liza Mae Tan',
        email: 'liza.tan@',
        password: 'short',
        confirmPassword: 'different',
        role: UserRole.requestor,
        acceptedTerms: true,
      );

      expect(errors.keys, {
        SignUpField.email,
        SignUpField.password,
        SignUpField.confirmPassword,
      });
      expect(errors[SignUpField.password], contains('8–12 characters'));
      expect(errors[SignUpField.confirmPassword], contains('do not match'));
    });

    test('accepts any valid address, not only the university domain', () {
      expect(
        SignUpController.validate(
          fullName: 'Liza Mae Tan',
          email: 'liza.tan@gmail.com',
          password: 'Horse#Bat12',
          confirmPassword: 'Horse#Bat12',
          role: UserRole.requestor,
          acceptedTerms: true,
        ),
        isEmpty,
      );
    });

    test('the terms must be accepted (2026-11-25)', () {
      Map<SignUpField, String> errors({required bool accepted}) =>
          SignUpController.validate(
            fullName: 'Liza Mae Tan',
            email: 'liza.tan@dorsu.edu.ph',
            password: 'Horse#Bat12',
            confirmPassword: 'Horse#Bat12',
            role: UserRole.requestor,
            acceptedTerms: accepted,
          );
      expect(errors(accepted: false), {
        SignUpField.terms:
            'Accept the Terms of Use and Privacy Notice to create an account.',
      });
      expect(errors(accepted: true), isEmpty);
    });
  });

  group('register', () {
    test('creates a pending requestor under the lower-cased address', () async {
      expect(await register(), isTrue);

      expect(auth.registered, ['liza.tan@dorsu.edu.ph']);
      final profile = users.created.single;
      expect(profile.fullName, 'Liza Mae Tan');
      expect(profile.email, 'liza.tan@dorsu.edu.ph');
      expect(profile.role, UserRole.requestor);
      expect(profile.accountStatus, AccountStatus.pending);
      expect(profile.department, isNull, reason: 'no department is asked for');
      expect(profile.contactNumber, isNull);
      expect(container.read(signUpControllerProvider).errorMessage, isNull);
    });

    test('Utility signs up a maintenance account, still awaiting approval '
        '(2026-11-26)', () async {
      expect(await register(role: UserRole.maintenancePersonnel), isTrue);
      final profile = users.created.single;
      expect(profile.role, UserRole.maintenancePersonnel);
      expect(profile.accountStatus, AccountStatus.pending);
    });

    test('without a role chosen, nothing is sent', () async {
      expect(await register(role: null), isFalse);
      expect(auth.registered, isEmpty);
      expect(container.read(signUpControllerProvider).errors.keys, [
        SignUpField.role,
      ]);
    });

    test('a mobile number is saved without its spaces and dashes', () async {
      expect(await register(contactNumber: '+63 917-123 4567'), isTrue);
      expect(users.created.single.contactNumber, '+639171234567');
    });

    test('an incomplete form sends nothing', () async {
      expect(await register(confirm: 'something else'), isFalse);

      expect(auth.registered, isEmpty);
      expect(container.read(signUpControllerProvider).errors.keys, [
        SignUpField.confirmPassword,
      ]);
    });

    test("the service's refusal is shown above the form", () async {
      auth.registerResult = const Result.failure(
        ValidationFailure('An account already exists for that email address.'),
      );

      expect(await register(), isFalse);

      expect(users.created, isEmpty);
      expect(
        container.read(signUpControllerProvider).errorMessage,
        'An account already exists for that email address.',
      );
    });

    test('a profile that cannot be saved fails the sign-up', () async {
      users = FakeUserRepository(
        personnel: const Result.success(<AppUser>[]),
        writeResult: const Result.failure(
          NetworkFailure('Cannot reach the server.'),
        ),
      );
      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          userRepositoryProvider.overrideWithValue(users),
        ],
      );
      addTearDown(container.dispose);

      expect(await register(), isFalse);
      expect(
        container.read(signUpControllerProvider).errorMessage,
        'Cannot reach the server.',
      );
    });

    test('correcting a field clears its error', () async {
      await register(confirm: 'something else');

      controller().clearError(SignUpField.confirmPassword);

      expect(container.read(signUpControllerProvider).errors, isEmpty);
    });
  });
}
