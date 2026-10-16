import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/connectivity_service.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/core/services/supabase/supabase_connectivity_service.dart';
import 'package:gsuhub/core/services/supabase/supabase_storage_service.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import '../../support/test_app_config.dart';

const _url = 'http://localhost:54321';
final _photo = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

Failure? _failureOf(Result<Object?> result) =>
    result.fold((_) => null, (failure) => failure);

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request request) respond;
  late String? uid;

  SupabaseClient client() {
    final client = SupabaseClient(
      _url,
      'anon-key',
      accessToken: () async => 'token-for-$uid',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = respond(request);
        // A real response knows its request, and the client reads it.
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: {'content-type': 'application/json', ...response.headers},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    return client;
  }

  SupabaseStorageService storage() => SupabaseStorageService(
    client: client(),
    currentUid: () => uid,
    guard: SupabaseCallGuard(testAppConfig()),
  );

  /// The Storage API: uploads succeed, signing answers a path.
  http.Response storageApi(http.Request request) {
    final path = request.url.path;
    if (path.startsWith('/storage/v1/object/sign/')) {
      final object = path.substring('/storage/v1/object/sign/'.length);
      return http.Response(
        jsonEncode({'signedURL': '/object/sign/$object?token=signed'}),
        200,
      );
    }
    return http.Response(jsonEncode({'Key': path, 'Id': 'id'}), 200);
  }

  setUp(() {
    requests = [];
    respond = storageApi;
    uid = 'seed-faculty-0001';
  });

  group('SupabaseStorageService', () {
    test("files a report's photo under the uploader's uid, and returns a "
        'ten-year signed URL', () async {
      final result = await storage().uploadFile(
        path: 'damage_reports/r-1/photo-1.jpg',
        bytes: _photo,
      );

      expect(
        result.fold((url) => url, (_) => null),
        '$_url/storage/v1/object/sign/photos/damage_reports/'
        'seed-faculty-0001/r-1/photo-1.jpg?token=signed',
      );
      final [upload, sign] = requests;
      expect(
        upload.url.path,
        '/storage/v1/object/photos/damage_reports/seed-faculty-0001/r-1/photo-1.jpg',
      );
      expect(
        upload.headers['Authorization'],
        'Bearer token-for-seed-faculty-0001',
      );
      // Sent as a multipart form; the photo's part says what it is, and
      // that is what the bucket's images-only rule reads.
      expect(
        utf8.decode(upload.bodyBytes, allowMalformed: true).toLowerCase(),
        contains('content-type: image/jpeg'),
      );
      // Never replaces a stored photo.
      expect(upload.headers['x-upsert'], 'false');
      expect(jsonDecode(sign.body), {'expiresIn': 3650 * 24 * 60 * 60});
    });

    test('files proof and finished work under the uid too, and leaves shared '
        'folders alone', () {
      final service = storage();
      expect(
        service.objectPath('tasks/t-1/proof.jpg'),
        'tasks/seed-faculty-0001/t-1/proof.jpg',
      );
      expect(
        service.objectPath('accomplishment_reports/ac-1/after.png'),
        'accomplishment_reports/seed-faculty-0001/ac-1/after.png',
      );
      expect(
        service.objectPath('inventory_items/i-1/photo.jpg'),
        'inventory_items/i-1/photo.jpg',
      );
      expect(
        service.objectPath('users/seed-faculty-0001/avatar.png'),
        'users/seed-faculty-0001/avatar.png',
      );
      // Already filed under a uid: unchanged.
      expect(
        service.objectPath('damage_reports/u-1/r-1/photo-1.jpg'),
        'damage_reports/u-1/r-1/photo-1.jpg',
      );
    });

    test('signed out, nothing is sent', () async {
      uid = null;
      final result = await storage().uploadFile(
        path: 'damage_reports/r-1/photo-1.jpg',
        bytes: _photo,
      );
      expect(_failureOf(result), isA<PermissionFailure>());
      expect(requests, isEmpty);
    });

    test(
      "the bucket's refusals come back as failures, not exceptions",
      () async {
        respond = (_) => http.Response(
          jsonEncode({
            'statusCode': '413',
            'error': 'Payload too large',
            'message': 'The object exceeded the maximum allowed size',
          }),
          413,
        );
        final result = await storage().uploadFile(
          path: 'damage_reports/r-1/photo-1.jpg',
          bytes: _photo,
        );
        expect(
          _failureOf(result),
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            'That photo is larger than 10 MB.',
          ),
        );
      },
    );

    test('an upload is not retried: it may have landed', () async {
      respond = (_) => throw http.ClientException('Connection reset');
      final service = SupabaseStorageService(
        client: client(),
        currentUid: () => uid,
        guard: SupabaseCallGuard(testAppConfig(maxRetryAttempts: 2)),
      );
      final result = await service.uploadFile(
        path: 'damage_reports/r-1/photo-1.jpg',
        bytes: _photo,
      );
      expect(_failureOf(result), isA<NetworkFailure>());
      expect(requests, hasLength(1));
    });

    test('progress shows the start and the finish', () async {
      final handle = storage().uploadFileWithProgress(
        path: 'damage_reports/r-1/photo-1.jpg',
        bytes: _photo,
      );
      final progress = await handle.progress.toList();
      expect(progress.map((p) => p.fraction), [0.0, 1.0]);
      expect((await handle.downloadUrl).isSuccess, isTrue);
    });

    test('removing a photo that is not there, or not yours, says so', () async {
      respond = (_) => http.Response('[]', 200);
      final result = await storage().deleteFile(
        path: 'inventory_items/i-1/photo.jpg',
      );
      expect(_failureOf(result), isA<NotFoundFailure>());
    });
  });

  group('SupabaseConnectivityService', () {
    SupabaseConnectivityService connectivity() {
      final service = SupabaseConnectivityService(
        client: client(),
        guard: SupabaseCallGuard(testAppConfig()),
      );
      addTearDown(service.dispose);
      return service;
    }

    test('an answer from the database is online', () async {
      respond = (_) => http.Response('[]', 200);
      final service = connectivity();
      expect((await service.checkReachable()).isSuccess, isTrue);
      expect(service.current, BackendReachability.online);
      expect(requests.single.url.path, '/rest/v1/app_config');
    });

    test('so is a refusal: the server answered', () async {
      respond = (_) => http.Response(
        jsonEncode({'code': '42501', 'message': 'permission denied'}),
        401,
      );
      final service = connectivity();
      await service.checkReachable();
      expect(service.current, BackendReachability.online);
    });

    test('a failed connection is offline', () async {
      respond = (_) => throw http.ClientException('Connection refused');
      final service = connectivity();
      expect((await service.checkReachable()).isFailure, isTrue);
      expect(service.current, BackendReachability.offline);
    });
  });
}
