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
/// No implementation exists yet. A concrete `FirebaseStorageService` is
/// built in Objective 1.C once a Storage bucket is actually configured.
abstract interface class StorageService {
  /// Uploads [bytes] to [path] (e.g.
  /// `damage_reports/{reportId}/{fileName}`) and returns its public
  /// download URL on success.
  Future<Result<String>> uploadFile({
    required String path,
    required Uint8List bytes,
    String? contentType,
  });

  Future<Result<String>> getDownloadUrl({required String path});

  Future<Result<void>> deleteFile({required String path});
}
