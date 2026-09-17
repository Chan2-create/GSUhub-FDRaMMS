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

/// Translates a caught [AppException] into its corresponding [Failure].
Failure failureFromException(AppException exception) => switch (exception) {
  NetworkException() => NetworkFailure(exception.message),
  ServerException() => ServerFailure(exception.message),
  PermissionException() => PermissionFailure(exception.message),
  NotFoundException() => NotFoundFailure(exception.message),
  ValidationException() => ValidationFailure(exception.message),
  UnknownException() => UnknownFailure(exception.message),
};
