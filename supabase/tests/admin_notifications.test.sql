-- Notices for administrators (Objective 7.A): who is told of what, and
-- that nothing is said for changes made outside the app.

begin;
select tests.create_fixtures();
select plan(17);

-- A second administrator, to tell the one who acted from the one who did
-- not, and one whose account is off.
insert into public.users (id, full_name, email, role, account_status) values
  ('u-admin2', 'Elena Cruz', 'admin2@test.ph', 'admin', 'active'),
  ('u-admin-off', 'Old Admin', 'adminoff@test.ph', 'admin', 'inactive');

-- Who among the test's administrators holds a notice for [entity].
create or replace function tests.admins_told(entity text, notice_type text)
returns text
language sql
set search_path = ''
as $$
  select coalesce(string_agg(recipient_id || ':' || title, ',' order by recipient_id collate "C"), '(nobody)')
  from public.notifications
  where related_entity_id = entity
    and type = notice_type
    and recipient_id in ('u-admin', 'u-admin2', 'u-admin-off');
$$;

-- ---------------------------------------------------------------- reports

select is(
  tests.attempt('u-req', $$select public.submit_report('r-a', 'Broken chair', 'A leg is loose.', 'low')$$),
  'ok',
  'a requestor files a report'
);
select is(
  tests.admins_told('r-a', 'reportSubmitted'),
  'u-admin:New report submitted,u-admin2:New report submitted',
  '…every active administrator is told, and not one whose account is off'
);
select is(
  (select body from public.notifications where related_entity_id = 'r-a' and recipient_id = 'u-admin'),
  '#R-A Broken chair.',
  '…with the report''s number and title'
);
select is(
  tests.attempt('u-req', $$select public.submit_report('r-b', 'Sparking outlet', 'Sparks when plugged.', 'critical',
    null, null, 'f-1', 'Engineering Building', 'Room 101')$$)
    || ':' || tests.admins_told('r-b', 'reportSubmitted'),
  'ok:u-admin:New urgent report submitted,u-admin2:New urgent report submitted',
  'a report the requestor marked Critical is announced as urgent'
);

-- ------------------------------------------------------------- work orders

select is(
  tests.attempt('u-tech2', $$select public.set_work_order_status('w-2', 'inProgress')$$)
    || ':' || tests.admins_told('w-2', 'workStarted'),
  'ok:u-admin:Work started,u-admin2:Work started',
  'the administrators are told when a technician starts work'
);
select is(
  (select body from public.notifications where related_entity_id = 'w-2' and type = 'workStarted' and recipient_id = 'u-admin'),
  'Juan Luna started working on #W-2 (Leaking pipe).',
  '…by whom, and on what'
);
select is(
  tests.attempt('u-tech', $$select public.submit_accomplishment('ac-a', 'w-1', 'Replaced the ballast.', array['x.jpg'])$$)
    || ':' || tests.admins_told('w-1', 'reviewRequested'),
  'ok:u-admin:Work ready for sign-off,u-admin2:Work ready for sign-off',
  'an accomplishment report asks the administrators to sign it off'
);
select is(
  (select body from public.notifications where related_entity_id = 'w-1' and type = 'reviewRequested' and recipient_id = 'u-admin'),
  'Marcus Wright submitted the accomplishment report for #W-1 (Flickering lights). Sign it off or send it back.',
  '…saying whose and for which work'
);

-- --------------------------------------------------------------- materials

select is(
  tests.attempt('u-tech2', $$select public.submit_material_request('m-a', 'w-2', '[{"inventoryItemId":"i-1","quantity":2}]')$$)
    || ':' || tests.admins_told('m-a', 'materialsRequested'),
  'ok:u-admin:Materials requested,u-admin2:Materials requested',
  'a technician''s request for materials is announced'
);
select is(
  (select body from public.notifications where related_entity_id = 'm-a' and recipient_id = 'u-admin'),
  'Juan Luna asked for 1 material for #W-2.',
  '…with how many and for which work'
);

-- Stock counts are the administrator's (6.A). The one who counted is not
-- told what they just saw; the other administrator is.
select is(
  tests.attempt('u-admin', $$select public.record_stock_count('i-1', 4, 'Counted the shelf.')$$)
    || ':' || tests.admins_told('i-1', 'lowStockAlert'),
  'ok:u-admin2:Low stock: LED Bulbs',
  'stock reaching its minimum is announced to the other administrators'
);
select is(
  (select body from public.notifications where related_entity_id = 'i-1' and type = 'lowStockAlert' and recipient_id = 'u-admin2'),
  'LED Bulbs is down to 4 units; its minimum is 5 units.',
  '…with what is left and the minimum'
);
select is(
  tests.attempt('u-admin2', $$select public.record_stock_count('i-1', 3, 'Counted again.')$$)
    || ':' || (select count(*)::text from public.notifications where related_entity_id = 'i-1' and type = 'lowStockAlert'
                 and recipient_id in ('u-admin', 'u-admin2', 'u-admin-off')),
  'ok:1',
  '…once: a material already low is not announced again as it falls'
);
select is(
  tests.attempt('u-admin2', $$select public.record_stock_count('i-1', 0, 'All used.')$$),
  'ok',
  'nor when it runs out from below its minimum'
);

-- ---------------------------------------------------------------- accounts

select is(
  tests.attempt_with_claims('{"sub":"u-new","role":"authenticated","email":"new@test.ph"}',
    $$select public.register_self('Pedro Reyes', 'College of Arts')$$)
    || ':' || tests.admins_told('u-new', 'accountRequested'),
  'ok:u-admin:Account request,u-admin2:Account request',
  'a sign-up waiting for approval is announced'
);
select is(
  (select body from public.notifications where related_entity_id = 'u-new' and recipient_id = 'u-admin'),
  'Pedro Reyes (new@test.ph) signed up and is waiting for approval.',
  '…with who it is'
);

-- -------------------------------------------------------- outside the app

-- Loading demo data, or the one-time import, writes as the database owner
-- with nobody signed in: no notices.
insert into public.damage_reports (id, reporter_id, reporter_name, title, description, requestor_priority, status)
values ('r-quiet', 'u-req', 'Maria Santos', 'Seeded report', 'From the demo data.', 'critical', 'submitted');
select is(
  tests.admins_told('r-quiet', 'reportSubmitted'),
  '(nobody)',
  'a row written outside the app tells nobody'
);

select * from finish();
rollback;
