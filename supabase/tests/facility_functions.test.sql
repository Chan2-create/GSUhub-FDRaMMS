-- Rooms and equipment (Objective 1, M3).

begin;
select tests.create_fixtures();
select plan(26);

-- ---------------------------------------------------------------- rooms

select is(
  tests.query_as('u-admin', $$select public.create_facility('f-new', ' Science Building ', 'Lab 2', null, 7.1, 126.5, 'FAC-F-NEW')$$),
  'f-new',
  'an administrator adds a room, and gets its id back'
);
select is(
  (select array[name, building_name, room_identifier, location_description, latitude::text, qr_code, is_active::text]
     from public.facilities where id = 'f-new'),
  array['Science Building', 'Science Building', 'Lab 2', 'Science Building, Lab 2', '7.1', 'FAC-F-NEW', 'true'],
  '…named after its building, described by building and room when no description is given'
);
select is(
  (select array[actor_name, action, description] from public.audit_logs where entity_id = 'f-new'),
  array['Ramon Dela Cruz', 'created', 'Added Science Building, Lab 2'],
  '…and audited'
);

select is(
  tests.error_of('u-admin', $$select public.create_facility('f-x', 'X', null, null, null, null, 'FAC-F-1')$$),
  'The code FAC-F-1 is already on a room.',
  'a code another room carries is refused'
);
select is(
  tests.error_of('u-admin', $$select public.create_facility('f-x', 'X', null, null, null, null, 'INV-I-1')$$),
  'The code INV-I-1 is already on a material.',
  '…and one a material carries: one scanner reads every label'
);
select is(
  tests.error_of('u-admin', $$select public.create_facility('f-x', 'X', null, null, null, null, 'TOOL-TL-0001')$$),
  'The code TOOL-TL-0001 is already on a tool.',
  '…or a tool'
);
select is(
  tests.error_of('u-admin', $$select public.create_facility('f-x', 'X', null, null, null, null, 'AST-A-1')$$),
  'The code AST-A-1 is already on equipment.',
  '…or equipment'
);
select is(
  tests.attempt('u-req', $$select public.create_facility('f-x', 'X', null, null, null, null, 'FAC-X')$$),
  'PT403',
  'a requestor cannot add rooms'
);
select is(
  tests.attempt('u-admin', $$select public.create_facility('f-x', 'X', null, null, 7.1, null, 'FAC-X')$$),
  '23514',
  'a latitude without a longitude is refused by the table'
);

select is(
  tests.attempt('u-admin', $$select public.update_facility('f-1', 'Engineering Building', 'Room 102', null, null, null)$$),
  'ok',
  'an administrator moves a room''s label'
);
select is(
  (select array[description, changes -> 'roomIdentifier' ->> 'from', changes -> 'roomIdentifier' ->> 'to', (select qr_code from public.facilities where id = 'f-1')]
     from public.audit_logs where entity_id = 'f-1' and action = 'updated'),
  array['Updated Engineering Building, Room 102', 'Room 101', 'Room 102', 'FAC-F-1'],
  '…the change is audited, and the code is kept when none is given'
);
select is(
  tests.attempt('u-admin', $$select public.update_facility('f-1', 'Engineering Building', 'Room 102', null, null, null)$$),
  'ok',
  'saving it again unchanged succeeds…'
);
select is(
  (select count(*)::int from public.audit_logs where entity_id = 'f-1'),
  1,
  '…and writes nothing'
);
select is(
  tests.attempt('u-admin', $$select public.update_facility('f-1', 'Engineering Building', 'Room 102', null, null, null, 'FAC-F-2')$$),
  'PT409',
  'a room cannot take another room''s code'
);
select is(
  tests.attempt('u-admin', $$select public.update_facility('f-nowhere', 'X', null, null, null, null)$$),
  'PT404',
  'an unknown room is not found'
);

select is(
  tests.attempt('u-admin', $$select public.set_facility_active('f-2', true)$$),
  'ok',
  'an administrator reactivates a room'
);
select is(
  (select description from public.audit_logs where entity_id = 'f-2'),
  'Reactivated Gymnasium, Main Court',
  '…and the audit names it'
);
select is(
  tests.attempt('u-tech', $$select public.set_facility_active('f-1', false)$$),
  'PT403',
  'a technician cannot deactivate rooms'
);

-- ---------------------------------------------------------------- equipment

select is(
  tests.query_as('u-admin', $$select public.create_asset('a-new', 'Aircon Unit', 'f-1', 'good', 'HVAC', null, 'AST-A-NEW')$$),
  'a-new',
  'an administrator adds equipment to a room'
);
select is(
  (select array[name, facility_id, condition, category, coalesce(serial_number, '-')] from public.assets where id = 'a-new'),
  array['Aircon Unit', 'f-1', 'good', 'HVAC', '-'],
  '…as entered'
);
select is(
  tests.error_of('u-admin', $$select public.create_asset('a-x', 'Fan', 'f-nowhere', 'good', null, null, 'AST-X')$$),
  'That room is not registered.',
  'not in a room that does not exist'
);
select is(
  tests.attempt('u-admin', $$select public.update_asset('a-1', 'Ceiling Fan', 'f-1', 'poor', null, 'SN-1')$$),
  'ok',
  'an administrator updates equipment'
);
select is(
  (select array[description, changes -> 'condition' ->> 'to', changes -> 'serialNumber' ->> 'to']
     from public.audit_logs where entity_id = 'a-1'),
  array['Updated Ceiling Fan', 'poor', 'SN-1'],
  '…and the audit says what changed'
);
select is(
  tests.attempt('u-admin', $$select public.set_asset_active('a-1', false)$$),
  'ok',
  'an administrator retires equipment'
);
select is(
  (select array[(select is_active::text from public.assets where id = 'a-1'), description]
     from public.audit_logs where entity_id = 'a-1' and action = 'statusChanged'),
  array['false', 'Deactivated Ceiling Fan'],
  '…which is kept, inactive, with its history'
);
select is(
  tests.attempt('u-req', $$select public.update_asset('a-1', 'Mine now', 'f-1', 'good', null, null)$$),
  'PT403',
  'a requestor cannot change equipment'
);

select * from finish();
rollback;
