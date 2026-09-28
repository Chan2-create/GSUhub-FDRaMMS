import 'dart:typed_data';

import '../utils/result.dart';

/// Abstract file-storage contract (report photo evidence, accomplishment
/// photos, QR assets). Every shell depends on this interface, never on
/// `firebase_storage` directly — see the "Shared Backend Contract" in
/// docs/architecture_decisions.md, rule 1.
///
/// Takes raw bytes rather than a platform-specific file-picker type
/// (`XFile`, `File`, etc.) so this interface stays usable from both the
/// web and mobile shells without depending on `dart:io` or a picker
/// package — satisfies rule 2 ("core/ is platform-agnostic").
///
/// Paths come from `StoragePaths` (core/constants/storage_paths.dart).
abstract interface class StorageService {
  /// Uploads [bytes] to [path] (e.g.
  /// `damage_reports/{reportId}/{fileName}`) and returns its public
  /// download URL on success.
  Future<Result<String>> uploadFile({
    required String path,
    required Uint8List bytes,
    String? contentType,
  });

  /// Uploads while reporting progress.
  ///
  /// Separate from [uploadFile] rather than replacing it: callers that do
  /// not need progress should not have to consume a stream to get a URL.
  /// The report form needs it — photos over campus wifi are slow enough
  /// that a determinate bar beats an indefinite spinner (Objective 3.C).
  ///
  /// The progress stream completes after the final event; await
  /// [UploadTaskHandle.downloadUrl] for the result.
  UploadTaskHandle uploadFileWithProgress({
    required String path,
    required Uint8List bytes,
    String? contentType,
  });

  Future<Result<String>> getDownloadUrl({required String path});

  Future<Result<void>> deleteFile({required String path});
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

/// Handle to an in-flight upload: live [progress] plus the eventual
/// download URL.
class UploadTaskHandle {
  const UploadTaskHandle({required this.progress, required this.downloadUrl});

  final Stream<UploadProgress> progress;
  final Future<Result<String>> downloadUrl;
}
