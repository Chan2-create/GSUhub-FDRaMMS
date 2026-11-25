import '../config/session_policy.dart';
import 'exceptions.dart';

/// User-facing representation of a failed operation, returned by
/// repositories via `Result<T>` (see `../utils/result.dart`) instead of
/// throwing. Mirrors [AppException] one-to-one so repository
/// implementations can translate a caught exception into a [Failure] with a
/// single mapping (see [Failure.fromException]).
sealed class Failure {
  const Failure(this.message);

  /// Human-readable, non-sensitive description suitable for display.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

/// The database is behind this version of the app (2026-11-26): a table
/// or function the app asks for is not there, because its migration has
/// not been applied to the project yet. PostgREST says so as a
/// "schema cache" error, which means nothing to the person using the app;
/// this says what to do instead.
final class DatabaseUpdateFailure extends ServerFailure {
  const DatabaseUpdateFailure([super.message = defaultMessage]);

  static const String defaultMessage =
      'This part of GSUhub needs a database update that has not been '
      'applied yet. Ask the system administrator to apply the latest '
      'update (npx supabase db push), then try again.';
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

/// The sign-in ended, and the database said so (PT401): idle for longer
/// than a session allows, or (2026-11-17) the account deactivated or its
/// role changed. `SessionWatch` signs the person out on it, wherever it
/// surfaced, and the sign-in page says [reason].
final class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure(
    super.message, {
    this.reason = SessionEndReason.idle,
  });

  final SessionEndReason reason;
}

/// Translates a caught [AppException] into its corresponding [Failure].
Failure failureFromException(AppException exception) => switch (exception) {
  NetworkException() => NetworkFailure(exception.message),
  ServerException() => ServerFailure(exception.message),
  PermissionException() => PermissionFailure(exception.message),
  NotFoundException() => NotFoundFailure(exception.message),
  ValidationException() => ValidationFailure(exception.message),
  UnknownException() => UnknownFailure(exception.message),
};
