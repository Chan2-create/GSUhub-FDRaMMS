import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../errors/failures.dart';
import '../utils/result.dart';
import 'file_download_service.dart';

/// A browser download through a temporary object URL.
class PlatformFileDownloadService implements FileDownloadService {
  @override
  Future<Result<void>> saveText({
    required String fileName,
    required String contents,
    String mimeType = 'text/csv',
  }) async {
    try {
      // The byte-order mark makes Excel read the file as UTF-8, so names
      // like "Peñaranda" survive the round trip instead of turning to
      // mojibake.
      final bytes = utf8.encode('﻿$contents');
      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = fileName;
      anchor.style.display = 'none';
      web.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);
      return const Result.success(null);
    } on Object {
      return Result.failure(UnknownFailure('Could not save $fileName.'));
    }
  }
}
