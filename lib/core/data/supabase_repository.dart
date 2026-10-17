import 'dart:math';

import 'package:supabase/supabase.dart';

import '../errors/failures.dart';
import '../services/supabase/supabase_call_guard.dart';
import '../utils/result.dart';
import 'row_snapshot.dart';

/// Shared plumbing for the Supabase repositories (Objective 1), as
/// `FirestoreRepository` was for the Firestore ones.
///
/// Reads go straight to the tables: row level security decides what the
/// caller sees. Writes go through the database's functions
/// (supabase/migrations/*_functions.sql), because app users can read the
/// tables and nothing more. Rows reach the models as [RowSnapshot]s, so
/// every model keeps its one converter.
///
/// Live views are Realtime streams. Realtime takes one filter per
/// subscription, so a view that needs more filters on the one the server
/// applies and the rest in [watchMany]'s callers.
abstract class SupabaseRepository {
  const SupabaseRepository({required this.client, required this.guard});

  final SupabaseClient client;

  final SupabaseCallGuard guard;

  /// One row by id, failing with not-found when there is none or the
  /// caller may not see it.
  Future<Result<T>> getOne<T>({
    required String table,
    required String id,
    required T Function(RowSnapshot) convert,
  }) => guard.call(() async {
    final row = await client.from(table).select().eq('id', id).maybeSingle();
    if (row == null) throw notFound('No $table $id');
    return convert(RowSnapshot.fromRow(row));
  });

  /// One row by id, or null when there is none.
  Future<Result<T?>> getOneOrNull<T>({
    required String table,
    required String id,
    required T Function(RowSnapshot) convert,
  }) => guard.call(() async {
    final row = await client.from(table).select().eq('id', id).maybeSingle();
    return row == null ? null : convert(RowSnapshot.fromRow(row));
  });

  Future<Result<List<T>>> getMany<T>({
    required Future<List<Map<String, dynamic>>> query,
    required T Function(RowSnapshot) convert,
  }) => guard.call(() async {
    final rows = await query;
    return [for (final row in rows) convert(RowSnapshot.fromRow(row))];
  });

  /// One row, live. Gone, or out of the caller's sight, is not-found.
  Stream<Result<T>> watchOne<T>({
    required String table,
    required String id,
    required T Function(RowSnapshot) convert,
  }) => guard.stream(
    client.from(table).stream(primaryKey: const ['id']).eq('id', id).map((
      rows,
    ) {
      if (rows.isEmpty) throw notFound('No $table $id');
      return convert(RowSnapshot.fromRow(rows.first));
    }),
  );

  /// Rows, live: every change the caller may see re-emits the list.
  Stream<Result<List<T>>> watchMany<T>({
    required Stream<List<Map<String, dynamic>>> stream,
    required T Function(RowSnapshot) convert,
  }) => guard.stream(
    stream.map(
      (rows) => [for (final row in rows) convert(RowSnapshot.fromRow(row))],
    ),
  );

  /// Calls a database function for its effect.
  Future<Result<void>> rpc(String function, Map<String, Object?> params) =>
      guard.call<void>(() async {
        await client.rpc<dynamic>(function, params: params);
      });

  /// Calls a database function that changes something and must not be
  /// repeated if a first attempt may have landed: no retry.
  Future<Result<R>> rpcOnce<R>(String function, Map<String, Object?> params) =>
      guard.callOnce(() async => await client.rpc<R>(function, params: params));

  /// A database function's answer.
  Future<Result<R>> rpcFor<R>(String function, Map<String, Object?> params) =>
      guard.call(() async => await client.rpc<R>(function, params: params));

  /// An id like Firestore's: 20 characters from a random source. The app
  /// names some records before saving them, so photos can be filed under
  /// the report they belong to.
  static String newId() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 20; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
  }

  /// A repository method nothing in the app calls, kept so the interface
  /// stays as it was (Objective 1, item 4: listed for a decision, not
  /// deleted). It has no database function behind it: a general-purpose
  /// write would open a way around the rules the functions enforce.
  static Future<Result<T>> unsupported<T>(String method) => Future.value(
    Result.failure(
      UnknownFailure(
        '$method is not available: changes like this go through the '
        'operation that makes them.',
      ),
    ),
  );

  /// A time as the database takes it.
  static String? time(DateTime? value) => value?.toUtc().toIso8601String();

  static PostgrestException notFound(String message) =>
      PostgrestException(message: message, code: 'PT404');

  /// A refusal the app makes before asking the database, worded for the
  /// person using it: mapped to a ValidationFailure carrying [message].
  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: 'PT422');
}
