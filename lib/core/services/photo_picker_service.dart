import 'dart:typed_data';

import '../utils/result.dart';

/// Where a photo comes from.
enum PhotoSource { camera, gallery }

/// A photo the user chose, already read into memory and scaled down.
///
/// Bytes rather than a file handle so it passes straight to
/// `StorageService.uploadFile` on web and mobile alike.
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;

  /// The name the platform gave it — for display, and for its extension.
  final String fileName;

  /// Always an `image/*` type: the Storage rules refuse anything else.
  final String mimeType;

  int get sizeInBytes => bytes.lengthInBytes;
}

/// Camera and gallery access for photo evidence (manuscript §1.5).
///
/// An interface so the report form can be exercised in tests without a
/// camera, and so the plugin behind it can change without touching a
/// screen.
abstract interface class PhotoPickerService {
  /// Up to [limit] photos from [source]. The camera yields at most one.
  ///
  /// An empty list means the user backed out — not a failure. Fails with a
  /// `PermissionFailure` when camera or photo access has been refused.
  Future<Result<List<PickedPhoto>>> pick(
    PhotoSource source, {
    required int limit,
  });
}
