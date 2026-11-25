-- The adviser's consultation (2026-11-26): buildings the administrator
-- keeps, rooms on a floor of one, rescheduling a report nobody can take
-- yet, signing up as Faculty or Utility, and a section's notices read.

begin;
select tests.create_fixtures();
select plan(38);

-- ------------------------------------------------------------ buildings

select is(
  tests.attempt('u-req', $$select public.create_building('Science Building')$$),
  'PT403',
  'a requestor does not add buildings'
);
select is(
  tests.attempt('u-admin', $$select public.create_building('  Science   Building ', 'Beside the gym', 6.9318, 126.2551)$$),
  'ok',
  'an administrator adds a building with its pin'
);
select is(
  (select array[name, description, latitude::text, longitude::text]
     from public.buildings where name = 'Science Building'),
  array['Science Building', 'Beside the gym', '6.9318', '126.2551'],
  '…its name tidied, its description and pin kept'
);
select is(
  tests.error_of('u-admin', $$select public.create_building('science building')$$),
  'A building named science building is already registered.',
  'one name, one building, whatever the capitals'
);
select is(
  tests.error_of('u-admin', $$select public.create_building('Annex', null, 6.93, null)$$),
  'Give both the latitude and the longitude, or neither.',
  'half a pin is refused'
);
select is(
  tests.visible('u-req', 'buildings', 'name') || ' / ' || tests.visible('u-tech', 'buildings', 'name')
    || ' / ' || tests.visible(null, 'buildings', 'name'),
  'Science Building / Science Building / ERROR 42501',
  'the report form and the maintenance app read them; nobody signed out does'
);

-- ------------------------------------------------------------ rooms in them

select is(
  tests.attempt('u-admin', format(
    $$select public.create_facility('f-sci', null, 'Room 201', null, 6.9319, 126.2552, 'FAC-SCI',
        building_id => %L, floor => ' 2nd floor ')$$,
    (select id from public.buildings where name = 'Science Building'))),
  'ok',
  'a room is added to a building chosen from the list, on a floor'
);
select is(
  (select array[f.building_name, f.name, f.floor, f.room_identifier,
                (f.building_id = b.id)::text]
     from public.facilities f, public.buildings b
     where f.id = 'f-sci' and b.name = 'Science Building'),
  array['Science Building', 'Science Building', '2nd floor', 'Room 201', 'true'],
  '…carrying the building''s name for the report form, and its floor'
);
select is(
  tests.attempt('u-admin', $$select public.create_facility('f-lib', 'Library', 'Reading Area', null, null, null, 'FAC-LIB')$$),
  'ok',
  'the console of before, which types the building, still adds a room'
);
select is(
  (select f.building_id = b.id from public.facilities f, public.buildings b
     where f.id = 'f-lib' and b.name = 'Library' and b.deleted_at is null),
  true,
  '…in a building of that name, registered for it'
);
select is(
  tests.attempt('u-admin', format(
    $$select public.update_building(%L, 'Science and Technology Building', 'Beside the gym', 6.9318, 126.2551)$$,
    (select id from public.buildings where name = 'Science Building'))),
  'ok',
  'an administrator renames a building'
);
select is(
  (select building_name || ' | ' || name from public.facilities where id = 'f-sci'),
  'Science and Technology Building | Science and Technology Building',
  '…and its rooms are listed under the new name'
);
select is(
  (select description from public.audit_logs where entity_type = 'buildings'
     and description like 'Updated%'),
  'Updated Science and Technology Building',
  '…audited'
);
select is(
  tests.attempt('u-admin', $$select public.update_facility('f-sci', null, 'Room 202', null, null, null,
      building_id => (select id from public.buildings where name = 'Library'), floor => 'Ground floor')$$),
  'ok',
  'a room moves to another building and floor'
);
select is(
  (select building_name || ' | ' || floor || ' | ' || (latitude is null)::text
     from public.facilities where id = 'f-sci'),
  'Library | Ground floor | true',
  '…its pin cleared with it'
);
select is(
  tests.error_of('u-admin', format($$select public.delete_building(%L)$$,
    (select id from public.buildings where name = 'Library'))),
  'Library still has 2 rooms. Delete them or move them to another building first.',
  'a building with rooms in it stays'
);
select is(
  tests.attempt('u-admin', format($$select public.delete_building(%L)$$,
    (select id from public.buildings where name = 'Science and Technology Building'))),
  'ok',
  'an empty one is deleted'
);
select is(
  tests.error_of('u-admin', format(
    $$select public.create_facility('f-gone', null, 'Lab', null, null, null, 'FAC-GONE', building_id => %L)$$,
    (select id from public.buildings where name = 'Science and Technology Building'))),
  'That building is no longer registered. Choose another.',
  '…and takes no new rooms'
);
select is(
  tests.attempt('u-admin', $$select public.create_building('Science and Technology Building')$$),
  'ok',
  'its name is free for a new building'
);

-- ------------------------------------------------------------ rescheduling

update public.damage_reports set status = 'approved', category = 'electrical',
  official_priority = 'medium' where id = 'r-3';

select is(
  tests.attempt('u-tech', $$select public.reschedule_report('r-3', 'No electrician free', now() + interval '3 days')$$),
  'PT403',
  'a technician does not reschedule reports'
);
select is(
  tests.error_of('u-admin', $$select public.reschedule_report('r-3', '  ', now() + interval '3 days')$$),
  'Give the reason the work has to wait.',
  'rescheduling needs a reason'
);
select is(
  tests.error_of('u-admin', $$select public.reschedule_report('r-3', 'No electrician free', null)$$),
  'Choose the date the work is moved to.',
  '…and a date'
);
select is(
  tests.error_of('u-admin', $$select public.reschedule_report('r-3', 'No electrician free', now() - interval '3 days')$$),
  'Choose today or a later date.',
  '…not one already past'
);
select is(
  tests.error_of('u-admin', $$select public.reschedule_report('r-1', 'Wait', now() + interval '3 days')$$),
  'Only an approved report that is not assigned yet can be rescheduled. This one is IN PROGRESS.',
  'only an approved report waiting for assignment'
);
select is(
  tests.attempt('u-admin', $$select public.reschedule_report('r-3', 'The only electrician is on leave.',
      date_trunc('day', now()) + interval '5 days')$$),
  'ok',
  'an administrator reschedules an approved report'
);
select is(
  (select array[status, reschedule_reason, rescheduled_to::date::text]
     from public.damage_reports where id = 'r-3'),
  array['approved', 'The only electrician is on leave.',
        (date_trunc('day', now()) + interval '5 days')::date::text],
  '…it stays approved, with the reason and the date'
);
select is(
  (select array[status, note, rescheduled_to::date::text] from public.report_status_history
     where report_id = 'r-3' and rescheduled_to is not null),
  array['approved', 'The only electrician is on leave.',
        (date_trunc('day', now()) + interval '5 days')::date::text],
  '…both on its timeline, which the requestor reads'
);
select is(
  (select title || ': ' || body from public.notifications
     where recipient_id = 'u-req' and related_entity_id = 'r-3' and title = 'Report rescheduled'),
  'Report rescheduled: The work on your report "Broken chair" is rescheduled to '
    || to_char(date_trunc('day', now()) + interval '5 days 8 hours', 'FMMon FMDD, YYYY')
    || ': The only electrician is on leave.',
  '…and the requestor is told why and until when'
);
select is(
  tests.query_as('u-req', $$select reschedule_reason || ' ' || rescheduled_to::date::text
     from public.damage_reports where id = 'r-3'$$),
  'The only electrician is on leave. ' || (date_trunc('day', now()) + interval '5 days')::date::text,
  'the requestor reads both on the report'
);
select is(
  tests.attempt('u-admin', $$select public.assign_work_order('r-3', 'u-tech')$$),
  'ok',
  'once someone is free, the rescheduled report is assigned as any other'
);

-- ------------------------------------------------------------ Faculty or Utility

select is(
  tests.attempt_with_claims('{"sub":"u-util","role":"authenticated","email":"util@test.ph"}',
    $$select public.register_self('Ben Ocampo', role => 'maintenancePersonnel')$$),
  'ok',
  'someone signs up as Utility, with no department'
);
select is(
  (select array[role, account_status, coalesce(department, 'none')] from public.users where id = 'u-util'),
  array['maintenancePersonnel', 'pending', 'none'],
  '…a maintenance account, waiting for approval like any sign-up'
);
select is(
  tests.attempt_with_claims('{"sub":"u-boss","role":"authenticated","email":"boss@test.ph"}',
    $$select public.register_self('Mallory', role => 'admin')$$),
  'PT422',
  'nobody signs themselves up as an administrator'
);
select is(
  tests.error_of('u-admin', $$select public.set_account_status('u-util', 'active')$$),
  'Choose Ben Ocampo''s trade before approving the account.',
  'a utility account is approved with its trade'
);
update public.users set specialization = 'plumbing' where id = 'u-util';
select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-util', 'active')$$),
  'ok',
  '…then approved'
);
select is(
  (select description from public.audit_logs where entity_id = 'u-util'
     and action = 'statusChanged'),
  'Approved the account request of Ben Ocampo (Utility)',
  '…the audit naming what they signed up as'
);

-- ------------------------------------------------------------ a section's notices, read

insert into public.notifications (id, recipient_id, type, title, body) values
  ('n-a', 'u-req', 'statusUpdate', 'One', 'One'),
  ('n-b', 'u-req', 'statusUpdate', 'Two', 'Two'),
  ('n-c', 'u-req2', 'statusUpdate', 'Theirs', 'Theirs');

select is(
  tests.attempt('u-req', $$select public.mark_notifications_read(array['n-a', 'n-c', 'n-missing'])$$),
  'ok',
  'a section''s notices are marked read together'
);
select is(
  (select string_agg(id || ':' || is_read::text, ',' order by id)
     from public.notifications where id in ('n-a', 'n-b', 'n-c')),
  'n-a:true,n-b:false,n-c:false',
  '…only the caller''s own, and only those named'
);

select * from finish();
rollback;
