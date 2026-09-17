import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import 'failures.dart';

/// Translates Firebase's untyped, string-coded errors into the typed
/// [Failure] hierarchy the rest of the app understands.
///
/// This is the boundary the Shared Backend Contract depends on: a
/// `FirebaseException` must never escape `core/services/` or
/// `data/repositories/`, because the moment one does, every caller above
/// is coupled to Firebase and the abstraction stops being worth anything.
abstract final class FirebaseErrorMapper {
  /// Maps any caught [error] to a [Failure].
  ///
  /// Handles [FirebaseException] by code, [TimeoutException] from the
  /// service-level timeout, and falls back to [UnknownFailure] for
  /// anything unrecognized — an unmapped error is still a handled error.
  static Failure map(Object error) {
    if (error is TimeoutException) {
      return const NetworkFailure(
        'The request timed out. Check your internet connection and try '
        'again.',
      );
    }
    if (error is FirebaseException) {
      return _fromFirebaseException(error);
    }
    return UnknownFailure('Something went wrong. ($error)');
  }

  /// Whether a failed operation is worth retrying.
  ///
  /// Only transient, server-side conditions qualify. A permission denial
  /// or a missing document will fail identically on every attempt, so
  /// retrying those just delays the error the user needs to see.
  static bool isRetryable(Object error) {
    if (error is TimeoutException) return true;
    if (error is! FirebaseException) return false;
    return const {
      'unavailable',
      'deadline-exceeded',
      'internal',
      'resource-exhausted',
      'aborted',
      'network-request-failed',
      'retry-limit-exceeded',
    }.contains(error.code);
  }

  static Failure _fromFirebaseException(FirebaseException error) {
    final message = error.message ?? error.code;

    return switch (error.code) {
      // --- connectivity ---
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => const NetworkFailure(
        'Cannot reach the server. Check your internet connection and try '
        'again.',
      ),

      // --- authorization ---
      'permission-denied' ||
      'unauthorized' ||
      'insufficient-permission' => const PermissionFailure(
        'You do not have permission to perform this action.',
      ),
      'unauthenticated' => const PermissionFailure(
        'Your session has expired. Please sign in again.',
      ),

      // --- not found ---
      'not-found' || 'object-not-found' => const NotFoundFailure(
        'The requested record no longer exists.',
      ),

      // --- auth: credentials ---
      'invalid-email' => const ValidationFailure(
        'That email address is not valid.',
      ),
      'user-disabled' => const PermissionFailure(
        'This account has been deactivated. Contact the GSU administrator.',
      ),
      // Modern Firebase Auth returns the deliberately vague
      // `invalid-credential` instead of distinguishing "no such user" from
      // "wrong password", so that a sign-in form cannot be used to
      // enumerate which email addresses have accounts. The message below
      // preserves that ambiguity on purpose.
      'invalid-credential' || 'user-not-found' || 'wrong-password' =>
        const PermissionFailure('Incorrect email or password.'),
      'email-already-in-use' => const ValidationFailure(
        'An account already exists for that email address.',
      ),
      'weak-password' => const ValidationFailure(
        'That password is too weak. Use at least 6 characters.',
      ),
      'too-many-requests' => const ServerFailure(
        'Too many attempts. Please wait a moment and try again.',
      ),
      'operation-not-allowed' => const ServerFailure(
        'This sign-in method is not enabled for the project.',
      ),
      'requires-recent-login' => const PermissionFailure(
        'Please sign in again to complete this action.',
      ),

      // --- validation ---
      'invalid-argument' ||
      'failed-precondition' ||
      'out-of-range' => ValidationFailure(message),
      'already-exists' => const ValidationFailure(
        'That record already exists.',
      ),

      // --- storage ---
      'quota-exceeded' => const ServerFailure(
        'Storage quota exceeded. Contact the GSU administrator.',
      ),
      'canceled' => const UnknownFailure('The operation was cancelled.'),

      // --- server ---
      'internal' || 'data-loss' || 'unknown' => ServerFailure(message),
      'resource-exhausted' => const ServerFailure(
        'The service is temporarily overloaded. Please try again shortly.',
      ),

      _ => UnknownFailure(message),
    };
  }
}
