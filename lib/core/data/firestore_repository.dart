import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firebase/firebase_call_guard.dart';
import '../services/firebase/firestore_service_impl.dart';
import '../utils/result.dart';

/// Shared plumbing for the concrete repositories.
///
/// Models built in 1.B convert from a `DocumentSnapshot`, while
/// [FirestoreService]'s generic surface converts from a `(data, id)` pair.
/// Rather than give every model a second converter, repositories use the
/// snapshot-based helpers here, which sit on top of the same
/// [FirestoreServiceImpl] and [FirebaseCallGuard] — so timeout, retry and
/// error mapping still apply uniformly.
abstract class FirestoreRepository {
  const FirestoreRepository({required this.db, required this.guard});

  /// Firestore access point. Protected by convention — repositories are
  /// the only layer permitted to touch it.
  final FirestoreServiceImpl db;

  final FirebaseCallGuard guard;

  CollectionReference<Map<String, dynamic>> collection(String path) =>
      db.collection(path);

  /// Reads one document and converts it, failing with `not-found` when it
  /// does not exist.
  Future<Result<T>> getOne<T>({
    required String path,
    required String id,
    required T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
  }) => guard.call(() async {
    final snapshot = await collection(path).doc(id).get();
    if (!snapshot.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'No document at $path/$id',
      );
    }
    return convert(snapshot);
  });

  /// Reads one document, returning `null` rather than failing when it is
  /// absent — for the cases where "no record yet" is a normal outcome
  /// (unrated work order, unread config).
  Future<Result<T?>> getOneOrNull<T>({
    required String path,
    required String id,
    required T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
  }) => guard.call(() async {
    final snapshot = await collection(path).doc(id).get();
    return snapshot.exists ? convert(snapshot) : null;
  });

  Future<Result<List<T>>> getMany<T>({
    required Query<Map<String, dynamic>> query,
    required T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
  }) => guard.call(() async {
    final snapshot = await query.get();
    return snapshot.docs.map(convert).toList(growable: false);
  });

  Stream<Result<T>> watchOne<T>({
    required String path,
    required String id,
    required T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
  }) => guard.stream(
    collection(path).doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'No document at $path/$id',
        );
      }
      return convert(snapshot);
    }),
  );

  Stream<Result<List<T>>> watchMany<T>({
    required Query<Map<String, dynamic>> query,
    required T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
  }) => guard.stream(
    query.snapshots().map(
      (snapshot) => snapshot.docs.map(convert).toList(growable: false),
    ),
  );

  Future<Result<String>> add({
    required String path,
    required Map<String, dynamic> data,
  }) => guard.call(() async {
    final reference = await collection(path).add(data);
    return reference.id;
  });

  Future<Result<void>> setDoc({
    required String path,
    required String id,
    required Map<String, dynamic> data,
  }) => guard.call(() => collection(path).doc(id).set(data));

  Future<Result<void>> updateDoc({
    required String path,
    required String id,
    required Map<String, dynamic> data,
  }) => guard.call(() => collection(path).doc(id).update(data));

  Future<Result<void>> deleteDoc({required String path, required String id}) =>
      guard.call(() => collection(path).doc(id).delete());

  /// Server-generated timestamp, preferred over `DateTime.now()` for
  /// `updatedAt`-style fields: a device with a wrong clock would otherwise
  /// write timestamps that sort incorrectly against everyone else's.
  static FieldValue get serverNow => FieldValue.serverTimestamp();

  /// A refusal the administrator should read as written — an illegal
  /// status move, a self-lockout. Thrown inside a transaction, it aborts
  /// the transaction, and FirebaseErrorMapper turns it into a
  /// ValidationFailure carrying [message] verbatim.
  static FirebaseException precondition(String message) => FirebaseException(
    plugin: 'gsuhub',
    code: 'failed-precondition',
    message: message,
  );

  static FirebaseException notFound(String message) => FirebaseException(
    plugin: 'cloud_firestore',
    code: 'not-found',
    message: message,
  );
}
