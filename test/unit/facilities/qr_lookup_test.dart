import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/facilities/data/models/asset.dart';
import 'package:gsuhub/features/facilities/presentation/qr_lookup.dart';

import '../../support/fake_report_form_backend.dart';

/// Scanned QR codes to facilities (manuscript §1.7). Unknown and retired
/// codes are expected answers, reported plainly — never errors.
void main() {
  Asset asset({String facilityId = 'fac-eng-101', bool isActive = true}) =>
      Asset(
        id: 'asset-fan-01',
        name: 'Ceiling Fan',
        qrCode: 'AST-FAN',
        facilityId: facilityId,
        condition: ItemCondition.poor,
        isActive: isActive,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  QrMatch matchOf(Result<QrMatch> result) =>
      result.fold((match) => match, (failure) => fail('$failure'));

  Failure failureOf(Result<QrMatch> result) =>
      result.fold((_) => fail('expected a failure'), (failure) => failure);

  test('finds a facility by its code, ignoring stray whitespace', () async {
    final lookup = QrLookup(FakeFacilityRepository());

    final match = matchOf(await lookup.resolve('  FAC-FAC-LIBRARY\n'));

    expect(match.facility.id, 'fac-library');
    expect(match.asset, isNull);
  });

  test("finds an asset's facility, and names the asset", () async {
    final lookup = QrLookup(FakeFacilityRepository(assets: [asset()]));

    final match = matchOf(await lookup.resolve('AST-FAN'));

    expect(match.facility.id, 'fac-eng-101');
    expect(match.asset?.id, 'asset-fan-01');
  });

  test('says an unknown code is not registered', () async {
    final lookup = QrLookup(FakeFacilityRepository());

    final failure = failureOf(await lookup.resolve('SOMETHING-ELSE'));

    expect(failure, isA<NotFoundFailure>());
    expect(failure.message, contains("isn't registered"));
  });

  test('treats an empty scan as unregistered', () async {
    final failure = failureOf(
      await QrLookup(FakeFacilityRepository()).resolve('   '),
    );

    expect(failure, isA<NotFoundFailure>());
  });

  test('refuses a retired facility', () async {
    final lookup = QrLookup(
      FakeFacilityRepository(
        facilities: [
          fakeFacility(
            id: 'fac-old',
            building: 'Old Annex',
            room: 'Room 1',
            isActive: false,
          ),
        ],
      ),
    );

    final failure = failureOf(await lookup.resolve('FAC-FAC-OLD'));

    expect(failure, isA<NotFoundFailure>());
    expect(failure.message, contains('no longer in service'));
  });

  test('refuses a retired asset, and an asset in a retired facility', () async {
    final retiredAsset = QrLookup(
      FakeFacilityRepository(assets: [asset(isActive: false)]),
    );
    expect(
      failureOf(await retiredAsset.resolve('AST-FAN')).message,
      contains('no longer in service'),
    );

    final retiredHome = QrLookup(
      FakeFacilityRepository(
        facilities: [
          fakeFacility(
            id: 'fac-old',
            building: 'Old Annex',
            room: 'Room 1',
            isActive: false,
          ),
        ],
        assets: [asset(facilityId: 'fac-old')],
      ),
    );
    expect(
      failureOf(await retiredHome.resolve('AST-FAN')).message,
      contains('no longer in service'),
    );
  });

  test('passes a connection failure through as itself', () async {
    final lookup = QrLookup(
      FakeFacilityRepository(failure: const NetworkFailure('Offline.')),
    );

    final failure = failureOf(await lookup.resolve('FAC-FAC-LIBRARY'));

    expect(failure, isA<NetworkFailure>());
  });
}
