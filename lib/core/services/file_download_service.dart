import 'dart:typed_data';

import '../utils/result.dart';
import 'file_download_service_stub.dart'
    if (dart.library.js_interop) 'file_download_service_web.dart'
    as platform;

/// Hands the administrator a file to save — the Analytics CSV export, and
/// the QR label sheets (Objective 6.C).
///
/// The admin console runs only in the browser (manuscript §1.5), so the
/// real implementation is a browser download. The stub keeps the rest of
/// the app, and its tests on the Dart VM, compiling everywhere else.
abstract interface class FileDownloadService {
  /// The implementation for the platform being compiled for.
  factory FileDownloadService() = platform.PlatformFileDownloadService;

  /// Offers [contents] as a file named [fileName].
  Future<Result<void>> saveText({
    required String fileName,
    required String contents,
    String mimeType = 'text/csv',
  });

  /// Offers [bytes] as a file named [fileName]: a PDF of labels.
  Future<Result<void>> saveBytes({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}
