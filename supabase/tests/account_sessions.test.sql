-- Deactivating an account, or changing its role, ends its sessions on
-- every device; the departments list; the account functions' checks
-- (2026-11-17, *_account_sessions_and_departments.sql).

begin;
select tests.create_fixtures();
select plan(45);

-- A token as the app gets it: `sub`, and Firebase's `auth_time`, the
-- moment the password was typed, [signed_in] from now (negative: ago).
-- Each test runs in one transaction, where now() stands still: a
-- revocation is stamped now(), a sign-in "after" it is a second later.
create or replace function pg_temp.token(uid text, signed_in interval)
returns text
language sql
set search_path = ''
as $$
  select json_build_object(
    'sub', uid, 'role', 'authenticated',
    'auth_time', floor(extract(epoch from now() + signed_in))
  )::text;
$$;

-- The message and the hint of what [statement] raises under [claims].
create or replace function pg_temp.refusal(claims text, statement text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  message text;
  hint text;
begin
  perform set_config('request.jwt.claims', claims, true);
  perform set_config('role', 'authenticated', true);
  execute statement;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return 'ok';
exception when others then
  get stacked diagnostics message = message_text, hint = pg_exception_hint;
  perform set_config('role', 'none', true);
  return sqlstate || ' ' || coalesce(hint, '') || ': ' || message;
end;
$$;

-- Signed in five minutes ago on two devices; on a third, a minute ago.
create temporary table devices as
  select * from (values
    ('requestor phone', pg_temp.token('u-req', interval '-5 minutes')),
    ('requestor laptop', pg_temp.token('u-req', interval '-1 minute')),
    ('technician phone', pg_temp.token('u-tech', interval '-5 minutes')),
    ('technician tablet', pg_temp.token('u-tech', interval '-2 minutes')),
    ('staff phone', pg_temp.token('u-req2', interval '-5 minutes'))
  ) v (device, claims);
grant select on devices to authenticated;

create or replace function pg_temp.on_device(device_name text, query text)
returns text
language sql
set search_path = ''
as $$
  select tests.query_with_claims((select d.claims from pg_temp.devices d where d.device = device_name), query);
$$;

select is(
  pg_temp.on_device('requestor phone', 'select public.session_state()')
    || ',' || pg_temp.on_device('technician phone', 'select public.session_state()'),
  'active,active',
  'signed in, a session is active'
);
select is(
  pg_temp.on_device('requestor phone', 'select count(*)::text from app.user_activity'),
  'ERROR 42501',
  '(asking where it stands is not activity, and touches nothing it may not)'
);

-- ------------------------------------------------- deactivation

select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-req', 'inactive')$$),
  'ok',
  'an administrator deactivates a faculty account'
);
select is(
  pg_temp.on_device('requestor phone', 'select public.session_state()')
    || ',' || pg_temp.on_device('requestor laptop', 'select public.session_state()'),
  'deactivated,deactivated',
  '…and every session it has ends, on every device, at once'
);
select is(
  pg_temp.refusal((select claims from devices where device = 'requestor phone'),
    'select public.touch_session()'),
  'PT401 deactivated: Your account has been deactivated by the Administrator. You have been logged out. '
    || 'If you believe this action was made in error, please contact the GSU Administrator''s Office.',
  '…refused with the reason, which the app signs out on and shows'
);
select is(
  pg_temp.on_device('requestor phone', 'select count(*)::text from public.damage_reports'),
  '0',
  '…its reports can no longer be read with it'
);
select is(
  pg_temp.on_device('requestor phone',
    $$select string_agg(account_status, ',') from public.users where id = 'u-req'$$),
  'inactive',
  '…but its own account still can: that is how the app learns of it'
);
select is(
  (select count(*)::int from public.damage_reports where reporter_id = 'u-req'),
  2,
  '…and nothing of theirs is deleted'
);
select is(
  (select array[u.sessions_revoked_reason, a.description, a.changes ->> 'sessionsEnded', a.actor_id]
     from public.users u, public.audit_logs a
     where u.id = 'u-req' and a.entity_id = 'u-req' and a.action = 'statusChanged'),
  array['deactivated', 'Deactivated the account of Maria Santos; their sessions were ended', 'true', 'u-admin'],
  '…and it is audited, with who did it'
);

select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-tech', 'inactive')$$),
  'ok',
  'a maintenance account is deactivated the same way'
);
select is(
  pg_temp.on_device('technician phone', 'select public.session_state()')
    || ',' || pg_temp.on_device('technician tablet', 'select public.session_state()'),
  'deactivated,deactivated',
  '…and its sessions end too'
);
select is(
  pg_temp.refusal((select claims from devices where device = 'technician tablet'),
    $$select public.set_task_status('t-1', 'completed')$$),
  'PT401 deactivated: Your account has been deactivated by the Administrator. You have been logged out. '
    || 'If you believe this action was made in error, please contact the GSU Administrator''s Office.',
  '…and it can change nothing'
);

select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-req', 'active')$$),
  'ok',
  'reactivated…'
);
select is(
  pg_temp.on_device('requestor phone', 'select public.session_state()'),
  'deactivated',
  '…the sessions it had stay ended'
);
select is(
  tests.query_with_claims(pg_temp.token('u-req', interval '1 second'), 'select public.session_state()')
    || ',' || tests.query_with_claims(pg_temp.token('u-req', interval '1 second'),
      'select count(*)::text from public.damage_reports'),
  'active,2',
  '…and signing in again works, with their reports all there'
);

-- ------------------------------------------------- a role change

select is(
  tests.attempt('u-admin', $$select public.update_account('u-req2', 'Ana Gomez', 'maintenancePersonnel', null, null, 'plumbing')$$),
  'ok',
  'an administrator changes a staff account''s role'
);
select is(
  pg_temp.on_device('staff phone', 'select public.session_state()'),
  'roleChanged',
  '…and its session ends'
);
select is(
  pg_temp.refusal((select claims from devices where device = 'staff phone'), 'select public.touch_session()'),
  'PT401 roleChanged: Your account role has been changed by the Administrator, and you have been logged out. '
    || 'If you did not request or expect this change, please visit the GSU Administrator''s Office for clarification.',
  '…refused with the reason'
);
select is(
  pg_temp.on_device('staff phone', 'select count(*)::text from public.damage_reports')
    || ',' || pg_temp.on_device('staff phone', 'select count(*)::text from public.tasks'),
  '0,0',
  '…neither the old role''s permissions nor the new one''s apply to the old session'
);
select is(
  tests.query_with_claims(pg_temp.token('u-req2', interval '1 second'), 'select app.active_role()')
    || ',' || tests.query_with_claims(pg_temp.token('u-req2', interval '1 second'), 'select public.session_state()'),
  'maintenancePersonnel,active',
  'signing in again, the new role applies'
);
select is(
  (select array[description, changes -> 'role' ->> 'from', changes -> 'role' ->> 'to', changes ->> 'sessionsEnded', actor_id,
                ("timestamp" is not null)::text]
     from public.audit_logs where entity_id = 'u-req2' and action = 'updated'),
  array['Changed Ana Gomez from End User to Maintenance; their sessions were ended',
    'requestor', 'maintenancePersonnel', 'true', 'u-admin', 'true'],
  'the change is audited: the previous role, the new one, who, and when'
);
select is(
  tests.attempt('u-admin', $$select public.update_account('u-req2', 'Ana M. Gomez', 'maintenancePersonnel', null, null, 'plumbing')$$)
    || ',' || tests.query_with_claims(pg_temp.token('u-req2', interval '1 second'), 'select public.session_state()'),
  'ok,active',
  'an edit that leaves the role as it was ends nothing'
);

-- ------------------------------------------------- the departments list

insert into public.departments (id, name) values
  ('dep-fcet', 'Faculty of Computing, Engineering and Technology'),
  ('dep-old', 'Old Office');
update public.departments set is_active = false where id = 'dep-old';

select is(
  tests.query_as(null, 'select string_agg(name, '','' order by name) from public.departments where id in (''dep-fcet'', ''dep-old'')'),
  'Faculty of Computing, Engineering and Technology',
  'anyone, signed in or not, reads the list: the Create Account form needs it'
);
select is(
  tests.query_as('u-req', 'select string_agg(name, '','' order by name) from public.departments where id in (''dep-fcet'', ''dep-old'')')
    || ' | ' || tests.query_as('u-admin', 'select string_agg(name, '','' order by name) from public.departments where id in (''dep-fcet'', ''dep-old'')'),
  'Faculty of Computing, Engineering and Technology | Faculty of Computing, Engineering and Technology,Old Office',
  'a retired one only the administrators see'
);
select is(
  tests.query_as(null, $$select count(*)::text from public.departments where false$$)
    || ',' || tests.attempt(null, $$insert into public.departments (name) values ('Mine')$$)
    || ',' || tests.attempt('u-admin', $$insert into public.departments (name) values ('Mine')$$),
  '0,42501,42501',
  'nobody writes the table directly'
);
select is(
  tests.attempt('u-admin', $$select public.create_department('  Faculty of   Nursing ')$$),
  'ok',
  'an administrator adds a department'
);
select is(
  (select name from public.departments where name like 'Faculty of Nursing%'),
  'Faculty of Nursing',
  '…tidied'
);
select is(
  tests.error_of('u-admin', $$select public.create_department('faculty of nursing')$$),
  'Faculty of Nursing is already on the list.',
  'not twice, whatever the case'
);
select is(
  tests.attempt_with_claims(pg_temp.token('u-req', interval '1 second'), $$select public.create_department('Mine')$$)
    || ',' || tests.attempt('u-tech2', $$select public.set_department_active('dep-fcet', false)$$),
  'PT403,PT403',
  'only administrators keep the list'
);

update public.users set department = 'Faculty of Computing, Engineering and Technology' where id = 'u-req';
select is(
  tests.attempt('u-admin', $$select public.rename_department('dep-fcet', 'Faculty of Computing and Engineering')$$),
  'ok',
  'a department is renamed…'
);
select is(
  (select department from public.users where id = 'u-req'),
  'Faculty of Computing and Engineering',
  '…on the accounts that name it too'
);
select is(
  tests.attempt('u-admin', $$select public.set_department_active('dep-fcet', false)$$)
    || ',' || (select department from public.users where id = 'u-req'),
  'ok,Faculty of Computing and Engineering',
  'retiring one leaves the accounts that name it as they are'
);
select is(
  tests.attempt('u-admin', $$select public.set_department_active('dep-fcet', true)$$),
  'ok',
  'restored…'
);
select is(
  (select count(*)::int from public.audit_logs where entity_type = 'departments'),
  4,
  '…and every change to the list is audited'
);

-- ------------------------------------------------- signing up, checked

select is(
  tests.attempt_with_claims('{"sub":"u-new0","role":"authenticated","email":"new0@test.ph"}',
    $$select public.register_self('Pia Ramos')$$),
  'ok',
  'signing up no longer asks for a department, even with departments on the list (2026-11-26)'
);
select is(
  tests.attempt_with_claims('{"sub":"u-new1","role":"authenticated","email":"new1@test.ph"}',
    $$select public.register_self('Pedro Reyes', 'Faculty of Magic')$$)
    || ',' || tests.attempt_with_claims('{"sub":"u-new1","role":"authenticated","email":"new1@test.ph"}',
    $$select public.register_self('Pedro Reyes', 'Old Office')$$),
  'PT422,PT422',
  'one that is on it: neither an invented one nor a retired one'
);
select is(
  tests.attempt_with_claims('{"sub":"u-new1","role":"authenticated","email":"new1@test.ph"}',
    $$select public.register_self('Pedro Reyes', 'faculty of nursing', '0917 123 456')$$),
  'PT422',
  'a mobile number is 11 digits'
);
select is(
  tests.attempt_with_claims('{"sub":"u-new1","role":"authenticated","email":"new1@test.ph"}',
    $$select public.register_self('Pedro Reyes', 'faculty of nursing', '0917-123-4567')$$),
  'ok',
  'with a listed department and a Philippine mobile number, the account is created'
);
select is(
  (select array[department, contact_number, account_status] from public.users where id = 'u-new1'),
  array['Faculty of Nursing', '09171234567', 'pending'],
  '…stored as the list spells it, the number without its dashes, awaiting approval'
);
select is(
  tests.attempt_with_claims('{"sub":"u-new2","role":"authenticated","email":"new2@test.ph"}',
    $$select public.register_self('Lito Cruz', 'Faculty of Nursing', '+639171234567')$$),
  'ok',
  'the +63 form is accepted too'
);

-- ------------------------------------------------- the administrator's forms, checked

select is(
  tests.error_of('u-admin', $$select public.create_account('u-new3', 'Rey Santos', 'not-an-email',
    'maintenancePersonnel', 'active', null, null, 'electrical', 'available')$$),
  'Enter a valid email address, such as juan.dc@dorsu.edu.ph.',
  'an account needs a valid email'
);
select is(
  tests.attempt('u-admin', $$select public.create_account('u-new3', 'Rey Santos', ' Rey.Santos@Test.PH ',
    'maintenancePersonnel', 'active', 'Faculty of Nursing', null, 'electrical', 'available')$$),
  'ok',
  'with one, the account is created…'
);
select is(
  (select email from public.users where id = 'u-new3'),
  'rey.santos@test.ph',
  '…stored as signing in compares it'
);
update public.users set department = 'Registrar''s Office (before the list)', contact_number = '1234'
  where id = 'u-tech2';
select is(
  tests.attempt('u-admin', $$select public.update_account('u-tech2', 'Juan Luna Jr.', 'maintenancePersonnel',
    'Registrar''s Office (before the list)', '1234', 'plumbing')$$),
  'ok',
  'an account from before the list keeps its department and number when edited'
);
select is(
  tests.attempt('u-admin', $$select public.update_account('u-tech2', 'Juan Luna Jr.', 'maintenancePersonnel',
    'Another Unlisted Office', '1234', 'plumbing')$$),
  'PT422',
  '…but cannot be given a new one that is not on the list'
);

select * from finish();
rollback;
