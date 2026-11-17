import 'dart:math';

import 'package:supabase/supabase.dart';

import '../errors/failures.dart';
import '../services/supabase/supabase_call_guard.dart';
import '../services/supabase/supabase_change_channel.dart';
import '../utils/result.dart';
import 'data_record.dart';
import 'live_sync.dart';
import 'row_record.dart';

/// Shared plumbing for the Supabase repositories (Objective 1), as
/// `FirestoreRepository` was for the Firestore ones.
///
/// Reads go straight to the tables: row level security decides what the
/// caller sees. Writes go through the database's functions
/// (supabase/migrations/*_functions.sql), because app users can read the
/// tables and nothing more. Rows reach the models as [DataRecord]s, so
/// every model keeps its one converter.
///
/// Live views are queries that [LiveSync] reads again whenever their
/// table may have changed ([liveRows]): on a change heard over Realtime,
/// and after every change this app makes itself, which is why the
/// function calls below tell it ([_settled]). A save therefore shows on
/// screen once the database has answered, whatever state the Realtime
/// connection is in (2026-11-16, docs/architecture_decisions.md §42).
abstract class SupabaseRepository {
  const SupabaseRepository({
    required this.client,
    required this.guard,
    this._live,
  });

  final SupabaseClient client;

  final SupabaseCallGuard guard;

  final LiveSync? _live;

  /// One per client for repositories built without one: the tests that
  /// stand a repository up by hand. The app hands every repository the
  /// same one (`liveSyncProvider`).
  static final Expando<LiveSync> _standalone = Expando<LiveSync>();

  /// What keeps this repository's live views current.
  LiveSync get live =>
      _live ?? (_standalone[client] ??= supabaseLiveSync(client));

  /// The rows of [table] that [query] narrows, orders and limits, now and
  /// whenever a row of [table] (or of [alsoWatching]) may have changed.
  Stream<LiveRows> liveRows(
    String table, [
    Future<LiveRows> Function(PostgrestFilterBuilder<PostgrestList> rows)?
    query,
    Set<String> alsoWatching = const {},
  ]) => live.watchRows(
    tables: {table, ...alsoWatching},
    fetch: () async {
      final rows = client.from(table).select();
      return LiveRows.of(await (query == null ? rows : query(rows)));
    },
  );

  /// One row by id, failing with not-found when there is none or the
  /// caller may not see it.
  Future<Result<T>> getOne<T>({
    required String table,
    required String id,
    required T Function(DataRecord) convert,
  }) => guard.call(() async {
    final row = await client.from(table).select().eq('id', id).maybeSingle();
    if (row == null) throw notFound('No $table $id');
    return convert(RowRecord.fromRow(row));
  });

  /// One row by id, or null when there is none.
  Future<Result<T?>> getOneOrNull<T>({
    required String table,
    required String id,
    required T Function(DataRecord) convert,
  }) => guard.call(() async {
    final row = await client.from(table).select().eq('id', id).maybeSingle();
    return row == null ? null : convert(RowRecord.fromRow(row));
  });

  Future<Result<List<T>>> getMany<T>({
    required Future<List<Map<String, dynamic>>> query,
    required T Function(DataRecord) convert,
  }) => guard.call(() async {
    final rows = await query;
    return [for (final row in rows) convert(RowRecord.fromRow(row))];
  });

  /// One row, live. Gone, or out of the caller's sight, is not-found.
  Stream<Result<T>> watchOne<T>({
    required String table,
    required String id,
    required T Function(DataRecord) convert,
  }) => guard.stream(
    liveRows(table, (rows) => rows.eq('id', id)).map((rows) {
      if (rows.isEmpty) throw notFound('No $table $id');
      return convert(RowRecord.fromRow(rows.first));
    }),
  );

  /// Rows, live: [stream] is a [liveRows], re-emitted as models.
  Stream<Result<List<T>>> watchMany<T>({
    required Stream<LiveRows> stream,
    required T Function(DataRecord) convert,
  }) => guard.stream(
    stream.map(
      (rows) => [for (final row in rows) convert(RowRecord.fromRow(row))],
    ),
  );

  /// Calls a database function for its effect.
  ///
  /// [changesData] is false for the few calls that change nothing a screen
  /// shows (the session's keep-alive, a push token): after any other, the
  /// live views are read again before the result is returned.
  Future<Result<void>> rpc(
    String function,
    Map<String, Object?> params, {
    bool changesData = true,
  }) => _settled(
    guard.call<void>(() async {
      await client.rpc<dynamic>(function, params: params);
    }),
    changesData: changesData,
  );

  /// Calls a database function that changes something and must not be
  /// repeated if a first attempt may have landed: no retry.
  Future<Result<R>> rpcOnce<R>(String function, Map<String, Object?> params) =>
      _settled(
        guard.callOnce(
          () async => await client.rpc<R>(function, params: params),
        ),
      );

  /// The result of a change, returned once the live views have been read
  /// again: by the time a screen is told "saved", it shows what was saved,
  /// and by the time it is told "refused", it shows what the database has.
  ///
  /// A call that never reached the database (no connection, a timeout)
  /// waits for nothing: the views are read again in the background, in
  /// case the change landed and only its answer was lost.
  Future<Result<R>> _settled<R>(
    Future<Result<R>> call, {
    bool changesData = true,
  }) async {
    final result = await call;
    if (changesData) {
      final unreached = result is Error<R> && result.failure is NetworkFailure;
      await live.changed(reached: !unreached);
    }
    return result;
  }

  /// A database function that answers with the row it wrote — a ledger
  /// entry, a loan — read as a model. [once] for one not safe to repeat.
  Future<Result<T>> rpcRow<T>(
    String function,
    Map<String, Object?> params, {
    required T Function(DataRecord) convert,
    bool once = false,
  }) {
    Future<T> run() async {
      final row = await client.rpc<Map<String, dynamic>>(
        function,
        params: params,
      );
      return convert(RowRecord.fromRow(row));
    }

    return _settled(once ? guard.callOnce(run) : guard.call(run));
  }

  /// A database function's answer.
  Future<Result<R>> rpcFor<R>(String function, Map<String, Object?> params) =>
      _settled(
        guard.call(() async => await client.rpc<R>(function, params: params)),
      );

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
