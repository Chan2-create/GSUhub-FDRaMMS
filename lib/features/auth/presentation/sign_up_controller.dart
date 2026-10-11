import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/di/service_providers.dart';
import '../../../core/enums/account_status.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/utils/result.dart';
import '../../user_management/data/models/app_user.dart';
import 'login_screen.dart' show validateEmail;

/// The sign-up form's fields, by name, for its per-field errors.
enum SignUpField { fullName, email, password, confirmPassword }

/// What the sign-up form holds besides its text: whether it is sending,
/// the inline errors, and a failure from the server.
@immutable
class SignUpState {
  const SignUpState({
    this.isSubmitting = false,
    this.errors = const {},
    this.errorMessage,
  });

  final bool isSubmitting;
  final Map<SignUpField, String> errors;

  /// A failure from the server, shown above the form.
  final String? errorMessage;
}

/// Self-registration for faculty and staff (Objective 3.A, Figma
/// `194:455`).
///
/// Creates the account through [AuthService.register] — the same service
/// that signs everyone in — and saves a `users` profile as a requestor
/// awaiting approval. It leaves nobody signed in: an administrator
/// approves the account from User Accounts before it can be used (§1.5
/// limits GSUhub to authorized faculty and staff).
class SignUpController extends Notifier<SignUpState> {
  @override
  SignUpState build() => const SignUpState();

  /// The shortest password accepted. Firebase allows six; eight is the
  /// floor most guidance now gives, and the account guards reports filed
  /// in the person's name.
  static const int minPasswordLength = 8;

  /// The longest name accepted, matching the security rules.
  static const int maxNameLength = 120;

  /// Checks the form, and when it is complete creates the account. Returns
  /// true when the account was created.
  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final errors = validate(
      fullName: fullName,
      email: email,
      password: password,
      confirmPassword: confirmPassword,
    );
    if (errors.isNotEmpty) {
      state = SignUpState(errors: errors);
      return false;
    }

    state = const SignUpState(isSubmitting: true);

    // Lower-cased so the stored address matches the one Firebase signs in
    // with, which the rules compare it against.
    final address = email.trim().toLowerCase();
    final name = fullName.trim();
    final users = ref.read(userRepositoryProvider);

    final result = await ref
        .read(authServiceProvider)
        .register(
          email: address,
          password: password,
          writeProfile: (uid) {
            final now = DateTime.now();
            return users.createSelfRegistration(
              AppUser(
                id: uid,
                fullName: name,
                email: address,
                role: UserRole.requestor,
                accountStatus: AccountStatus.pending,
                createdAt: now,
                updatedAt: now,
              ),
            );
          },
        );

    switch (result) {
      case Success():
        state = const SignUpState();
        return true;
      case Error(:final failure):
        state = SignUpState(errorMessage: failure.message);
        return false;
    }
  }

  /// Clears one field's error once the person starts correcting it.
  void clearError(SignUpField field) {
    if (!state.errors.containsKey(field)) return;
    state = SignUpState(
      errors: {...state.errors}..remove(field),
      errorMessage: state.errorMessage,
    );
  }

  /// Every problem with the form, by field. Empty when it can be sent.
  static Map<SignUpField, String> validate({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) {
    final name = fullName.trim();
    return {
      if (name.isEmpty)
        SignUpField.fullName: 'Enter your full name.'
      else if (name.length > maxNameLength)
        SignUpField.fullName:
            'Keep your name to $maxNameLength characters or fewer.',
      SignUpField.email: ?validateEmail(email),
      if (password.isEmpty)
        SignUpField.password: 'Choose a password.'
      else if (password.length < minPasswordLength)
        SignUpField.password: 'Use at least $minPasswordLength characters.',
      if (confirmPassword.isEmpty)
        SignUpField.confirmPassword: 'Enter your password again.'
      else if (confirmPassword != password)
        SignUpField.confirmPassword: 'The passwords do not match.',
    };
  }
}

final signUpControllerProvider =
    NotifierProvider<SignUpController, SignUpState>(SignUpController.new);
