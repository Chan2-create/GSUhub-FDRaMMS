import 'dart:async';

import '../../config/app_config.dart';
import '../../errors/firebase_error_mapper.dart';
import '../../utils/result.dart';

/// Wraps Firebase calls with the project's timeout, retry and
/// error-mapping policy, so every service and repository method gets
/// identical behaviour without repeating the same try/catch fifty times.
///
/// Why this exists rather than letting each method handle its own errors:
/// a single inconsistent `catch` that forgets to map a `FirebaseException`
/// leaks Firebase's types past the service boundary and quietly breaks the
/// Shared Backend Contract. Funnelling every call through here makes that
/// impossible by construction.
class FirebaseCallGuard {
  const FirebaseCallGuard(this._config);

  final AppConfig _config;

  /// Runs [operation], returning [Result.success] or a mapped
  /// [Result.failure].
  ///
  /// Retries transient failures up to [AppConfig.maxRetryAttempts] with a
  /// short exponential backoff. Deterministic failures (permission denied,
  /// not found, validation) return immediately — see
  /// [FirebaseErrorMapper.isRetryable].
  Future<Result<T>> call<T>(Future<T> Function() operation) async {
    var attempt = 0;

    while (true) {
      try {
        final value = await operation().timeout(_config.requestTimeout);
        return Result.success(value);
      } on Object catch (error) {
        final canRetry =
            attempt < _config.maxRetryAttempts &&
            FirebaseErrorMapper.isRetryable(error);

        if (!canRetry) {
          return Result.failure(FirebaseErrorMapper.map(error));
        }

        attempt++;
        await Future<void>.delayed(_backoffFor(attempt));
      }
    }
  }

  /// Wraps a stream so subscribers receive mapped failures instead of raw
  /// Firebase errors.
  ///
  /// Streams are not retried: a Firestore snapshot listener already
  /// reconnects on its own once connectivity returns, and layering our own
  /// retry on top would produce duplicate subscriptions.
  Stream<Result<T>> stream<T>(Stream<T> source) => source
      .map<Result<T>>(Result.success)
      .transform(
        StreamTransformer<Result<T>, Result<T>>.fromHandlers(
          // Converts the error into a value on the stream rather than
          // letting it terminate the subscription, so a transient failure
          // does not permanently kill a live listener.
          handleError: (error, stackTrace, sink) =>
              sink.add(Result<T>.failure(FirebaseErrorMapper.map(error))),
        ),
      );

  /// 200ms, 400ms, 800ms … — short enough that a user on a flaky campus
  /// connection is not left waiting, long enough to outlast a brief blip.
  Duration _backoffFor(int attempt) =>
      Duration(milliseconds: 200 * (1 << (attempt - 1)));
}
