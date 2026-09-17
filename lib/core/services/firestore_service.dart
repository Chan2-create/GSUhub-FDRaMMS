import '../utils/result.dart';

/// Abstract Firestore access contract. Every shell and feature depends on
/// this interface, never on `cloud_firestore` directly — see the "Shared
/// Backend Contract" in docs/architecture_decisions.md, rules 1 and 3.
///
/// Deliberately generic and collection-path-based (paths come from
/// `constants/firestore_paths.dart`) rather than typed per entity —
/// document *shapes* (field names, models) are Objective 1.B's
/// responsibility. `fromMap`/`toMap` are supplied by the caller so this
/// interface never needs to know what a `damage_reports` document looks
/// like.
///
/// No implementation exists yet. A concrete `CloudFirestoreService` is
/// built in Objective 1.C once the database structure (1.B) exists to
/// query against.
abstract interface class FirestoreService {
  Future<Result<T>> getDocument<T>({
    required String collectionPath,
    required String documentId,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  });

  Future<Result<List<T>>> getCollection<T>({
    required String collectionPath,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  });

  /// Emits the document at [collectionPath]/[documentId] every time it
  /// changes, or a [Result.failure] if it doesn't exist / can't be read.
  Stream<Result<T>> watchDocument<T>({
    required String collectionPath,
    required String documentId,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  });

  Stream<Result<List<T>>> watchCollection<T>({
    required String collectionPath,
    required T Function(Map<String, dynamic> data, String id) fromMap,
  });

  /// Creates a new document with an auto-generated id and returns it.
  Future<Result<String>> addDocument({
    required String collectionPath,
    required Map<String, dynamic> data,
  });

  /// Creates or fully overwrites the document at [documentId].
  Future<Result<void>> setDocument({
    required String collectionPath,
    required String documentId,
    required Map<String, dynamic> data,
  });

  /// Merges [data] into the existing document at [documentId].
  Future<Result<void>> updateDocument({
    required String collectionPath,
    required String documentId,
    required Map<String, dynamic> data,
  });

  Future<Result<void>> deleteDocument({
    required String collectionPath,
    required String documentId,
  });
}
