import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../errors/failures.dart';
import '../../utils/result.dart';
import '../photo_picker_service.dart';

/// [PhotoPickerService] on the `image_picker` plugin — the system camera
/// and photo picker on Android, a file input on web.
class ImagePickerPhotoService implements PhotoPickerService {
  ImagePickerPhotoService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Longest edge, in pixels, a photo is scaled down to before upload.
  ///
  /// A phone camera's 12-megapixel original is 3–6 MB, which is slow over
  /// campus wifi and close to the Storage rules' 10 MB ceiling. At 1920px a
  /// JPEG is a few hundred kilobytes and still shows a cracked tile or a
  /// water stain plainly.
  static const double maxDimension = 1920;

  /// JPEG quality for the re-encode — visually indistinguishable at the
  /// sizes the photos are viewed at, and about a third of the bytes of 100.
  static const int jpegQuality = 80;

  @override
  Future<Result<List<PickedPhoto>>> pick(
    PhotoSource source, {
    required int limit,
  }) async {
    if (limit <= 0) return const Result.success([]);
    try {
      final files = switch (source) {
        PhotoSource.camera => [?await _single(ImageSource.camera)],
        // The plugin's multi-select refuses a limit below two.
        PhotoSource.gallery when limit == 1 => [
          ?await _single(ImageSource.gallery),
        ],
        PhotoSource.gallery => await _picker.pickMultiImage(
          maxWidth: maxDimension,
          maxHeight: maxDimension,
          imageQuality: jpegQuality,
          limit: limit,
        ),
      };

      final photos = <PickedPhoto>[];
      // The limit is advisory on some platforms (a browser's file dialog
      // ignores it), so it is enforced here as well.
      for (final file in files.take(limit)) {
        photos.add(
          PickedPhoto(
            bytes: await file.readAsBytes(),
            fileName: file.name,
            mimeType: _imageTypeOf(file),
          ),
        );
      }
      return Result.success(photos);
    } on PlatformException catch (error) {
      return Result.failure(_failureFor(error, source));
    } on Object catch (error) {
      return Result.failure(
        UnknownFailure("Couldn't open the photo. ($error)"),
      );
    }
  }

  Future<XFile?> _single(ImageSource source) => _picker.pickImage(
    source: source,
    maxWidth: maxDimension,
    maxHeight: maxDimension,
    imageQuality: jpegQuality,
  );

  /// The platform's own type when it gives one, else the extension's —
  /// Android often reports none, and Storage would then save the upload as
  /// `application/octet-stream`, which the rules refuse.
  static String _imageTypeOf(XFile file) {
    final reported = file.mimeType;
    if (reported != null && reported.startsWith('image/')) return reported;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    // The picker re-encodes to JPEG when it scales, which is nearly always.
    return 'image/jpeg';
  }

  static Failure _failureFor(PlatformException error, PhotoSource source) =>
      switch (error.code) {
        'camera_access_denied' => const PermissionFailure(
          "Camera access is blocked for GSUhub. Allow it in your phone's "
          'Settings to take a photo, or choose one from your gallery.',
        ),
        'photo_access_denied' => const PermissionFailure(
          "Photo access is blocked for GSUhub. Allow it in your phone's "
          'Settings, or take a photo with the camera instead.',
        ),
        'no_available_camera' => const ValidationFailure(
          'No camera is available. Choose a photo from your gallery '
          'instead.',
        ),
        _ => UnknownFailure(
          source == PhotoSource.camera
              ? "Couldn't open the camera. (${error.code})"
              : "Couldn't open your photos. (${error.code})",
        ),
      };
}
