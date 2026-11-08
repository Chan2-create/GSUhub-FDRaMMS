import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/services/supabase/supabase_call_guard.dart';
import 'package:gsuhub/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import '../../support/test_app_config.dart';

/// A deleted material (2026-11-05) stays in its table for its ledger, and
/// the repository never hands it out: not by its id, not by its code.
void main() {
  final requests = <http.Request>[];
  late Object? answer;
  late InventoryRepositoryImpl repository;

  Map<String, dynamic> row({String? deletedAt}) => {
    'id': 'i-1',
    'name': 'maso',
    'category': 'tools',
    'specification': null,
    'quantity_available': 2,
    'unit_of_measurement': 'units',
    'storage_location': 'GSU Store',
    'qr_code': 'INV-MASO',
    'minimum_threshold': 5,
    'unit_cost': null,
    'photo_url': null,
    'condition': null,
    'created_at': '2026-10-20T08:00:00Z',
    'updated_at': '2026-10-20T08:00:00Z',
    'deleted_at': deletedAt,
  };

  setUp(() {
    requests.clear();
    final client = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      accessToken: () async => 'token',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(answer),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    repository = InventoryRepositoryImpl(
      client: client,
      guard: SupabaseCallGuard(testAppConfig()),
    );
  });

  test('a material still in the inventory is found by its id', () async {
    answer = row();
    final result = await repository.getItemById('i-1');
    expect(result.fold((item) => item.name, (_) => null), 'maso');
  });

  test('a deleted one is not', () async {
    answer = row(deletedAt: '2026-11-05T02:00:00Z');
    final result = await repository.getItemById('i-1');
    expect(
      result.fold((_) => null, (failure) => failure),
      isA<NotFoundFailure>().having(
        (failure) => failure.message,
        'message',
        'This material is no longer in the inventory.',
      ),
    );
  });

  test('a scanned code is looked up among the materials still in the '
      'inventory', () async {
    answer = <Object>[];
    final result = await repository.getItemByQrCode('INV-MASO');

    expect(result.fold((_) => null, (f) => f), isA<NotFoundFailure>());
    final query = requests.single.url.queryParameters;
    expect(query['qr_code'], 'eq.INV-MASO');
    expect(query['deleted_at'], 'is.null');
  });
}
