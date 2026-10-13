import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/item_condition.dart';
import 'package:gsuhub/core/enums/tool_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/facilities/data/models/facility_draft.dart';
import 'package:gsuhub/features/inventory/data/models/inventory_item_draft.dart';
import 'package:gsuhub/features/inventory/data/models/material_line.dart';
import 'package:gsuhub/features/tools/data/models/tool_draft.dart';

import '../../support/fake_firestore_repositories.dart';

/// Inventory management (Objectives 6.A–6.C), against the real
/// repositories over an in-memory Firestore: materials and their ledger,
/// technicians' requests and the materials pre-assigned to a job, tools
/// checked out from the console, and the rooms and equipment that carry
/// QR codes.
void main() {
  late FirestoreHarness h;
  const admin = FirestoreHarness.admin;
  const technician = FirestoreHarness.technician;

  setUp(() => h = FirestoreHarness());

  String? failureMessage(Result<Object?> result) =>
      result.fold((_) => null, (failure) => failure.message);

  Future<List<Map<String, dynamic>>> all(String collection) async => [
    for (final doc in (await h.firestore.collection(collection).get()).docs)
      doc.data(),
  ];

  Future<List<Map<String, dynamic>>> ledgerFor(String itemId) async => [
    for (final entry in await all(FirestorePaths.inventoryTransactions))
      if (entry['inventoryItemId'] == itemId) entry,
  ];

  CollectionReference<Map<String, dynamic>> allocated(String workOrderId) => h
      .firestore
      .collection(FirestorePaths.workOrders)
      .doc(workOrderId)
      .collection(FirestorePaths.materialsAllocated);

  InventoryItemDraft material({
    String name = 'Wall Socket Plate (Double)',
    String qrCode = 'INV-SOCKET-PLATE',
    double? unitCost = 85,
  }) => InventoryItemDraft(
    name: name,
    category: 'Electrical',
    specification: 'Double',
    unitOfMeasurement: 'pcs',
    storageLocation: 'GSU Store, Shelf B',
    qrCode: qrCode,
    minimumThreshold: 5,
    unitCost: unitCost,
  );

  group('materials (6.A)', () {
    test(
      'a new material arrives with its opening stock on the ledger',
      () async {
        final result = await h.inventory.createItem(
          draft: material(),
          openingStock: 20,
          actor: admin,
        );
        final id = result.fold((id) => id, (f) => fail(f.message));

        final item = await h.doc(FirestorePaths.inventoryItems, id);
        expect(item['name'], 'Wall Socket Plate (Double)');
        expect(item['specification'], 'Double');
        expect(item['unitCost'], 85);
        expect(item['quantityAvailable'], 20);

        final ledger = await ledgerFor(id);
        expect(ledger, hasLength(1));
        expect(ledger.single['type'], 'replenishment');
        expect(ledger.single['quantityBefore'], 0);
        expect(ledger.single['quantityAfter'], 20);
        expect(ledger.single['performedByName'], admin.name);
        expect(
          (await h.auditEntries()).single['description'],
          'Added Wall Socket Plate (Double) to the inventory with 20 pcs',
        );
      },
    );

    test('with no opening stock, nothing is on the ledger', () async {
      final id = (await h.inventory.createItem(
        draft: material(),
        openingStock: 0,
        actor: admin,
      )).fold((id) => id, (f) => fail(f.message));

      expect(await ledgerFor(id), isEmpty);
      expect(
        (await h.doc(FirestorePaths.inventoryItems, id))['quantityAvailable'],
        0,
      );
    });

    test('a code already on a tool, room or material is refused', () async {
      await h.addTool('tool-1');
      await h.addInventoryItem('inv-1');

      expect(
        failureMessage(
          await h.inventory.createItem(
            draft: material(qrCode: 'TOOL-TL-0001'),
            openingStock: 0,
            actor: admin,
          ),
        ),
        'The code TOOL-TL-0001 is already on a tool.',
      );
      expect(
        failureMessage(
          await h.inventory.createItem(
            draft: material(qrCode: 'INV-INV-1'),
            openingStock: 0,
            actor: admin,
          ),
        ),
        'The code INV-INV-1 is already on a material.',
      );
      expect(
        failureMessage(
          await h.inventory.createItem(
            draft: material(name: '  '),
            openingStock: 0,
            actor: admin,
          ),
        ),
        'Enter the material’s name.',
      );
      expect(await h.count(FirestorePaths.inventoryItems), 1);
    });

    test('editing details never touches the stock, and is audited', () async {
      await h.addInventoryItem('inv-1');

      final saved = await h.inventory.updateItemDetails(
        itemId: 'inv-1',
        draft: material(name: 'LED Bulbs (60W Eq)', qrCode: 'INV-INV-1'),
        actor: admin,
      );
      expect(saved.isSuccess, isTrue);

      final item = await h.doc(FirestorePaths.inventoryItems, 'inv-1');
      expect(item['name'], 'LED Bulbs (60W Eq)');
      expect(item['quantityAvailable'], 10);
      final audit = (await h.auditEntries()).single;
      expect(audit['description'], 'Updated LED Bulbs (60W Eq)');
      expect(
        audit['changes'],
        containsPair('name', isA<Map<String, dynamic>>()),
      );
      expect(audit['changes'], isNot(contains('qrCode')));

      // Saving the same details again changes and records nothing.
      await h.inventory.updateItemDetails(
        itemId: 'inv-1',
        draft: material(name: 'LED Bulbs (60W Eq)', qrCode: 'INV-INV-1'),
        actor: admin,
      );
      expect(await h.auditEntries(), hasLength(1));
    });

    test('a delivery adds to the stock, on the ledger', () async {
      await h.addInventoryItem('inv-1', quantity: 3);

      final entry = (await h.inventory.recordDelivery(
        itemId: 'inv-1',
        quantity: 12,
        actor: admin,
        notes: ' PO 2026-114 ',
      )).fold((entry) => entry, (f) => fail(f.message));

      expect(entry.quantityAfter, 15);
      expect(
        (await h.doc(
          FirestorePaths.inventoryItems,
          'inv-1',
        ))['quantityAvailable'],
        15,
      );
      final ledger = (await ledgerFor('inv-1')).single;
      expect(ledger['type'], 'replenishment');
      expect(ledger['notes'], 'PO 2026-114');
      expect(
        failureMessage(
          await h.inventory.recordDelivery(
            itemId: 'inv-1',
            quantity: 0,
            actor: admin,
          ),
        ),
        'Enter a quantity above zero.',
      );
    });

    test(
      'a stock count corrects the balance either way, with a reason',
      () async {
        await h.addInventoryItem('inv-1');

        final down = (await h.inventory.recordStockCount(
          itemId: 'inv-1',
          countedQuantity: 7,
          actor: admin,
          reason: 'Three broken in storage',
        )).fold((entry) => entry, (f) => fail(f.message));
        expect(down.type.id, 'adjustment');
        expect(down.quantity, 3);
        expect(down.change, -3);

        final up = (await h.inventory.recordStockCount(
          itemId: 'inv-1',
          countedQuantity: 9,
          actor: admin,
          reason: 'Found a box on shelf C',
        )).fold((entry) => entry, (f) => fail(f.message));
        expect(up.change, 2);
        expect(
          (await h.doc(
            FirestorePaths.inventoryItems,
            'inv-1',
          ))['quantityAvailable'],
          9,
        );

        expect(
          failureMessage(
            await h.inventory.recordStockCount(
              itemId: 'inv-1',
              countedQuantity: 9,
              actor: admin,
              reason: 'Recount',
            ),
          ),
          'The count matches the record: 9 units.',
        );
        expect(
          failureMessage(
            await h.inventory.recordStockCount(
              itemId: 'inv-1',
              countedQuantity: 4,
              actor: admin,
              reason: ' ',
            ),
          ),
          'Say why the count differs.',
        );
        expect(await ledgerFor('inv-1'), hasLength(2));
      },
    );
  });

  group('requests and pre-assigned materials (6.B)', () {
    Future<void> addWork(WorkOrderStatus status) async {
      await h.addPersonnel(technician.id);
      await h.addReport('r1', workOrderId: 'w1');
      await h.addWorkOrder('w1', reportIds: ['r1'], status: status);
      await h.addInventoryItem('inv-plate', name: 'Socket Plate');
      await h.addInventoryItem(
        'inv-tape',
        name: 'Insulation Tape',
        quantity: 2,
      );
    }

    MaterialLine line(String itemId, double quantity) => MaterialLine(
      inventoryItemId: itemId,
      itemName: 'whatever the phone thought',
      quantity: quantity,
      unitOfMeasurement: 'units',
    );

    Future<String> fileRequest({
      List<MaterialLine>? items,
      String note = 'Two more outlets in the lobby are cracked.',
    }) async {
      final id = h.requests.newRequestId();
      final result = await h.requests.submit(
        requestId: id,
        workOrderId: 'w1',
        items: items ?? [line('inv-plate', 4)],
        actor: technician,
        note: note,
      );
      expect(failureMessage(result), isNull);
      return id;
    }

    test('a technician requests materials for their open work', () async {
      await addWork(WorkOrderStatus.inProgress);

      final id = await fileRequest(
        items: [
          line('inv-plate', 2),
          line('inv-tape', 1),
          line('inv-plate', 2),
        ],
      );

      final request = await h.doc(FirestorePaths.materialRequests, id);
      expect(request['status'], 'pending');
      expect(request['requestedBy'], technician.id);
      expect(request['requestedByName'], technician.name);
      expect(request['note'], 'Two more outlets in the lobby are cracked.');
      // Names come from the inventory, and a repeated item is added up.
      expect(request['items'], [
        {
          'inventoryItemId': 'inv-plate',
          'itemName': 'Socket Plate',
          'quantity': 4,
          'unitOfMeasurement': 'units',
        },
        {
          'inventoryItemId': 'inv-tape',
          'itemName': 'Insulation Tape',
          'quantity': 1,
          'unitOfMeasurement': 'units',
        },
      ]);
    });

    test('filing the same request again files it once', () async {
      await addWork(WorkOrderStatus.inProgress);
      final id = h.requests.newRequestId();
      for (var i = 0; i < 2; i++) {
        await h.requests.submit(
          requestId: id,
          workOrderId: 'w1',
          items: [line('inv-plate', 1)],
          actor: technician,
        );
      }
      expect(await h.count(FirestorePaths.materialRequests), 1);
    });

    test('not for work assigned to someone else, or no longer open', () async {
      await addWork(WorkOrderStatus.forReview);
      expect(
        failureMessage(
          await h.requests.submit(
            requestId: h.requests.newRequestId(),
            workOrderId: 'w1',
            items: [line('inv-plate', 1)],
            actor: technician,
          ),
        ),
        '#WO-W1 is For Review; materials can no longer be assigned to it.',
      );

      await h.addWorkOrder(
        'w2',
        reportIds: ['r1'],
        status: WorkOrderStatus.inProgress,
        assignedPersonnelIds: const ['personnel-2'],
      );
      expect(
        failureMessage(
          await h.requests.submit(
            requestId: h.requests.newRequestId(),
            workOrderId: 'w2',
            items: [line('inv-plate', 1)],
            actor: technician,
          ),
        ),
        'This work order is not assigned to you.',
      );
      expect(
        failureMessage(
          await h.requests.submit(
            requestId: h.requests.newRequestId(),
            workOrderId: 'w2',
            items: const [],
            actor: technician,
          ),
        ),
        'Add the materials you need.',
      );
      expect(await h.count(FirestorePaths.materialRequests), 0);
    });

    test(
      'approving adds the items to the job and tells the technician',
      () async {
        await addWork(WorkOrderStatus.inProgress);
        await h.allocations.allocate(
          workOrderId: 'w1',
          inventoryItemId: 'inv-plate',
          quantity: 1,
          actor: admin,
        );
        final id = await fileRequest();

        final approved = await h.requests.approve(
          requestId: id,
          actor: admin,
          note: 'Collect them from Shelf B.',
        );
        expect(failureMessage(approved), isNull);

        final plate = (await allocated('w1').doc('inv-plate').get()).data()!;
        expect(plate['quantity'], 5);
        expect(plate['itemName'], 'Socket Plate');
        final request = await h.doc(FirestorePaths.materialRequests, id);
        expect(request['status'], 'approved');
        expect(request['adminNote'], 'Collect them from Shelf B.');
        expect(request['reviewedBy'], admin.id);
        // Nothing moves on the shelf until the report is filed.
        expect(
          (await h.doc(
            FirestorePaths.inventoryItems,
            'inv-plate',
          ))['quantityAvailable'],
          10,
        );

        final notice = (await h.notifications()).singleWhere(
          (n) => n['recipientId'] == technician.id,
        );
        expect(notice['title'], 'Materials approved');
        expect(notice['relatedEntityId'], 'w1');

        expect(
          failureMessage(await h.requests.approve(requestId: id, actor: admin)),
          startsWith('#'),
        );
      },
    );

    test('approval is refused when the store holds less than asked', () async {
      await addWork(WorkOrderStatus.inProgress);
      final id = await fileRequest(items: [line('inv-tape', 5)]);

      expect(
        failureMessage(await h.requests.approve(requestId: id, actor: admin)),
        'Only 2 units of Insulation Tape in stock.',
      );
      expect(
        (await h.doc(FirestorePaths.materialRequests, id))['status'],
        'pending',
      );
      expect((await allocated('w1').get()).docs, isEmpty);
    });

    test('declining needs a reason, which the technician is told', () async {
      await addWork(WorkOrderStatus.inProgress);
      final id = await fileRequest();

      expect(
        failureMessage(
          await h.requests.decline(requestId: id, actor: admin, note: ' '),
        ),
        'Say why the request is declined.',
      );
      final declined = await h.requests.decline(
        requestId: id,
        actor: admin,
        note: 'Use the plates already on the job.',
      );
      expect(failureMessage(declined), isNull);

      final request = await h.doc(FirestorePaths.materialRequests, id);
      expect(request['status'], 'declined');
      final notice = (await h.notifications()).single;
      expect(notice['title'], 'Materials request declined');
      expect(notice['body'], contains('Use the plates already on the job.'));
    });

    test(
      'pre-assigning sets a quantity; not above stock or on closed work',
      () async {
        await addWork(WorkOrderStatus.pending);

        expect(
          failureMessage(
            await h.allocations.allocate(
              workOrderId: 'w1',
              inventoryItemId: 'inv-plate',
              quantity: 6,
              actor: admin,
            ),
          ),
          isNull,
        );
        await h.allocations.allocate(
          workOrderId: 'w1',
          inventoryItemId: 'inv-plate',
          quantity: 3,
          actor: admin,
        );
        expect(
          (await allocated('w1').doc('inv-plate').get()).data()!['quantity'],
          3,
        );
        expect(
          failureMessage(
            await h.allocations.allocate(
              workOrderId: 'w1',
              inventoryItemId: 'inv-tape',
              quantity: 3,
              actor: admin,
            ),
          ),
          'Only 2 units of Insulation Tape in stock.',
        );

        await h.allocations.remove(
          workOrderId: 'w1',
          inventoryItemId: 'inv-plate',
          actor: admin,
        );
        expect((await allocated('w1').get()).docs, isEmpty);

        await h.addWorkOrder(
          'w9',
          reportIds: ['r1'],
          status: WorkOrderStatus.completed,
        );
        expect(
          failureMessage(
            await h.allocations.allocate(
              workOrderId: 'w9',
              inventoryItemId: 'inv-plate',
              quantity: 1,
              actor: admin,
            ),
          ),
          '#WO-W9 is Completed; materials can no longer be assigned to it.',
        );
      },
    );
  });

  group('tools (6.B)', () {
    ToolDraft drill({String code = 'TL-0755', String? qrCode}) => ToolDraft(
      toolCode: code,
      name: 'Hilti Rotary Hammer Drill',
      condition: ItemCondition.good,
      qrCode: qrCode ?? ToolDraft.defaultQrCode(code),
      category: 'Power Tools',
    );

    test('a new tool goes on the shelf; its ID and code are its own', () async {
      final id = (await h.tools.createTool(
        draft: drill(code: 'tl-0755 '),
        actor: admin,
      )).fold((id) => id, (f) => fail(f.message));

      final tool = await h.doc(FirestorePaths.tools, id);
      expect(tool['toolCode'], 'TL-0755');
      expect(tool['qrCode'], 'TOOL-TL-0755');
      expect(tool['status'], 'available');

      expect(
        failureMessage(await h.tools.createTool(draft: drill(), actor: admin)),
        'Another tool already has the ID TL-0755.',
      );
      await h.addInventoryItem('inv-1');
      expect(
        failureMessage(
          await h.tools.createTool(
            draft: drill(code: 'TL-0999', qrCode: 'INV-INV-1'),
            actor: admin,
          ),
        ),
        'The code INV-INV-1 is already on a material.',
      );
    });

    test(
      'a tool goes to repair and back, or is retired; not while out',
      () async {
        await h.addTool('tool-1');

        Future<String?> move(ToolStatus status) async => failureMessage(
          await h.tools.setToolStatus(
            toolId: 'tool-1',
            status: status,
            actor: admin,
          ),
        );

        expect(await move(ToolStatus.inRepair), isNull);
        expect(
          (await h.doc(FirestorePaths.tools, 'tool-1'))['status'],
          'inRepair',
        );
        expect(await move(ToolStatus.available), isNull);
        expect(
          (await h.auditEntries()).last['description'],
          'Brought Fluke Multimeter back from repair',
        );

        await h.addTool('tool-2', status: ToolStatus.borrowed);
        expect(
          failureMessage(
            await h.tools.setToolStatus(
              toolId: 'tool-2',
              status: ToolStatus.inRepair,
              actor: admin,
            ),
          ),
          'Fluke Multimeter is out with a technician; check it in first.',
        );

        expect(await move(ToolStatus.retired), isNull);
        expect(
          await move(ToolStatus.available),
          'Fluke Multimeter is retired.',
        );
      },
    );

    test('the console checks a tool out to a technician', () async {
      await h.addPersonnel(technician.id);
      await h.addTool('tool-1');

      final loan = (await h.tools.borrowTool(
        toolId: 'tool-1',
        borrower: technician,
        issuedBy: admin,
        workOrderId: 'w1',
      )).fold((loan) => loan, (f) => fail(f.message));

      expect(loan.borrowedBy, technician.id);
      final tool = await h.doc(FirestorePaths.tools, 'tool-1');
      expect(tool['status'], 'borrowed');
      expect(tool['currentHolderId'], technician.id);
      final audit = (await h.auditEntries()).single;
      expect(audit['actorId'], admin.id);
      expect(
        audit['description'],
        'Checked out Fluke Multimeter to Marcus Wright for #WO-W1',
      );
    });

    test('editing a tool that is out keeps the condition it left in', () async {
      await h.addTool('tool-1', status: ToolStatus.borrowed);

      await h.tools.updateToolDetails(
        toolId: 'tool-1',
        draft: const ToolDraft(
          toolCode: 'TL-0001',
          name: 'Fluke 179 Multimeter',
          condition: ItemCondition.poor,
          qrCode: 'TOOL-TL-0001',
        ),
        actor: admin,
      );

      final tool = await h.doc(FirestorePaths.tools, 'tool-1');
      expect(tool['name'], 'Fluke 179 Multimeter');
      expect(tool['condition'], 'good');
      expect(tool['status'], 'borrowed');
    });
  });

  group('rooms and equipment (6.C)', () {
    test(
      'a new room takes its building as its name and a code from its id',
      () async {
        final id = (await h.facilities.createFacility(
          draft: const FacilityDraft(
            buildingName: ' Engineering Building ',
            roomIdentifier: 'Room 305',
            latitude: 7.2048,
            longitude: 126.5354,
          ),
          actor: admin,
        )).fold((id) => id, (f) => fail(f.message));

        final room = await h.doc(FirestorePaths.facilities, id);
        expect(room['name'], 'Engineering Building');
        expect(room['buildingName'], 'Engineering Building');
        expect(room['locationDescription'], 'Engineering Building, Room 305');
        expect(room['qrCode'], 'FAC-${id.toUpperCase()}');
        expect(room['isActive'], isTrue);
        expect(room['coordinates'], isA<GeoPoint>());
        expect(
          (await h.auditEntries()).single['description'],
          'Added Engineering Building, Room 305',
        );
      },
    );

    test('a room is edited, deactivated and reactivated', () async {
      final id = (await h.facilities.createFacility(
        draft: const FacilityDraft(
          buildingName: 'Gymnasium',
          qrCode: 'FAC-GYM',
        ),
        actor: admin,
      )).fold((id) => id, (f) => fail(f.message));

      await h.facilities.updateFacility(
        facilityId: id,
        draft: const FacilityDraft(
          buildingName: 'Gymnasium',
          roomIdentifier: 'Main Court',
        ),
        actor: admin,
      );
      var room = await h.doc(FirestorePaths.facilities, id);
      expect(room['roomIdentifier'], 'Main Court');
      // Left empty, the code stays as it was.
      expect(room['qrCode'], 'FAC-GYM');

      await h.facilities.setFacilityActive(
        facilityId: id,
        active: false,
        actor: admin,
      );
      room = await h.doc(FirestorePaths.facilities, id);
      expect(room['isActive'], isFalse);
      expect(
        (await h.facilities.getFacilities()).fold(
          (l) => l,
          (f) => fail(f.message),
        ),
        isEmpty,
      );

      expect(
        failureMessage(
          await h.facilities.createFacility(
            draft: const FacilityDraft(
              buildingName: 'Annex',
              qrCode: 'FAC-GYM',
            ),
            actor: admin,
          ),
        ),
        'The code FAC-GYM is already on a room.',
      );
      expect(
        failureMessage(
          await h.facilities.createFacility(
            draft: const FacilityDraft(buildingName: 'Annex', latitude: 7),
            actor: admin,
          ),
        ),
        'Enter both the latitude and the longitude, or neither.',
      );
    });

    test('equipment belongs to a registered room', () async {
      final roomId = (await h.facilities.createFacility(
        draft: const FacilityDraft(buildingName: 'Science Building'),
        actor: admin,
      )).fold((id) => id, (f) => fail(f.message));

      final assetId = (await h.facilities.createAsset(
        draft: AssetDraft(
          name: 'Ceiling Fan',
          facilityId: roomId,
          condition: ItemCondition.fair,
        ),
        actor: admin,
      )).fold((id) => id, (f) => fail(f.message));
      final asset = await h.doc(FirestorePaths.assets, assetId);
      expect(asset['qrCode'], 'AST-${assetId.toUpperCase()}');
      expect(asset['facilityId'], roomId);

      expect(
        failureMessage(
          await h.facilities.createAsset(
            draft: const AssetDraft(
              name: 'Projector',
              facilityId: 'nowhere',
              condition: ItemCondition.good,
            ),
            actor: admin,
          ),
        ),
        'That room is not registered.',
      );
    });
  });
}
