import '../errors/failures.dart';
import '../utils/result.dart';
import 'file_download_service.dart';

/// Used wherever there is no browser — the Dart VM tests, and the mobile
/// builds, which have no export button to press.
class PlatformFileDownloadService implements FileDownloadService {
  @override
  Future<Result<void>> saveText({
    required String fileName,
    required String contents,
    String mimeType = 'text/csv',
  }) async => const Result.failure(
    ValidationFailure('Exporting is available in the web console only.'),
  );
}
