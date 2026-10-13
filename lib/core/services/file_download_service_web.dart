import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

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
      _download(fileName, bytes, '$mimeType;charset=utf-8');
      return const Result.success(null);
    } on Object {
      return Result.failure(UnknownFailure('Could not save $fileName.'));
    }
  }

  @override
  Future<Result<void>> saveBytes({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      _download(fileName, bytes, mimeType);
      return const Result.success(null);
    } on Object {
      return Result.failure(UnknownFailure('Could not save $fileName.'));
    }
  }

  static void _download(String fileName, Uint8List bytes, String type) {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.style.display = 'none';
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
