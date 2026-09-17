import '../errors/failures.dart';

/// Outcome of an operation that can fail in an expected way, as an
/// alternative to throwing. Repositories return `Result<T>` rather than
/// `Future<T>` so callers are compile-time forced to handle failure —
/// see [fold] and [when].
sealed class Result<T> {
  const Result();

  /// Wraps a successful [value].
  const factory Result.success(T value) = Success<T>;

  /// Wraps a [failure].
  const factory Result.failure(Failure failure) = Error<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Error<T>;

  /// Reduces this [Result] to a single value of type [R] by invoking
  /// exactly one of [onSuccess] or [onFailure].
  R fold<R>(
    R Function(T value) onSuccess,
    R Function(Failure failure) onFailure,
  ) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Error<T>(:final failure) => onFailure(failure),
  };

  /// Transforms a successful value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success<T>(:final value) => Result<R>.success(transform(value)),
    Error<T>(:final failure) => Result<R>.failure(failure),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class Error<T> extends Result<T> {
  const Error(this.failure);

  final Failure failure;
}
