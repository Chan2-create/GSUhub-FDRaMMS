-- Sessions end after 30 minutes of inactivity (2026-11-14), and the
-- database is what ends them: an idle account reads nothing and changes
-- nothing, whatever token it holds, until it signs in again.

begin;
select tests.create_fixtures();
select plan(25);

-- A token as the app gets it: `sub`, and Firebase's `auth_time`, the
-- moment the password was last typed, [signed_in_ago] seconds ago.
create or replace function pg_temp.token(uid text, signed_in_ago integer)
returns text
language sql
set search_path = ''
as $$
  select json_build_object(
    'sub', uid, 'role', 'authenticated',
    'auth_time', floor(extract(epoch from now())) - signed_in_ago
  )::text;
$$;

-- What the database last saw [uid] do, as the app records it.
create or replace function pg_temp.last_seen(uid text, ago interval)
returns void
language sql
set search_path = ''
as $$
  insert into app.user_activity (user_id, last_active_at)
  values (uid, now() - ago)
  on conflict (user_id) do update set last_active_at = excluded.last_active_at;
$$;

select is(app.inactivity_limit(), interval '30 minutes', 'a session ends after 30 minutes of inactivity');

-- ------------------------------------------------- recording activity

select is(
  tests.visible('u-req', 'facilities'),
  'f-1,f-2',
  'a token that says only who, for an account with no record yet, is alive (the tests'' own tokens)'
);
select is(
  tests.attempt('u-req', $$select public.touch_session()$$),
  'ok',
  'the app records that the account is active'
);
select ok(
  (select now() - a.last_active_at < interval '5 seconds' from app.user_activity a where a.user_id = 'u-req'),
  '…as of now'
);
select pg_temp.last_seen('u-req', interval '10 minutes');
select is(tests.attempt('u-req', $$select public.touch_session()$$), 'ok', 'touching again');
select ok(
  (select now() - a.last_active_at < interval '5 seconds' from app.user_activity a where a.user_id = 'u-req'),
  '…moves the record forward'
);

-- ------------------------------------------------- an idle session

select pg_temp.last_seen('u-req', interval '31 minutes');
select is(
  tests.query_with_claims(pg_temp.token('u-req', 7200), $$select app.session_alive()::text$$),
  'false',
  'idle for 31 minutes, signed in two hours ago: the session has ended'
);
select is(
  tests.query_with_claims(pg_temp.token('u-req', 7200), $$select count(*)::text from public.facilities where id in ('f-1', 'f-2')$$),
  '0',
  '…it reads nothing'
);
select is(
  tests.query_with_claims(pg_temp.token('u-req', 7200), $$select count(*)::text from public.users$$),
  '1',
  '…except its own profile, as a deactivated account does'
);
select is(
  tests.attempt_with_claims(pg_temp.token('u-req', 7200), $$select public.mark_all_notifications_read()$$),
  'PT401',
  '…and the functions refuse it as a session that ended, not as a lack of permission'
);
select is(
  tests.error_of('u-req', $$select public.mark_all_notifications_read()$$),
  'Your session ended after 30 minutes of inactivity. Sign in again to continue.',
  '…saying so'
);
select is(
  tests.attempt_with_claims(pg_temp.token('u-req', 7200), $$select public.touch_session()$$),
  'PT401',
  'touching late revives nothing'
);
select ok(
  (select now() - a.last_active_at > interval '30 minutes' from app.user_activity a where a.user_id = 'u-req'),
  '…and the record is left as it was'
);

-- ------------------------------------------------- the boundary

select pg_temp.last_seen('u-req', interval '29 minutes');
select is(
  tests.query_with_claims(pg_temp.token('u-req', 7200), $$select count(*)::text from public.facilities where id in ('f-1', 'f-2')$$),
  '2',
  'active 29 minutes ago: still signed in'
);
select pg_temp.last_seen('u-req', interval '30 minutes 1 second');
select is(
  tests.query_with_claims(pg_temp.token('u-req', 7200), $$select count(*)::text from public.facilities where id in ('f-1', 'f-2')$$),
  '0',
  'active 30 minutes ago: not any more'
);

-- ------------------------------------------------- signing in again

select is(
  tests.query_with_claims(pg_temp.token('u-req', 60), $$select count(*)::text from public.facilities where id in ('f-1', 'f-2')$$),
  '2',
  'a fresh sign-in is activity: the new token opens everything again'
);
select is(
  tests.attempt_with_claims(pg_temp.token('u-req', 60), $$select public.touch_session()$$),
  'ok',
  '…and the app records it'
);
select ok(
  (select now() - a.last_active_at < interval '5 seconds' from app.user_activity a where a.user_id = 'u-req'),
  '…as of now'
);

-- ------------------------------------------------- administrators too

select pg_temp.last_seen('u-admin', interval '45 minutes');
select is(
  tests.attempt_with_claims(pg_temp.token('u-admin', 3600), $$select public.set_account_status('u-req2', 'inactive')$$),
  'PT401',
  'an administrator''s ended session changes no account'
);
select is(
  tests.attempt_with_claims(pg_temp.token('u-admin', 30), $$select public.set_account_status('u-req2', 'inactive')$$),
  'ok',
  '…until they sign in again'
);

-- ------------------------------------------------- who may touch what

select is(
  tests.attempt(null, $$select public.touch_session()$$),
  '42501',
  'nobody signed out records activity'
);
select is(
  tests.query_as('u-req', $$select count(*)::text from app.user_activity$$),
  'ERROR 42501',
  'no account reads the activity records themselves'
);
select is(
  tests.attempt_with_claims(pg_temp.token('u-ghost', 10), $$select public.touch_session()$$),
  'ok',
  'someone signed in with no profile yet (mid sign-up) is not refused'
);
select is(
  (select count(*)::int from app.user_activity a where a.user_id = 'u-ghost'),
  0,
  '…and nothing is recorded for them'
);

insert into public.users (id, full_name, email, role, account_status)
values ('u-gone', 'Leaving Soon', 'gone@test.ph', 'requestor', 'active');
select pg_temp.last_seen('u-gone', interval '1 minute');
delete from public.users where id = 'u-gone';
select is(
  (select count(*)::int from app.user_activity a where a.user_id = 'u-gone'),
  0,
  'a deleted account takes its activity record with it'
);

select * from finish();
rollback;
