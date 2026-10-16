import 'dart:async';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../../utils/result.dart';
import '../storage_service.dart';
import 'supabase_call_guard.dart';

/// Supabase Storage implementation of [StorageService]: every photo goes
/// to the private `photos` bucket (supabase/migrations/*_storage_policies.sql).
///
/// The bucket is private, so the URL handed back is a signed one, valid for
/// ten years, and that is what a report stores in `photo_urls` — exactly
/// as it stored Firebase's download URL, so no model or screen changes.
///
/// Callers pass the same paths as before (`StoragePaths`). The bucket's
/// policies want photos filed under the uploader's uid, which a screen
/// should not have to know about, so this service adds it: a report's
/// `damage_reports/{reportId}/{file}` is stored as
/// `damage_reports/{uid}/{reportId}/{file}`, and likewise for
/// accomplishment reports and task proof.
class SupabaseStorageService implements StorageService {
  const SupabaseStorageService({
    required this._client,
    required this._currentUid,
    required this._guard,
  });

  static const String bucket = 'photos';

  /// How long a photo's URL works. Revoking one early takes rotating the
  /// project's keys, which is acceptable for maintenance photos.
  static const Duration signedUrlLifetime = Duration(days: 3650);

  /// Folders whose photos are filed under the uploader's uid.
  static const Set<String> ownerFolders = {
    'damage_reports',
    'accomplishment_reports',
    'tasks',
  };

  final SupabaseClient _client;
  final String? Function() _currentUid;
  final SupabaseCallGuard _guard;

  StorageFileApi get _bucket => _client.storage.from(bucket);

  /// Where [path] is stored in the bucket.
  String objectPath(String path) {
    final parts = path.split('/');
    if (!ownerFolders.contains(parts.first) || parts.length != 3) return path;
    final uid = _currentUid();
    if (uid == null) {
      throw const StorageException(
        'Sign in to upload photos.',
        statusCode: '401',
      );
    }
    return [parts[0], uid, parts[1], parts[2]].join('/');
  }

  @override
  Future<Result<String>> uploadFile({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) =>
      // Once: a retry after a timeout that actually stored the photo would
      // be refused as a duplicate and hide the success.
      _guard.callOnce(() => _upload(path, bytes, contentType));

  @override
  UploadTaskHandle uploadFileWithProgress({
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) {
    // The Storage API reports no progress for a single upload, so the bar
    // shows started and finished. The interface allows that.
    final progress = StreamController<UploadProgress>();
    progress.add(UploadProgress(bytesTransferred: 0, totalBytes: bytes.length));
    final url = uploadFile(path: path, bytes: bytes, contentType: contentType);
    unawaited(
      url.then((result) {
        if (result.isSuccess) {
          progress.add(
            UploadProgress(
              bytesTransferred: bytes.length,
              totalBytes: bytes.length,
            ),
          );
        }
        return progress.close();
      }),
    );
    return UploadTaskHandle(progress: progress.stream, downloadUrl: url);
  }

  @override
  Future<Result<String>> getDownloadUrl({required String path}) =>
      _guard.call(() => _signedUrl(objectPath(path)));

  @override
  Future<Result<void>> deleteFile({required String path}) =>
      _guard.call(() async {
        final removed = await _bucket.remove([objectPath(path)]);
        // Storage answers a refused or missing object with an empty list.
        if (removed.isEmpty) {
          throw const StorageException(
            'That photo no longer exists.',
            statusCode: '404',
          );
        }
      });

  Future<String> _upload(
    String path,
    Uint8List bytes,
    String? contentType,
  ) async {
    final object = objectPath(path);
    await _bucket.uploadBinary(
      object,
      bytes,
      // Not upserted: a photo, once stored, is never replaced (the bucket
      // has no update policy).
      fileOptions: FileOptions(
        contentType: contentType ?? _inferContentType(path),
      ),
    );
    return _signedUrl(object);
  }

  Future<String> _signedUrl(String object) =>
      _bucket.createSignedUrl(object, signedUrlLifetime.inSeconds);

  /// Storage does not infer content type from bytes, and the bucket takes
  /// images only.
  static String _inferContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}
