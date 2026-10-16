-- The stock ledger (Objective 1, item 1): a quantity cannot change without
-- its history row, and the history cannot be rewritten.

begin;
select tests.create_fixtures();
select plan(17);

-- i-1 starts with the fixture's opening delivery: 20 units.
select is(
  (select quantity_available from public.inventory_items where id = 'i-1'),
  20::double precision,
  'the opening delivery set the stock'
);
select is(
  (select array[quantity_before, quantity_after] from public.inventory_transactions where id = 'l-1'),
  array[0, 20]::double precision[],
  'the ledger recorded the balances it produced, not the ones it was given'
);

-- A technician's account cannot touch the quantity.
select is(
  tests.attempt('u-tech', $$update public.inventory_items set quantity_available = 999 where id = 'i-1'$$),
  '42501',
  'a technician cannot change a quantity directly'
);
select is(
  tests.attempt('u-tech', $$insert into public.inventory_transactions (inventory_item_id, item_name, type, quantity, quantity_before, quantity_after, performed_by) values ('i-1', 'LED Bulbs', 'replenishment', 5, 0, 0, 'u-tech')$$),
  '42501',
  'a technician cannot write the ledger directly either'
);
select is(
  tests.attempt('u-admin', $$update public.inventory_items set quantity_available = 999 where id = 'i-1'$$),
  '42501',
  'nor can an administrator'
);

-- Not even the table owner, or code running as it (an RPC), changes a
-- quantity except through the ledger.
select throws_ok(
  $$update public.inventory_items set quantity_available = 999 where id = 'i-1'$$,
  'PT403',
  'Stock changes only through the inventory ledger.',
  'the database owner cannot change a quantity directly'
);
select throws_ok(
  $$insert into public.inventory_items (id, name, category, unit_of_measurement, storage_location, qr_code, quantity_available) values ('i-new', 'Tape', 'Electrical', 'rolls', 'Store', 'INV-NEW', 7)$$,
  'PT403',
  'A new material starts at zero; its opening stock is a ledger entry.',
  'a new material cannot arrive with stock that has no ledger entry'
);
select lives_ok(
  $$update public.inventory_items set name = 'LED Bulbs (60W)', updated_at = now() where id = 'i-1'$$,
  'its other details may change'
);

-- Through the ledger: deliveries add, use subtracts, a count sets.
insert into public.inventory_transactions (id, inventory_item_id, type, quantity, performed_by)
values ('l-2', 'i-1', 'consumption', 6, 'u-tech');
select is(
  (select quantity_available from public.inventory_items where id = 'i-1'),
  14::double precision,
  'a consumption entry takes stock off'
);
select throws_ok(
  $$insert into public.inventory_transactions (inventory_item_id, type, quantity, performed_by) values ('i-1', 'consumption', 15, 'u-tech')$$,
  'PT409',
  'Only 14 units of LED Bulbs (60W) in stock.',
  'stock cannot go below zero'
);
insert into public.inventory_transactions (id, inventory_item_id, type, quantity, quantity_after, performed_by, notes)
values ('l-3', 'i-1', 'adjustment', 1, 11, 'u-admin', 'Three broken in storage');
select is(
  (select array[quantity, quantity_before, quantity_after] from public.inventory_transactions where id = 'l-3'),
  array[3, 14, 11]::double precision[],
  'a stock count records the size of the correction'
);
select is(
  (select quantity_available from public.inventory_items where id = 'i-1'),
  11::double precision,
  'and sets the counted balance'
);
select throws_ok(
  $$insert into public.inventory_transactions (inventory_item_id, type, quantity, quantity_after, performed_by) values ('i-1', 'adjustment', 1, 11, 'u-admin')$$,
  'PT409',
  'The count matches the record: 11 units.',
  'a count that matches the record is refused'
);

-- The ledger and the audit log are insert-only, for everyone.
select throws_ok(
  $$update public.inventory_transactions set quantity = 1 where id = 'l-1'$$,
  'PT403',
  null,
  'a ledger entry cannot be changed, even by the owner'
);
select throws_ok(
  $$delete from public.inventory_transactions where id = 'l-1'$$,
  'PT403',
  null,
  'nor removed'
);
select throws_ok(
  $$update public.audit_logs set description = 'nothing happened' where id = 'au-1'$$,
  'PT403',
  null,
  'an audit entry cannot be changed'
);
select throws_ok(
  $$update public.report_status_history set status = 'closed' where id = 'h-1'$$,
  'PT403',
  null,
  'nor a timeline entry'
);

select * from finish();
rollback;
