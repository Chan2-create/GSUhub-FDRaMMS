import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../utils/result.dart';
import '../storage_service.dart';
import 'firebase_call_guard.dart';

/// Canonical Cloud Storage paths.
///
/// Centralized for the same reason collection names are: a path typed by
/// hand in two places eventually diverges, and here a divergence means
/// uploads land somewhere the security rules do not cover. These mirror
/// the `match` blocks in `firebase/storage.rules` exactly — change one and
/// you must change the other.
abstract final class StoragePaths {
  /// Photo evidence attached to a damage report (manuscript §1.5).
  static String damageReportPhoto(String reportId, String fileName) =>
      'damage_reports/$reportId/$fileName';

  /// Photo documentation of completed maintenance.
  static String accomplishmentPhoto(String reportId, String fileName) =>
      'accomplishment_reports/$reportId/$fileName';

  /// Per-task proof of work (Figure 24, "Upload Proof").
  static String taskProofPhoto(String taskId, String fileName) =>
      'tasks/$taskId/$fileName';

  /// Generated QR code image for a facility or asset.
  static String qrCode(String entityType, String entityId) =>
      'qr_codes/$entityType/$entityId.png';

  static String userProfileImage(String uid, String fileName) =>
      'users/$uid/$fileName';
}

/// Progress of an in-flight upload, surfaced so a UI can show a
/// determinate progress bar instead of an indefinite spinner — photo
/// uploads over campus wifi are slow enough that the difference matters.
class UploadProgress {
  const UploadProgress({
    required this.bytesTransferred,
    required this.totalBytes,
  });

  final int bytesTransferred;
  final int totalBytes;

  /// 0.0–1.0, or 0.0 when the total is not yet known.
  double get fraction =>
      totalBytes <= 0 ? 0 : (bytesTransferred / totalBytes).clamp(0.0, 1.0);

  bool get isComplete => totalBytes > 0 && bytesTransferred >= totalBytes;
}

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

  /// Uploads while reporting progress.
  ///
  /// Separate from [uploadFile] rather than replacing it: the interface
  /// contract from 1.A returns a `Future<Result<String>>`, and callers
  /// that do not need progress should not have to consume a stream to get
  /// a URL.
  ///
  /// The returned stream completes after emitting a final progress event;
  /// await [UploadTaskHandle.downloadUrl] for the result.
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
      progress: task.snapshotEvents.map(
        (snapshot) => UploadProgress(
          bytesTransferred: snapshot.bytesTransferred,
          totalBytes: snapshot.totalBytes,
        ),
      ),
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

/// Handle to an in-flight upload: live [progress] plus the eventual
/// download URL.
class UploadTaskHandle {
  const UploadTaskHandle({required this.progress, required this.downloadUrl});

  final Stream<UploadProgress> progress;
  final Future<Result<String>> downloadUrl;
}
