-- Test helpers and fixtures, shared by the other test files.
--
-- `supabase test db` runs the files in name order on one database, and this
-- one is not rolled back, so what it creates is there for the rest. (The
-- Docker-free runner, tool/sql_tests/run.mjs, applies it before each file.)
-- Nothing here is a migration: the app's database never has a `tests`
-- schema.

begin;
select plan(1);

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Rows that were there before the fixtures: the demo data, when the
-- tests run after `supabase db reset` loaded supabase/seed.sql. Visibility
-- checks look at the fixtures only, so they hold on an empty database and
-- on a seeded one.
create table if not exists tests.pre_existing (tbl text, key text);
grant select on tests.pre_existing to anon, authenticated, service_role;

-- Fixtures: a small world with every role and every relationship the
-- policies distinguish. Inserted as the database owner, past row level
-- security, as a test's preconditions should be.
create or replace function tests.create_fixtures()
returns void
language plpgsql
set search_path = ''
as $$
declare
  t record;
begin
  delete from tests.pre_existing;
  for t in
    select * from (values
      ('users', 'id'), ('facilities', 'id'), ('assets', 'id'),
      ('damage_reports', 'id'), ('report_status_history', 'id'),
      ('work_orders', 'id'), ('work_order_materials_used', 'work_order_id'),
      ('work_order_materials_allocated', 'work_order_id'), ('tasks', 'id'),
      ('accomplishment_reports', 'id'), ('inventory_items', 'id'),
      ('inventory_transactions', 'id'), ('material_requests', 'id'),
      ('tools', 'id'), ('tool_loans', 'id'), ('feedback', 'id'),
      ('notifications', 'id'), ('audit_logs', 'id'), ('app_config', 'id')
    ) v (tbl, key)
  loop
    execute format(
      'insert into tests.pre_existing select %L, %I from public.%I',
      t.tbl, t.key, t.tbl
    );
  end loop;

  insert into public.users (id, full_name, email, role, account_status, specialization) values
    ('u-admin', 'Ramon Dela Cruz', 'admin@test.ph', 'admin', 'active', null),
    ('u-req', 'Maria Santos', 'req@test.ph', 'requestor', 'active', null),
    ('u-req2', 'Ana Gomez', 'req2@test.ph', 'requestor', 'active', null),
    ('u-tech', 'Marcus Wright', 'tech@test.ph', 'maintenancePersonnel', 'active', 'electrical'),
    ('u-tech2', 'Juan Luna', 'tech2@test.ph', 'maintenancePersonnel', 'active', 'plumbing'),
    ('u-inactive', 'Grace Lim', 'inactive@test.ph', 'requestor', 'inactive', null),
    ('u-pending', 'Liza Tan', 'pending@test.ph', 'requestor', 'pending', null),
    ('u-tech-off', 'Carlo Bato', 'techoff@test.ph', 'maintenancePersonnel', 'inactive', 'airConditioning');

  insert into public.facilities (id, name, building_name, room_identifier, qr_code, is_active) values
    ('f-1', 'Engineering Building', 'Engineering Building', 'Room 101', 'FAC-F-1', true),
    ('f-2', 'Gymnasium', 'Gymnasium', 'Main Court', 'FAC-F-2', false);
  insert into public.assets (id, name, qr_code, facility_id, condition) values
    ('a-1', 'Ceiling Fan', 'AST-A-1', 'f-1', 'fair');

  insert into public.work_orders (id, report_ids, title, description, category, priority, status, assigned_personnel_ids, created_by) values
    ('w-1', array['r-1'], 'Flickering lights', 'Room 101', 'electrical', 'high', 'inProgress', array['u-tech', 'u-tech-off'], 'u-admin'),
    ('w-2', array['r-2'], 'Leaking pipe', 'Lab 3', 'plumbing', 'medium', 'pending', array['u-tech2'], 'u-admin');

  insert into public.damage_reports (id, reporter_id, reporter_name, title, description, requestor_priority, status, work_order_id, facility_id) values
    ('r-1', 'u-req', 'Maria Santos', 'Flickering lights', 'Lights flicker.', 'high', 'inProgress', 'w-1', 'f-1'),
    ('r-2', 'u-req2', 'Ana Gomez', 'Leaking pipe', 'Pipe leaks.', 'medium', 'assigned', 'w-2', 'f-1'),
    ('r-3', 'u-req', 'Maria Santos', 'Broken chair', 'A leg is loose.', 'low', 'submitted', null, 'f-1'),
    ('r-4', 'u-inactive', 'Grace Lim', 'Old report', 'From before.', 'low', 'completed', null, 'f-1');

  insert into public.report_status_history (id, report_id, status, changed_by) values
    ('h-1', 'r-1', 'submitted', 'u-req'),
    ('h-2', 'r-2', 'submitted', 'u-req2'),
    ('h-3', 'r-3', 'submitted', 'u-req');

  insert into public.inventory_items (id, name, category, unit_of_measurement, storage_location, qr_code, minimum_threshold) values
    ('i-1', 'LED Bulbs', 'Electrical', 'units', 'Store A', 'INV-I-1', 5);
  insert into public.inventory_transactions (id, inventory_item_id, item_name, type, quantity, quantity_before, quantity_after, performed_by) values
    ('l-1', 'i-1', 'LED Bulbs', 'replenishment', 20, 0, 0, 'u-admin');

  insert into public.work_order_materials_used (work_order_id, inventory_item_id, item_name, quantity_used, unit_of_measurement, recorded_by) values
    ('w-1', 'i-1', 'LED Bulbs', 2, 'units', 'u-tech'),
    ('w-2', 'i-1', 'LED Bulbs', 1, 'units', 'u-tech2');
  insert into public.work_order_materials_allocated (work_order_id, inventory_item_id, item_name, quantity, unit_of_measurement, allocated_by) values
    ('w-1', 'i-1', 'LED Bulbs', 4, 'units', 'u-admin'),
    ('w-2', 'i-1', 'LED Bulbs', 3, 'units', 'u-admin');

  insert into public.tasks (id, work_order_id, title, assigned_to) values
    ('t-1', 'w-1', 'Replace the ballast', 'u-tech'),
    ('t-2', 'w-2', 'Fix the joint', 'u-tech2');

  insert into public.accomplishment_reports (id, work_order_id, submitted_by, completion_notes) values
    ('ac-1', 'w-1', 'u-tech', 'Done.'),
    ('ac-2', 'w-2', 'u-tech2', 'Done.');

  insert into public.material_requests (id, work_order_id, requested_by, requested_by_name, items) values
    ('m-1', 'w-1', 'u-tech', 'Marcus Wright', '[{"inventoryItemId":"i-1","itemName":"LED Bulbs","quantity":2,"unitOfMeasurement":"units"}]'),
    ('m-2', 'w-2', 'u-tech2', 'Juan Luna', '[{"inventoryItemId":"i-1","itemName":"LED Bulbs","quantity":1,"unitOfMeasurement":"units"}]');

  insert into public.tools (id, tool_code, name, status, condition, current_holder_id, qr_code) values
    ('tl-1', 'TL-0001', 'Multimeter', 'borrowed', 'good', 'u-tech', 'TOOL-TL-0001'),
    ('tl-2', 'TL-0002', 'Pipe Wrench', 'borrowed', 'good', 'u-tech2', 'TOOL-TL-0002');
  insert into public.tool_loans (id, tool_id, tool_name, borrowed_by, condition_on_borrow) values
    ('lo-1', 'tl-1', 'Multimeter', 'u-tech', 'good'),
    ('lo-2', 'tl-2', 'Pipe Wrench', 'u-tech2', 'good');

  insert into public.feedback (id, work_order_id, report_id, submitted_by, response_time_rating, service_quality_rating, overall_satisfaction_rating) values
    ('r-1', 'w-1', 'r-1', 'u-req', 4, 5, 4),
    ('r-2', 'w-2', 'r-2', 'u-req2', 3, 3, 3);

  insert into public.notifications (id, recipient_id, type, title, body) values
    ('n-1', 'u-req', 'statusUpdate', 'Report approved', 'Approved.'),
    ('n-2', 'u-tech', 'workOrderAssigned', 'New work order', 'Assigned.'),
    ('n-3', 'u-inactive', 'statusUpdate', 'Report closed', 'Closed.');

  insert into public.audit_logs (id, actor_id, actor_name, action, entity_type, entity_id, description) values
    ('au-1', 'u-admin', 'Ramon Dela Cruz', 'created', 'damage_reports', 'r-1', 'Report created');

  insert into public.app_config (id, data) values
    ('classification_rules', '{"keywordsByCategory":{}}')
    on conflict (id) do nothing;
  -- With the demo data loaded, the config row was already there.
  delete from tests.pre_existing where tbl = 'app_config' and key = 'classification_rules';
end;
$$;

-- Runs [query] as [uid] (null: no signed-in user, the `anon` role) and
-- returns its single text result, or 'ERROR <sqlstate>'.
create or replace function tests.query_as(uid text, query text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  result text;
begin
  perform set_config(
    'request.jwt.claims',
    case when uid is null then ''
         else json_build_object('sub', uid, 'role', 'authenticated')::text end,
    true
  );
  perform set_config('role', case when uid is null then 'anon' else 'authenticated' end, true);
  execute query into result;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return coalesce(result, '');
exception when others then
  return 'ERROR ' || sqlstate;
end;
$$;

-- The keys of the rows of [tbl] that [uid] can see, in order, joined by
-- commas.
create or replace function tests.visible(uid text, tbl text, key text default 'id')
returns text
language sql
set search_path = ''
as $$
  select tests.query_as(
    uid,
    format(
      'select coalesce(string_agg(%1$s, '','' order by %1$s collate "C"), '''') from public.%2$I '
      || 'where %1$s not in (select p.key from tests.pre_existing p where p.tbl = %3$L)',
      key,
      tbl,
      tbl
    )
  );
$$;

-- Runs [statement] as [uid]; 'ok', or the sqlstate it failed with. The
-- caller rolls back.
create or replace function tests.attempt(uid text, statement text)
returns text
language plpgsql
set search_path = ''
as $$
begin
  perform set_config(
    'request.jwt.claims',
    case when uid is null then ''
         else json_build_object('sub', uid, 'role', 'authenticated')::text end,
    true
  );
  perform set_config('role', case when uid is null then 'anon' else 'authenticated' end, true);
  execute statement;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return 'ok';
exception when others then
  return sqlstate;
end;
$$;

-- Like attempt(), returning the error message rather than the sqlstate.
create or replace function tests.error_of(uid text, statement text)
returns text
language plpgsql
set search_path = ''
as $$
begin
  perform set_config(
    'request.jwt.claims',
    case when uid is null then ''
         else json_build_object('sub', uid, 'role', 'authenticated')::text end,
    true
  );
  perform set_config('role', case when uid is null then 'anon' else 'authenticated' end, true);
  execute statement;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return null;
exception when others then
  return sqlerrm;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;

select ok(true, 'test helpers ready');
select * from finish();
commit;
