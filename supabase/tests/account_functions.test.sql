-- Accounts (Objective 1, M3): signing up, provisioning, editing,
-- activating, the push token.

begin;
select tests.create_fixtures();
select plan(34);

-- ---------------------------------------------------------------- signing up

select is(
  tests.attempt_with_claims(
    '{"sub":"u-new","role":"authenticated","email":"new@test.ph"}',
    $$select public.register_self('  Pedro Reyes ', 'College of Arts', null)$$),
  'ok',
  'someone who just signed up files their profile'
);
select is(
  (select array[full_name, email, role, account_status, department] from public.users where id = 'u-new'),
  array['Pedro Reyes', 'new@test.ph', 'requestor', 'pending', 'College of Arts'],
  '…as a requestor awaiting approval, under the email they signed in with'
);
select is(
  (select count(*)::int from public.audit_logs where entity_id = 'u-new'),
  0,
  '…with no audit entry: they are not active yet, and approval is the recorded decision'
);
select is(
  tests.attempt_with_claims(
    '{"sub":"u-new","role":"authenticated","email":"new@test.ph"}',
    $$select public.register_self('Pedro Reyes')$$),
  'PT409',
  'once only'
);
select is(
  tests.attempt_with_claims('{"sub":"u-new2","role":"authenticated"}',
    $$select public.register_self('No Email')$$),
  'PT422',
  'not without the email they signed in with'
);
select is(
  tests.attempt(null, $$select public.register_self('Anonymous')$$),
  '42501',
  'not without signing in'
);

-- ---------------------------------------------------------------- provisioning

select is(
  tests.attempt('u-admin', $$select public.create_account('u-tech3', 'Rico Diaz ', 'tech3@test.ph',
    'maintenancePersonnel', 'active', null, ' ', 'carpentry', 'available')$$),
  'ok',
  'an administrator provisions a maintenance account'
);
select is(
  (select array[full_name, role, account_status, specialization, coalesce(contact_number, '-')]
     from public.users where id = 'u-tech3'),
  array['Rico Diaz', 'maintenancePersonnel', 'active', 'carpentry', '-'],
  '…as entered, trimmed, a blank contact number left empty'
);
select is(
  (select array[actor_id, actor_name, action, description, changes ->> 'role']
     from public.audit_logs where entity_id = 'u-tech3'),
  array['u-admin', 'Ramon Dela Cruz', 'created', 'Created Maintenance account for Rico Diaz', 'maintenancePersonnel'],
  '…audited under the administrator''s own name'
);
select is(
  tests.attempt('u-admin', $$select public.create_account('u-tech', 'Again', 'x@test.ph',
    'maintenancePersonnel', 'active')$$),
  'PT409',
  'not over an existing profile'
);
select is(
  tests.attempt('u-req', $$select public.create_account('u-x', 'X', 'x@test.ph', 'admin', 'active')$$),
  'PT403',
  'a requestor cannot provision accounts'
);

-- ---------------------------------------------------------------- editing

select is(
  tests.attempt('u-admin', $$select public.update_account('u-req2', 'Ana M. Gomez', 'requestor', 'Library', null)$$),
  'ok',
  'an administrator edits an account'
);
select is(
  (select array[description, changes -> 'fullName' ->> 'to', changes -> 'department' ->> 'to']
     from public.audit_logs where entity_id = 'u-req2' and action = 'updated'),
  array['Updated account details for Ana Gomez', 'Ana M. Gomez', 'Library'],
  '…and the audit says what changed'
);
select is(
  tests.attempt('u-admin', $$select public.update_account('u-req2', 'Ana M. Gomez', 'requestor', 'Library', null)$$),
  'ok',
  'an edit that changes nothing succeeds…'
);
select is(
  (select count(*)::int from public.audit_logs where entity_id = 'u-req2'),
  1,
  '…and writes nothing'
);
select is(
  tests.error_of('u-admin', $$select public.update_account('u-admin', 'Ramon Dela Cruz', 'requestor')$$),
  'You cannot change your own role. Ask another administrator.',
  'an administrator cannot change their own role'
);
update public.users set active_task_count = 1 where id = 'u-tech';
select is(
  tests.error_of('u-admin', $$select public.update_account('u-tech', 'Marcus Wright', 'requestor')$$),
  'Marcus Wright still has 1 active work order. Finish or reassign them before changing their role.',
  'nor the role of someone still holding work'
);
select is(
  tests.attempt('u-admin', $$select public.update_account('u-req', 'Maria Santos', 'maintenancePersonnel', null, null, 'plumbing')$$),
  'ok',
  'a role change'
);
select is(
  (select array[u.role, u.specialization, u.availability, a.description]
     from public.users u, public.audit_logs a
     where u.id = 'u-req' and a.entity_id = 'u-req' and a.action = 'updated'),
  array['maintenancePersonnel', 'plumbing', 'available', 'Changed Maria Santos from End User to Maintenance'],
  '…gives personnel a trade and leave status, and is described as one'
);
select is(
  tests.attempt('u-tech', $$select public.update_account('u-tech2', 'Juan Luna', 'admin')$$),
  'PT403',
  'a technician cannot edit accounts'
);

-- ---------------------------------------------------------------- activating

select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-pending', 'active')$$),
  'ok',
  'an administrator approves a sign-up request'
);
select is(
  (select array[u.account_status, a.description, a.changes ->> 'from']
     from public.users u, public.audit_logs a
     where u.id = 'u-pending' and a.entity_id = 'u-pending'),
  array['active', 'Approved the account request of Liza Tan', 'pending'],
  '…and the audit says so'
);
select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-pending', 'active')$$),
  'ok',
  'setting the status it already has succeeds…'
);
select is(
  (select count(*)::int from public.audit_logs where entity_id = 'u-pending'),
  1,
  '…and writes nothing'
);
select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-tech2', 'inactive')$$),
  'ok',
  'an administrator deactivates an account'
);
select is(
  (select description from public.audit_logs where entity_id = 'u-tech2'),
  'Deactivated the account of Juan Luna',
  '…and the audit says so'
);
select is(
  tests.error_of('u-admin', $$select public.set_account_status('u-admin', 'inactive')$$),
  'You cannot deactivate your own account. Ask another administrator.',
  'but not their own'
);
select is(
  tests.attempt('u-admin', $$select public.set_account_status('u-nobody', 'active')$$),
  'PT404',
  'an unknown account is not found'
);
select is(
  tests.attempt('u-req2', $$select public.set_account_status('u-req2', 'active')$$),
  'PT403',
  'a requestor cannot change account statuses, their own included'
);
select is(
  tests.attempt('u-inactive', $$select public.set_account_status('u-inactive', 'active')$$),
  'PT403',
  'a deactivated account cannot reactivate itself'
);

-- ---------------------------------------------------------------- the push token

select is(
  tests.attempt('u-req2', $$select public.set_fcm_token('u-req2', 'token-1')$$),
  'ok',
  'one''s own push token is saved'
);
select is((select fcm_token from public.users where id = 'u-req2'), 'token-1', '…as sent');
select is(
  tests.attempt('u-req2', $$select public.set_fcm_token('u-tech', 'stolen')$$),
  'PT403',
  'nobody else''s'
);
select is(
  (select fcm_token from public.users where id = 'u-tech'),
  null,
  '…which stays as it was'
);

select * from finish();
rollback;
