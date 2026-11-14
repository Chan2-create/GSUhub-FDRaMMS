-- Sessions end after 30 minutes of inactivity (Chris, 2026-11-14), and
-- the database is what ends them: the apps warn at 28 minutes and sign
-- out at 30, but a token in the hands of a client that ignores its timer
-- opens nothing after that either.
--
-- How the database knows (docs/architecture_decisions.md §31):
--
--   * The token the app trades its Firebase sign-in for carries Firebase's
--     `auth_time`: the moment the password was last typed. A fresh sign-in
--     is activity in itself, so an idle account signs back in without any
--     record having to change first.
--   * `app.user_activity` holds when each account last did something. The
--     app records it through `touch_session` while it is being used, at
--     most once a minute. Touching cannot revive a session that has
--     already ended.
--   * `app.active_role()` is the one check every policy and every function
--     goes through. It now also requires activity, or a sign-in, within
--     `app.inactivity_limit()`. Past it, the caller is nobody: reads see no
--     rows, and the functions refuse with PT401 (`app.require_session`).
--
-- A token without `auth_time` and an account without an activity record
-- count as alive: the exchange has always set `auth_time` since this
-- migration, and the tests' own tokens set only `sub`.

create table app.user_activity (
  user_id text primary key references public.users (id) on delete cascade,
  last_active_at timestamptz not null default now()
);
alter table app.user_activity enable row level security;
-- No policies and no grants: only the functions below, which run as the
-- owner, read or write it.

create or replace function app.inactivity_limit()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '30 minutes';
$$;

-- When the caller last did anything the database knows of: their last
-- recorded activity or their sign-in, whichever is later. Null when
-- neither is known.
create or replace function app.last_active_at()
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    (select a.last_active_at from app.user_activity a where a.user_id = (select app.uid())),
    to_timestamp(nullif((select auth.jwt()) ->> 'auth_time', '')::double precision)
  );
$$;

create or replace function app.session_alive()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select app.last_active_at()) > now() - app.inactivity_limit(),
    true
  );
$$;

-- As in access_helpers.sql, and alive.
create or replace function app.active_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.role
  from public.users u
  where u.id = (select app.uid())
    and u.account_status = 'active'
    and (select app.session_alive());
$$;

-- A signed-in caller whose session has ended is told so, rather than
-- that they lack permission: the app signs them out on this code.
create or replace function app.require_session()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is not null and not (select app.session_alive()) then
    perform app.refuse('PT401',
      'Your session ended after 30 minutes of inactivity. Sign in again to continue.');
  end if;
end;
$$;

create or replace function app.require_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_session();
  if not (select app.is_admin()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
end;
$$;

create or replace function app.require_active()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_session();
  if not (select app.is_active()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
end;
$$;

-- The app, while it is being used: records that the caller is active.
-- Refused once the session has ended, so touching late revives nothing;
-- a fresh sign-in carries its own `auth_time` and is let through. An
-- account with no profile yet (someone mid sign-up) has nothing to
-- record against.
create or replace function app.touch_session()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
begin
  if caller is null then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  perform app.require_session();
  insert into app.user_activity (user_id, last_active_at)
  select caller, now()
  where exists (select 1 from public.users u where u.id = caller)
  on conflict (user_id) do update set last_active_at = excluded.last_active_at;
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.touch_session()
returns void language sql security invoker set search_path = ''
as $$ select app.touch_session(); $$;

revoke execute on function public.touch_session() from public, anon;
grant execute on function public.touch_session() to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
