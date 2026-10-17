-- The inventory (Objective 1, M4): materials, deliveries, stock counts.
-- Stock moves only through ledger entries.

begin;
select tests.create_fixtures();
select plan(19);

select isnt(
  tests.query_as('u-admin', $$select public.create_inventory_item('12/2 Wire ', 'Electrical', '250ft', 'rolls',
    'Store A', 'INV-WIRE', 2, 3850, null, 34)$$),
  null,
  'an administrator adds a material with its opening stock'
);
select is(
  (select array[i.name, i.quantity_available::text, t.type, t.quantity_before::text, t.quantity_after::text, t.notes]
     from public.inventory_items i join public.inventory_transactions t on t.inventory_item_id = i.id
     where i.qr_code = 'INV-WIRE'),
  array['12/2 Wire', '34', 'replenishment', '0', '34', 'Opening stock'],
  '…the opening stock is its first ledger entry'
);
select is(
  (select description from public.audit_logs where entity_type = 'inventory_items' and action = 'created'),
  'Added 12/2 Wire to the inventory with 34 rolls',
  '…and it is audited'
);
select is(
  tests.attempt('u-admin', $$select public.create_inventory_item('Tape', 'Electrical', null, 'rolls',
    'Store A', 'INV-TAPE', 0, null, null, 0)$$),
  'ok',
  'a material may start with nothing'
);
select is(
  (select array[(select quantity_available::text from public.inventory_items where qr_code = 'INV-TAPE'),
                (select count(*)::text from public.inventory_transactions t join public.inventory_items i on i.id = t.inventory_item_id where i.qr_code = 'INV-TAPE')]),
  array['0', '0'],
  '…and then has no ledger entry'
);
select is(
  tests.attempt('u-admin', $$select public.create_inventory_item('X', 'Electrical', null, 'rolls',
    'Store A', 'INV-X', 0, null, null, -1)$$),
  'PT422',
  'opening stock is never below zero'
);
select is(
  tests.error_of('u-admin', $$select public.create_inventory_item('X', 'Electrical', null, 'rolls',
    'Store A', 'FAC-F-1', 0, null, null, 0)$$),
  'The code FAC-F-1 is already on a room.',
  'nor under a code something else carries'
);
select is(
  tests.attempt('u-tech', $$select public.create_inventory_item('X', 'Electrical', null, 'rolls',
    'Store A', 'INV-Y', 0, null, null, 0)$$),
  'PT403',
  'a technician does not add materials'
);

select is(
  tests.attempt('u-admin', $$select public.update_inventory_item('i-1', 'LED Bulbs (60W)', 'Electrical', null, 'units',
    'Store B', 'INV-I-1', 5, null, null)$$),
  'ok',
  'an administrator edits a material''s details'
);
select is(
  (select array[changes -> 'name' ->> 'to', changes -> 'storageLocation' ->> 'to',
                (select quantity_available::text from public.inventory_items where id = 'i-1')]
     from public.audit_logs where entity_id = 'i-1'),
  array['LED Bulbs (60W)', 'Store B', '20'],
  '…the change is audited, and the stock is not among the details'
);
select is(
  tests.attempt('u-admin', $$select public.update_inventory_item('i-gone', 'X', 'Electrical', null, 'units',
    'Store B', 'INV-GONE', 0, null, null)$$),
  'PT404',
  'a material that is gone is not found'
);

select is(
  tests.query_as('u-admin', $$select (public.record_delivery('i-1', 5, ' From the supplier ')).quantity_after::text$$),
  '25',
  'a delivery adds to the stock, and answers with its ledger entry'
);
select is(
  (select array[t.type, t.notes, t.performed_by_name, i.quantity_available::text]
     from public.inventory_transactions t join public.inventory_items i on i.id = t.inventory_item_id
     where t.notes = 'From the supplier'),
  array['replenishment', 'From the supplier', 'Ramon Dela Cruz', '25'],
  '…recorded under the administrator'
);
select is(
  tests.attempt('u-admin', $$select public.record_delivery('i-1', 0)$$),
  'PT422',
  'a delivery of nothing is refused'
);
select is(
  tests.query_as('u-admin', $$select (select array[quantity, quantity_before, quantity_after]::text
    from public.record_stock_count('i-1', 22, ' Three broken in storage ') entry)$$),
  '{3,25,22}',
  'a stock count records the size of the correction and sets the counted balance'
);
select is(
  tests.error_of('u-admin', $$select public.record_stock_count('i-1', 22, 'Counted again')$$),
  'The count matches the record: 22 units.',
  'a count that matches the record is refused'
);
select is(
  tests.error_of('u-admin', $$select public.record_stock_count('i-1', 21, '  ')$$),
  'Say why the count differs.',
  'a count that differs says why'
);
select is(
  tests.attempt('u-admin', $$select public.record_stock_count('i-1', -1, 'Lost')$$),
  'PT422',
  'and is never below zero'
);
select is(
  tests.attempt('u-tech', $$select public.record_stock_count('i-1', 30, 'Found some')$$)
    || tests.attempt('u-tech', $$select public.record_delivery('i-1', 30)$$),
  'PT403PT403',
  'a technician neither counts nor receives stock'
);

select * from finish();
rollback;
