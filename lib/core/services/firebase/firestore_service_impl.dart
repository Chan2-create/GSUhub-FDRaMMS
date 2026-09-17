import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/result.dart';
import '../firestore_service.dart';
import 'firebase_call_guard.dart';

/// Cloud Firestore implementation of [FirestoreService].
///
/// Stays generic and collection-path-based, exactly as the 1.B interface
/// defines it: this class knows how to move documents, not what any
/// particular document means. Entity knowledge lives in the repositories
/// that call it.
///
/// Also exposes the transaction and batch primitives repositories need for
/// the invariants 1.B specified — atomic inventory deduction, atomic tool
/// borrow/return — which the generic CRUD surface cannot express.
class FirestoreServiceImpl implements FirestoreService {
  const FirestoreServiceImpl({required this._firestore, required this._guard});

  final FirebaseFirestore _firestore;
  final FirebaseCallGuard _guard;

  /// Direct access for repositories that need Firestore's own query
  /// builder (`where`, `orderBy`, `limit`) or its transaction API.
  ///
  /// This is the one deliberate seam in the abstraction. The alternative —
  /// reinventing a query DSL on top of Firestore's — would be a large,
  /// leaky abstraction that still could not express everything. Exposing
  /// the raw handle *to repositories only* keeps the boundary where it
  /// matters: shells and features still never see Firestore, because they
  /// only ever talk to repositories.
  FirebaseFirestore get raw => _firestore;

  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _firestore.collection(path);

  @override
  Future<Result<T>> getDocument<T>({
    required String collectionPath,
    required String documentId,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  }) => _guard.call(() async {
    final snapshot = await _firestore
        .collection(collectionPath)
        .doc(documentId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'No document at $collectionPath/$documentId',
      );
    }
    return fromMap(data, snapshot.id);
  });

  @override
  Future<Result<List<T>>> getCollection<T>({
    required String collectionPath,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  }) => _guard.call(() async {
    final snapshot = await _firestore.collection(collectionPath).get();
    return snapshot.docs
        .map((doc) => fromMap(doc.data(), doc.id))
        .toList(growable: false);
  });

  @override
  Stream<Result<T>> watchDocument<T>({
    required String collectionPath,
    required String documentId,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  }) => _guard.stream(
    _firestore.collection(collectionPath).doc(documentId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'No document at $collectionPath/$documentId',
        );
      }
      return fromMap(data, snapshot.id);
    }),
  );

  @override
  Stream<Result<List<T>>> watchCollection<T>({
    required String collectionPath,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  }) => watchQuery(
    query: _firestore.collection(collectionPath),
    fromMap: fromMap,
  );

  /// Live results for a caller-built [query]. The repository composes the
  /// filters; this handles the mapping and error translation.
  Stream<Result<List<T>>> watchQuery<T>({
    required Query<Map<String, dynamic>> query,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  }) => _guard.stream(
    query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => fromMap(doc.data(), doc.id))
          .toList(growable: false),
    ),
  );

  /// One-shot results for a caller-built [query].
  Future<Result<List<T>>> runQuery<T>({
    required Query<Map<String, dynamic>> query,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  }) => _guard.call(() async {
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => fromMap(doc.data(), doc.id))
        .toList(growable: false);
  });

  @override
  Future<Result<String>> addDocument({
    required String collectionPath,
    required Map<String, dynamic> data,
  }) => _guard.call(() async {
    final reference = await _firestore.collection(collectionPath).add(data);
    return reference.id;
  });

  @override
  Future<Result<void>> setDocument({
    required String collectionPath,
    required String documentId,
    required Map<String, dynamic> data,
  }) => _guard.call(
    () => _firestore.collection(collectionPath).doc(documentId).set(data),
  );

  @override
  Future<Result<void>> updateDocument({
    required String collectionPath,
    required String documentId,
    required Map<String, dynamic> data,
  }) => _guard.call(
    () => _firestore.collection(collectionPath).doc(documentId).update(data),
  );

  @override
  Future<Result<void>> deleteDocument({
    required String collectionPath,
    required String documentId,
  }) => _guard.call(
    () => _firestore.collection(collectionPath).doc(documentId).delete(),
  );

  /// Runs [handler] inside a Firestore transaction.
  ///
  /// Required for the read-then-write invariants 1.B specified: deducting
  /// stock must read the current balance and write the new one atomically,
  /// or two concurrent deductions both read the same figure and one
  /// silently overwrites the other.
  Future<Result<T>> runTransaction<T>(
    Future<T> Function(Transaction transaction) handler,
  ) => _guard.call(() => _firestore.runTransaction<T>(handler));

  /// Applies several writes atomically, for operations that need
  /// all-or-nothing semantics but no reads.
  Future<Result<void>> runBatch(void Function(WriteBatch batch) build) =>
      _guard.call(() {
        final batch = _firestore.batch();
        build(batch);
        return batch.commit();
      });
}
