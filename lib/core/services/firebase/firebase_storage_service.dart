import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../utils/result.dart';
import '../storage_service.dart';
import 'firebase_call_guard.dart';

/// Cloud Storage implementation of [StorageService].
class FirebaseStorageService implements StorageService {
  const FirebaseStorageService({required this._storage, required this._guard});

  final FirebaseStorage _storage;
  final FirebaseCallGuard _guard;

  @override
  Future<Result<String>> uploadFile({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) => _guard.call(() async {
    final reference = _storage.ref(path);
    await reference.putData(
      bytes,
      SettableMetadata(contentType: contentType ?? _inferContentType(path)),
    );
    return reference.getDownloadURL();
  });

  @override
  UploadTaskHandle uploadFileWithProgress({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) {
    final reference = _storage.ref(path);
    final task = reference.putData(
      bytes,
      SettableMetadata(contentType: contentType ?? _inferContentType(path)),
    );

    return UploadTaskHandle(
      progress: task.snapshotEvents
          .map(
            (snapshot) => UploadProgress(
              bytesTransferred: snapshot.bytesTransferred,
              totalBytes: snapshot.totalBytes,
            ),
          )
          // A failed upload also errors this stream, with a raw
          // FirebaseException. The failure is reported — mapped — through
          // downloadUrl; letting it out here as well would leak Firebase's
          // type past the service boundary.
          .handleError((Object _) {}),
      downloadUrl: _guard.call(() async {
        await task;
        return reference.getDownloadURL();
      }),
    );
  }

  @override
  Future<Result<String>> getDownloadUrl({required String path}) =>
      _guard.call(() => _storage.ref(path).getDownloadURL());

  @override
  Future<Result<void>> deleteFile({required String path}) =>
      _guard.call(() => _storage.ref(path).delete());

  /// Storage does not infer content type from bytes, and an object stored
  /// as `application/octet-stream` will not render in an `<img>` tag —
  /// which would silently break every photo view in the app.
  static String _inferContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}
