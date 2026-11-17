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

/// Faculty and staff self-registration (Objective 3.A): what the form
/// refuses, and that a complete one creates a requestor awaiting approval
/// — never an active account, never another role.
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
    String password = 'Correct-horse1',
    String? confirm,
    String? department = 'Faculty of Business and Management',
    String contactNumber = '',
    bool departmentRequired = true,
  }) => controller().register(
    fullName: fullName,
    email: email,
    password: password,
    confirmPassword: confirm ?? password,
    department: department,
    contactNumber: contactNumber,
    departmentRequired: departmentRequired,
  );

  group('validate', () {
    test('an empty form names every required field', () {
      expect(
        SignUpController.validate(
          fullName: ' ',
          email: '',
          password: '',
          confirmPassword: '',
          departmentRequired: true,
        ).keys,
        unorderedEquals({
          SignUpField.fullName,
          SignUpField.email,
          SignUpField.department,
          SignUpField.password,
          SignUpField.confirmPassword,
        }),
      );
    });

    test('a department is required only while the list has any', () {
      Map<SignUpField, String> errors({required bool required}) =>
          SignUpController.validate(
            fullName: 'Liza Mae Tan',
            email: 'liza.tan@dorsu.edu.ph',
            password: 'Correct-horse1',
            confirmPassword: 'Correct-horse1',
            departmentRequired: required,
          );
      expect(errors(required: true), {
        SignUpField.department: 'Choose your department or faculty.',
      });
      expect(errors(required: false), isEmpty);
    });

    test('a mobile number, when given, is a Philippine one', () {
      final errors = SignUpController.validate(
        fullName: 'Liza Mae Tan',
        email: 'liza.tan@dorsu.edu.ph',
        password: 'Correct-horse1',
        confirmPassword: 'Correct-horse1',
        contactNumber: '12345',
      );
      expect(errors.keys, [SignUpField.contactNumber]);
    });

    test('a password must meet every requirement', () {
      for (final (password, missing) in [
        ('Correcthorse1', 'a special character'),
        ('correct-horse1', 'an uppercase letter'),
        ('CORRECT-HORSE1', 'a lowercase letter'),
        ('Correct-horse', 'a number'),
        ('Co-1', 'at least 8 characters'),
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
      );

      expect(errors.keys, {
        SignUpField.email,
        SignUpField.password,
        SignUpField.confirmPassword,
      });
      expect(errors[SignUpField.password], contains('at least 8 characters'));
      expect(errors[SignUpField.confirmPassword], contains('do not match'));
    });

    test('accepts any valid address, not only the university domain', () {
      expect(
        SignUpController.validate(
          fullName: 'Liza Mae Tan',
          email: 'liza.tan@gmail.com',
          password: 'Correct-horse1',
          confirmPassword: 'Correct-horse1',
        ),
        isEmpty,
      );
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
      expect(profile.department, 'Faculty of Business and Management');
      expect(profile.contactNumber, isNull);
      expect(container.read(signUpControllerProvider).errorMessage, isNull);
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
