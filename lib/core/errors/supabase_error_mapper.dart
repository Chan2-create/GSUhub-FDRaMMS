import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../services/supabase/supabase_session.dart';
import 'failures.dart';

/// Translates Supabase's errors into the typed [Failure] hierarchy the
/// rest of the app understands — the Supabase half of the boundary
/// [FirebaseErrorMapper] keeps for Firebase. No Postgrest or Storage
/// exception may leave `core/services/` or `data/repositories/`.
///
/// The database's own functions raise with SQLSTATE `PTxxx`, which the API
/// turns into HTTP status xxx (supabase/migrations): PT403 for "not yours",
/// PT404 for "not there", PT409 and PT422 for a request the data refuses.
/// Their messages are written for the person using the app, so they are
/// shown as they come.
abstract final class SupabaseErrorMapper {
  static const _offline = NetworkFailure(
    'Cannot reach the server. Check your internet connection and try '
    'again.',
  );
  static const _denied = PermissionFailure(
    'You do not have permission to perform this action.',
  );
  static const _signedOut = PermissionFailure(
    'Your session has expired. Please sign in again.',
  );

  static Failure map(Object error) {
    if (error is TimeoutException) {
      return const NetworkFailure(
        'The request timed out. Check your internet connection and try '
        'again.',
      );
    }
    if (error is SupabaseSessionException) {
      return error.rejected ? _signedOut : _offline;
    }
    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is StorageException) return _fromStorage(error);
    if (error is RealtimeSubscribeException) return _offline;
    if (error is http.ClientException) return _offline;
    return UnknownFailure('Something went wrong. ($error)');
  }

  /// Whether a failed operation is worth retrying: only transient,
  /// server-side conditions. A refusal fails the same way every time.
  static bool isRetryable(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }
    if (error is SupabaseSessionException) return !error.rejected;
    if (error is PostgrestException) {
      return _transientCodes.contains(error.code);
    }
    if (error is StorageException) {
      final status = int.tryParse(error.statusCode ?? '');
      return status == null
          ? _isTransportError(error)
          : status >= 500 && status != 501;
    }
    return false;
  }

  /// Serialization failures, deadlocks, timeouts, an unreachable
  /// database, and the gateway's own 5xx.
  static const _transientCodes = {
    '40001',
    '40P01',
    '57014',
    '08000',
    '08003',
    '08006',
    'PGRST000',
    'PGRST001',
    'PGRST002',
    'PGRST003',
    '500',
    '502',
    '503',
    '504',
  };

  static Failure _fromPostgrest(PostgrestException error) {
    final code = error.code ?? '';
    return switch (code) {
      'PT403' => PermissionFailure(error.message),
      'PT404' => NotFoundFailure(error.message),
      'PT409' || 'PT422' || 'P0001' => ValidationFailure(error.message),
      // Row level security, or a table the caller has no grant on.
      '42501' => _denied,
      // The access token is missing, malformed or expired.
      'PGRST301' || 'PGRST302' || 'PGRST303' || '401' => _signedOut,
      // `.single()` found nothing.
      'PGRST116' => const NotFoundFailure(
        'The requested record no longer exists.',
      ),
      '23505' => const ValidationFailure('That record already exists.'),
      '23503' => const ValidationFailure(
        'That refers to a record that no longer exists.',
      ),
      '23502' || '23514' || '22P02' || '22023' || '22001' =>
        const ValidationFailure('Some of the details entered are not valid.'),
      _ when _transientCodes.contains(code) => _offline,
      _ => ServerFailure(error.message),
    };
  }

  static Failure _fromStorage(StorageException error) {
    if (_isTransportError(error)) return _offline;
    final message = error.message.toLowerCase();
    if (message.contains('row-level security')) return _denied;
    if (message.contains('mime')) {
      return const ValidationFailure('Only photos can be uploaded.');
    }
    if (message.contains('maximum allowed size') ||
        message.contains('too large')) {
      return const ValidationFailure('That photo is larger than 10 MB.');
    }
    return switch (error.statusCode) {
      '401' => _signedOut,
      '403' => _denied,
      '404' => const NotFoundFailure('That photo no longer exists.'),
      '409' => const ValidationFailure(
        'A photo with that name already exists.',
      ),
      '413' => const ValidationFailure('That photo is larger than 10 MB.'),
      '415' => const ValidationFailure('Only photos can be uploaded.'),
      _ => ServerFailure(error.message),
    };
  }

  /// Storage reports a failed connection with the exception's type name
  /// as its status code.
  static bool _isTransportError(StorageException error) {
    final status = error.statusCode ?? '';
    return status.contains('ClientException') ||
        status.contains('SocketException') ||
        status.contains('TimeoutException');
  }
}
