import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/facilities/presentation/qr_lookup.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item.dart';
import 'package:gsuhub/features/inventory/data/repositories/inventory_repository.dart';
import 'package:gsuhub/features/scanning/domain/personnel_scan_resolver.dart';
import 'package:gsuhub/features/tools/data/models/tool.dart';
import 'package:gsuhub/features/tools/data/repositories/tool_repository.dart';

import '../../support/fake_report_form_backend.dart';

/// What a code scanned in the personnel app identifies (Objective 5.C).
void main() {
  final created = DateTime.utc(2026);
  final item = InventoryItem(
    id: 'inv-led',
    name: 'LED Bulbs',
    category: 'Electrical',
    quantityAvailable: 12,
    unitOfMeasurement: 'units',
    storageLocation: 'GSU Store',
    qrCode: 'INV-LED',
    minimumThreshold: 5,
    createdAt: created,
    updatedAt: created,
  );
  final tool = Tool(
    id: 'tool-1',
    toolCode: 'TL-0912',
    name: 'Fluke Multimeter',
    status: ToolStatus.available,
    condition: ItemCondition.good,
    qrCode: 'TOOL-TL-0912',
    createdAt: created,
    updatedAt: created,
  );

  PersonnelScanResolver resolver({Failure? inventoryFailure}) =>
      PersonnelScanResolver(
        _Inventory(item, failure: inventoryFailure),
        _Tools(tool),
        QrLookup(FakeFacilityRepository()),
      );

  test('a material code finds the material', () async {
    final match = (await resolver().resolve('  INV-LED '))
        .fold((match) => match, (f) => fail(f.message));
    expect(match, isA<MaterialMatch>());
    expect((match as MaterialMatch).item.name, 'LED Bulbs');
  });

  test('a tool code finds the tool', () async {
    final match = (await resolver().resolve('TOOL-TL-0912'))
        .fold((match) => match, (f) => fail(f.message));
    expect((match as ToolMatch).tool.name, 'Fluke Multimeter');
  });

  test('a room code finds the room', () async {
    final match = (await resolver().resolve('FAC-FAC-ENG-101'))
        .fold((match) => match, (f) => fail(f.message));
    expect((match as PlaceMatch).place.facility.id, 'fac-eng-101');
  });

  test('an unknown code says what it is not', () async {
    final result = await resolver().resolve('HELLO');
    expect(
      result.fold((_) => null, (f) => f.message),
      PersonnelScanResolver.unregistered,
    );
  });

  test('a failed read is reported, not taken for "unknown"', () async {
    final result = await resolver(
      inventoryFailure: const NetworkFailure('No connection.'),
    ).resolve('INV-LED');
    expect(result.fold((_) => null, (f) => f), isA<NetworkFailure>());
  });
}

class _Inventory implements InventoryRepository {
  _Inventory(this.item, {this.failure});

  final InventoryItem item;
  final Failure? failure;

  @override
  Future<Result<InventoryItem>> getItemByQrCode(String qrCode) async {
    if (failure case final failure?) return Result.failure(failure);
    return qrCode == item.qrCode
        ? Result.success(item)
        : const Result.failure(NotFoundFailure('No item.'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tools implements ToolRepository {
  _Tools(this.tool);

  final Tool tool;

  @override
  Future<Result<Tool>> getToolByQrCode(String qrCode) async =>
      qrCode == tool.qrCode
      ? Result.success(tool)
      : const Result.failure(NotFoundFailure('No tool.'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
