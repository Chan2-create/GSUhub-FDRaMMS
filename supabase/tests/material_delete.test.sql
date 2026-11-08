-- Deleting a material (2026-11-05): it leaves the inventory, keeps its
-- history, and nothing new happens to it. Refused while open work still
-- counts on it.

begin;
select tests.create_fixtures();
select plan(20);

select is(
  tests.attempt('u-tech', $$select public.delete_inventory_item('i-1')$$),
  'PT403',
  'a technician does not delete materials'
);
select is(
  tests.attempt('u-admin', $$select public.delete_inventory_item('i-gone')$$),
  'PT404',
  'a material that is not there is not found'
);

-- The fixtures record LED Bulbs as used on, and set aside for, both work
-- orders, and both technicians have asked for some.
select matches(
  tests.error_of('u-admin', $$select public.delete_inventory_item('i-1')$$),
  '^LED Bulbs is recorded as used on #W-[12] and comes off stock when that work is finished\. Delete it after that\.$',
  'a material recorded as used on open work is kept'
);
update public.work_orders set status = 'completed' where id = 'w-1';
delete from public.work_order_materials_used where work_order_id = 'w-2';
select matches(
  tests.error_of('u-admin', $$select public.delete_inventory_item('i-1')$$),
  '^LED Bulbs is set aside for #W-2\. Take it off that work order first\.$',
  '…and one set aside for open work; finished work no longer counts'
);
delete from public.work_order_materials_allocated where work_order_id = 'w-2';
select matches(
  tests.error_of('u-admin', $$select public.delete_inventory_item('i-1')$$),
  '^LED Bulbs is on #M-[12], a material request waiting for review\. Approve or decline it first\.$',
  '…and one asked for in a request waiting for review'
);
update public.material_requests set status = 'declined' where id in ('m-1', 'm-2');

select is(
  tests.attempt('u-admin', $$select public.delete_inventory_item('i-1')$$),
  'ok',
  'then an administrator deletes it'
);
select is(
  (select array[(deleted_at is not null)::text, quantity_available::text, qr_code]
     from public.inventory_items where id = 'i-1'),
  array['true', '20', 'INV-I-1'],
  '…it is marked deleted, and its stock and code are as they were'
);
select is(
  (select count(*)::int from public.inventory_transactions where inventory_item_id = 'i-1'),
  1,
  '…its stock history stays'
);
select is(
  (select array[action, description] from public.audit_logs
     where entity_type = 'inventory_items' and entity_id = 'i-1'),
  array['deleted', 'Deleted LED Bulbs from the inventory, with 20 units still recorded'],
  '…and the deletion is audited, with the stock it still had'
);
select is(
  tests.attempt('u-admin', $$select public.delete_inventory_item('i-1')$$)
    || (select count(*)::text from public.audit_logs where entity_id = 'i-1'),
  'ok1',
  'deleting it again does nothing'
);

-- Nothing new happens to it.
select is(
  tests.error_of('u-admin', $$select public.record_delivery('i-1', 5)$$),
  'LED Bulbs is no longer in the inventory.',
  'no delivery'
);
select is(
  tests.attempt('u-admin', $$select public.record_stock_count('i-1', 3, 'Found some')$$),
  'PT404',
  'no stock count'
);
select is(
  tests.attempt('u-admin', $$select public.update_inventory_item('i-1', 'LED Bulbs', 'Electrical', null, 'units',
    'Store C', 'INV-I-1', 5, null, null)$$),
  'PT404',
  'no edit'
);
update public.work_orders set status = 'inProgress' where id = 'w-1';
select is(
  tests.error_of('u-tech', $$select public.record_material_use('w-1', 'i-1', 1)$$),
  'LED Bulbs is no longer in the inventory.',
  'a technician cannot record it as used'
);
select is(
  tests.attempt('u-admin', $$select public.allocate_material('w-1', 'i-1', 1)$$),
  'PT404',
  'nor can an administrator set it aside'
);
select is(
  tests.error_of('u-tech', $$select public.submit_material_request('m-new', 'w-1',
    '[{"inventoryItemId": "i-1", "quantity": 2}]')$$),
  'LED Bulbs is no longer in the inventory.',
  'nor a technician ask for it'
);
select is(
  tests.attempt('u-tech', $$select public.submit_accomplishment('ac-new', 'w-1', 'Replaced the bulbs.',
    array['x.jpg'],
    '[{"inventoryItemId": "i-1", "itemName": "LED Bulbs", "quantityUsed": 1, "unitOfMeasurement": "units"}]')$$),
  'PT404',
  'nor does a filed accomplishment report take it off stock'
);
select is(
  (select quantity_available::text from public.inventory_items where id = 'i-1'),
  '20',
  '…its stock never moved'
);

-- Its code is free.
select isnt(
  tests.query_as('u-admin', $$select public.create_inventory_item('LED Bulbs (new)', 'Electrical', null, 'units',
    'Store A', 'INV-I-1', 5, null, null, 10)$$),
  null,
  'another material may take its code'
);
select is(
  tests.error_of('u-admin', $$select public.create_inventory_item('LED Bulbs (copy)', 'Electrical', null, 'units',
    'Store A', 'INV-I-1', 5, null, null, 0)$$),
  'The code INV-I-1 is already on a material.',
  '…but only one material still in the inventory'
);

select * from finish();
rollback;
