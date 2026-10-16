import 'dart:async';

import '../config/app_config.dart';
import '../errors/failures.dart';
import '../utils/result.dart';

/// Wraps backend calls with the project's timeout, retry and error-mapping
/// policy, so every service and repository method gets identical behaviour
/// without repeating the same try/catch fifty times.
///
/// Why this exists rather than letting each method handle its own errors:
/// a single inconsistent `catch` that forgets to map a backend exception
/// leaks the backend's types past the service boundary and quietly breaks
/// the Shared Backend Contract. Funnelling every call through here makes
/// that impossible by construction.
///
/// One per backend: `FirebaseCallGuard` and `SupabaseCallGuard` differ only
/// in how they read their backend's errors.
class CallGuard {
  const CallGuard(
    this._config, {
    required this._map,
    required this._isRetryable,
  });

  final AppConfig _config;
  final Failure Function(Object error) _map;
  final bool Function(Object error) _isRetryable;

  /// Runs [operation], returning [Result.success] or a mapped
  /// [Result.failure].
  ///
  /// Retries transient failures up to [AppConfig.maxRetryAttempts] with a
  /// short exponential backoff. Deterministic failures (permission denied,
  /// not found, validation) return immediately.
  Future<Result<T>> call<T>(Future<T> Function() operation) async {
    var attempt = 0;

    while (true) {
      try {
        final value = await operation().timeout(_config.requestTimeout);
        return Result.success(value);
      } on Object catch (error) {
        final canRetry =
            attempt < _config.maxRetryAttempts && _isRetryable(error);

        if (!canRetry) {
          return Result.failure(_map(error));
        }

        attempt++;
        await Future<void>.delayed(_backoffFor(attempt));
      }
    }
  }

  /// Runs [operation] once, with the timeout and error mapping of [call]
  /// but no retry.
  ///
  /// For calls that are not safe to repeat. Creating an account is one: if
  /// a first attempt timed out after the account was actually made, a retry
  /// fails as "email already in use" and hides the real outcome.
  Future<Result<T>> callOnce<T>(Future<T> Function() operation) async {
    try {
      return Result.success(await operation().timeout(_config.requestTimeout));
    } on Object catch (error) {
      return Result.failure(_map(error));
    }
  }

  /// Wraps a stream so subscribers receive mapped failures instead of raw
  /// backend errors.
  ///
  /// Streams are not retried: live listeners reconnect on their own once
  /// connectivity returns, and layering our own retry on top would produce
  /// duplicate subscriptions.
  Stream<Result<T>> stream<T>(Stream<T> source) => source
      .map<Result<T>>(Result.success)
      .transform(
        StreamTransformer<Result<T>, Result<T>>.fromHandlers(
          // Converts the error into a value on the stream rather than
          // letting it terminate the subscription, so a transient failure
          // does not permanently kill a live listener.
          handleError: (error, stackTrace, sink) =>
              sink.add(Result<T>.failure(_map(error))),
        ),
      );

  /// 200ms, 400ms, 800ms … — short enough that a user on a flaky campus
  /// connection is not left waiting, long enough to outlast a brief blip.
  Duration _backoffFor(int attempt) =>
      Duration(milliseconds: 200 * (1 << (attempt - 1)));
}
