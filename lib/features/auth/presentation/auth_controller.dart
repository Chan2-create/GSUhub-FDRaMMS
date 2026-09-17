import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/service_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/auth_service.dart';

/// State of the login form.
@immutable
class LoginState {
  const LoginState({
    this.isSubmitting = false,
    this.errorMessage,
    this.infoMessage,
  });

  final bool isSubmitting;

  /// Shown as an inline banner above the form.
  final String? errorMessage;

  /// Confirmation copy, e.g. after a password-reset email is sent.
  final String? infoMessage;

  LoginState copyWith({
    bool? isSubmitting,
    String? errorMessage,
    String? infoMessage,
  }) => LoginState(
    isSubmitting: isSubmitting ?? this.isSubmitting,
    errorMessage: errorMessage,
    infoMessage: infoMessage,
  );
}

/// Drives the login form.
///
/// Talks only to [AuthService] — the Shared Backend Contract (1.A, rule 1)
/// forbids a widget or controller from touching Firebase Auth directly,
/// and this is the class that would otherwise be tempted to.
class AuthController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  AuthService get _auth => ref.read(authServiceProvider);

  /// Signs in. Returns the authenticated user on success, or null — with
  /// [LoginState.errorMessage] set — on failure.
  ///
  /// The caller navigates; this deliberately does not, so the same
  /// controller works regardless of where the user was headed.
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    state = const LoginState(isSubmitting: true);

    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return result.fold(
      (user) {
        state = const LoginState();
        return user;
      },
      (failure) {
        state = LoginState(errorMessage: _messageFor(failure));
        return null;
      },
    );
  }

  /// Sends a password-reset email.
  ///
  /// Reports success even when the address has no account. Confirming
  /// which emails exist would turn this form into an account-enumeration
  /// oracle, and `FirebaseErrorMapper` already keeps sign-in errors vague
  /// for the same reason.
  Future<void> sendPasswordReset(String email) async {
    state = const LoginState(isSubmitting: true);

    final result = await _auth.sendPasswordResetEmail(email: email);

    state = result.fold(
      (_) => const LoginState(
        infoMessage:
            'If an account exists for that address, a password reset '
            'link is on its way.',
      ),
      (failure) => switch (failure) {
        // A network failure genuinely means "we did not send it", so the
        // user needs to know. Anything else is kept indistinguishable
        // from success.
        NetworkFailure() => LoginState(errorMessage: failure.message),
        ValidationFailure() => LoginState(errorMessage: failure.message),
        _ => const LoginState(
          infoMessage:
              'If an account exists for that address, a password reset '
              'link is on its way.',
        ),
      },
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = const LoginState();
  }

  void clearMessages() => state = LoginState(isSubmitting: state.isSubmitting);

  /// Failures already carry non-leaky, user-facing copy from
  /// `FirebaseErrorMapper`; this only distinguishes the deactivated-account
  /// case, which the service reports as a permission failure with its own
  /// wording.
  static String _messageFor(Failure failure) => failure.message;
}

final authControllerProvider = NotifierProvider<AuthController, LoginState>(
  AuthController.new,
);
