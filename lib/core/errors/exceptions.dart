/// Exceptions thrown by data sources (Firestore, Storage, platform APIs).
///
/// These are caught at the repository boundary and translated into
/// [Failure]s (see `failures.dart`) for the rest of the app to consume —
/// UI and business-logic layers should never catch these directly.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Human-readable, non-sensitive description of what went wrong.
  final String message;

  /// The underlying error/exception this one was translated from, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// No network connectivity, or a request timed out.
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}

/// A backend (Firestore/Storage/Functions) call failed on the server side.
final class ServerException extends AppException {
  const ServerException(super.message, {super.cause});
}

/// The current user is not permitted to perform the requested operation —
/// typically a Firestore Security Rules denial.
final class PermissionException extends AppException {
  const PermissionException(super.message, {super.cause});
}

/// The requested document/resource does not exist.
final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause});
}

/// Input failed local validation before a request was even made.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

/// A caught error did not match any of the more specific exception types
/// above.
final class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause});
}
