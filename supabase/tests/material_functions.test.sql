-- Materials on a work order (Objective 1, M4): recorded as used, set
-- aside, requested.

begin;
select tests.create_fixtures();
select plan(33);

insert into public.work_orders (id, report_ids, title, description, category, priority, status, assigned_personnel_ids, created_by) values
  ('w-done', array['r-4'], 'Old job', 'Done.', 'electrical', 'low', 'completed', array['u-tech'], 'u-admin');

-- ---------------------------------------------------------------- recorded as used

select is(
  tests.attempt('u-tech', $$select public.record_material_use('w-1', 'i-1', 3)$$),
  'ok',
  'the technician records what the work used'
);
select is(
  (select array[quantity_used::text, item_name, unit_of_measurement, recorded_by]
     from public.work_order_materials_used where work_order_id = 'w-1' and inventory_item_id = 'i-1'),
  array['3', 'LED Bulbs', 'units', 'u-tech'],
  '…replacing what was recorded, named and measured from the inventory'
);
select is(
  (select quantity_available from public.inventory_items where id = 'i-1'),
  20::double precision,
  '…and no stock moves until the accomplishment report'
);
select is(
  tests.error_of('u-tech', $$select public.record_material_use('w-1', 'i-1', 100)$$),
  'Only 20 units of LED Bulbs in stock.',
  'not more than is in stock'
);
select is(
  tests.attempt('u-tech', $$select public.record_material_use('w-1', 'i-1', 0)$$),
  'PT422',
  'nor nothing'
);
select is(
  tests.error_of('u-tech2', $$select public.record_material_use('w-1', 'i-1', 1)$$),
  'This work order is not assigned to you.',
  'nor on someone else''s work'
);
select is(
  tests.error_of('u-tech', $$select public.record_material_use('w-done', 'i-1', 1)$$),
  'This work order is Completed; materials can no longer be recorded on it.',
  'nor on finished work'
);
select is(
  tests.attempt('u-req', $$select public.record_material_use('w-1', 'i-1', 1)$$),
  'PT403',
  'a requestor records nothing'
);
select is(
  tests.attempt('u-tech2', $$select public.remove_material_use('w-1', 'i-1')$$),
  'PT403',
  'a technician cannot take a line off someone else''s work'
);
select is(
  tests.attempt('u-tech', $$select public.remove_material_use('w-1', 'i-1')$$),
  'ok',
  'but takes one off their own'
);
select is(
  (select count(*)::int from public.work_order_materials_used where work_order_id = 'w-1'),
  0,
  '…which is gone'
);

-- ---------------------------------------------------------------- set aside

select is(
  tests.attempt('u-admin', $$select public.allocate_material('w-1', 'i-1', 6)$$),
  'ok',
  'an administrator sets materials aside for the work'
);
select is(
  (select quantity from public.work_order_materials_allocated where work_order_id = 'w-1' and inventory_item_id = 'i-1'),
  6::double precision,
  '…replacing what was set aside'
);
select is(
  (select description from public.audit_logs where entity_id = 'w-1'),
  'Pre-assigned 6 units of LED Bulbs to #W-1',
  '…and it is audited'
);
select is(
  tests.error_of('u-admin', $$select public.allocate_material('w-1', 'i-1', 21)$$),
  'Only 20 units of LED Bulbs in stock.',
  'not more than is in stock'
);
select is(
  tests.error_of('u-admin', $$select public.allocate_material('w-done', 'i-1', 1)$$),
  '#W-DONE is Completed; materials can no longer be assigned to it.',
  'not to finished work'
);
select is(
  tests.attempt('u-tech', $$select public.allocate_material('w-1', 'i-1', 1)$$),
  'PT403',
  'a technician sets nothing aside for themselves'
);
select is(
  tests.attempt('u-admin', $$select public.remove_allocation('w-1', 'i-1')$$)
    || tests.attempt('u-admin', $$select public.remove_allocation('w-1', 'i-1')$$),
  'okok',
  'an administrator takes it off again, and twice is fine'
);
select is(
  (select string_agg(description, ' | ' order by "timestamp", description) from public.audit_logs
     where entity_id = 'w-1' and description like 'Took%'),
  'Took LED Bulbs off #W-1’s pre-assigned materials',
  '…audited once'
);

-- ---------------------------------------------------------------- requests

select is(
  tests.attempt('u-tech', $$select public.submit_material_request('m-new', 'w-1',
    '[{"inventoryItemId":"i-1","quantity":2},{"inventoryItemId":"i-1","quantity":1}]', ' For the hallway ')$$),
  'ok',
  'the technician asks for materials'
);
select is(
  (select array[items::text, requested_by_name, note, status]
     from public.material_requests where id = 'm-new'),
  array['[{"itemName": "LED Bulbs", "quantity": 3, "inventoryItemId": "i-1", "unitOfMeasurement": "units"}]',
        'Marcus Wright', 'For the hallway', 'pending'],
  '…the same material twice is one line, named and measured from the inventory'
);
select is(
  (select description from public.audit_logs where entity_id = 'm-new'),
  'Requested 3 units of LED Bulbs for #W-1',
  '…and the request is audited'
);
select is(
  tests.attempt('u-tech', $$select public.submit_material_request('m-new', 'w-1', '[{"inventoryItemId":"i-1","quantity":9}]')$$)
    || ':' || tests.error_of('u-tech', $$select public.submit_material_request('m-x', 'w-1', '[]')$$),
  'ok:Add the materials you need.',
  'filing again is a retry; a request needs materials'
);
select is(
  tests.error_of('u-tech', $$select public.submit_material_request('m-x', 'w-1',
    (select jsonb_agg(jsonb_build_object('inventoryItemId', 'i-' || n, 'quantity', 1)) from generate_series(1, 21) n))$$),
  'Ask for at most 20 materials at a time.',
  'at most twenty of them'
);
select is(
  tests.error_of('u-tech2', $$select public.submit_material_request('m-x', 'w-1', '[{"inventoryItemId":"i-1","quantity":1}]')$$),
  'This work order is not assigned to you.',
  'only for one''s own work'
);

insert into public.work_order_materials_allocated (work_order_id, inventory_item_id, item_name, quantity, unit_of_measurement, allocated_by)
values ('w-1', 'i-1', 'LED Bulbs', 4, 'units', 'u-admin');
select is(
  tests.attempt('u-admin', $$select public.approve_material_request('m-new', ' Pick them up at noon. ')$$),
  'ok',
  'an administrator approves the request'
);
select is(
  (select array[(select quantity::text from public.work_order_materials_allocated where work_order_id = 'w-1' and inventory_item_id = 'i-1'),
                status, admin_note, reviewed_by]
     from public.material_requests where id = 'm-new'),
  array['7', 'approved', 'Pick them up at noon.', 'u-admin'],
  '…which adds to what was already set aside (4 + 3)'
);
select is(
  (select body from public.notifications where recipient_id = 'u-tech' and title = 'Materials approved'),
  'GSU approved request #M-NEW for "Flickering lights". The materials are on the work order. GSU: "Pick them up at noon."',
  '…and tells the technician'
);
select is(
  tests.error_of('u-admin', $$select public.decline_material_request('m-new', 'Changed my mind')$$),
  '#M-NEW was already approved.',
  'a request is answered once'
);
select is(
  tests.error_of('u-admin', $$select public.decline_material_request('m-2', '  ')$$)
    || ' / ' || tests.attempt('u-admin', $$select public.decline_material_request('m-2', 'Out of budget')$$),
  'Say why the request is declined. / ok',
  'an administrator declines one, saying why'
);
select is(
  (select array[r.status, n.body] from public.material_requests r, public.notifications n
     where r.id = 'm-2' and n.recipient_id = 'u-tech2' and n.title = 'Materials request declined'),
  array['declined', 'GSU declined request #M-2 for "Leaking pipe": "Out of budget"'],
  '…and the technician is told'
);

insert into public.material_requests (id, work_order_id, requested_by, requested_by_name, items) values
  ('m-big', 'w-1', 'u-tech', 'Marcus Wright', '[{"inventoryItemId":"i-1","itemName":"LED Bulbs","quantity":50,"unitOfMeasurement":"units"}]');
select is(
  tests.error_of('u-admin', $$select public.approve_material_request('m-big')$$),
  'Only 20 units of LED Bulbs in stock.',
  'a request for more than is in stock is not approved…'
);
select is(
  (select status from public.material_requests where id = 'm-big'),
  'pending',
  '…and stays waiting'
);

select * from finish();
rollback;
