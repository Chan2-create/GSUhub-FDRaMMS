-- Accounts (Chris, 2026-11-17; docs/architecture_decisions.md §43):
--
--   1. Deactivating an account, or changing its role, ends every session
--      it has, on every device, at once. The database refuses each of
--      them from then on, and says why, so the apps sign the person out
--      with that reason.
--   2. A list of departments and faculties, kept by the administrator,
--      that faculty and staff choose from when they create an account.
--   3. The account functions check what they are given: an email's shape,
--      a Philippine mobile number, a department on the list.
--
-- What is kept: every account, report and record. Nothing here deletes.

-- ------------------------------------------------------------ 1. sessions

-- When the account's sessions were last ended, and why. A sign-in from
-- before then (the token's `auth_time`, set by firebase-token-exchange)
-- is no longer a session; one made afterwards is.
alter table public.users
  add column sessions_revoked_at timestamptz,
  add column sessions_revoked_reason text
    check (sessions_revoked_reason in ('deactivated', 'roleChanged'));

-- Why the caller's session has ended, or null while it has not:
--   'deactivated'  the account is inactive, or was deactivated after this
--                  sign-in (and has been reactivated since);
--   'roleChanged'  an administrator changed the account's role after this
--                  sign-in;
--   'idle'         15 minutes without activity (*_session_inactivity.sql).
-- A token without `auth_time` predates every revocation: the exchange has
-- set it on every token since 2026-11-14.
create or replace function app.session_end_reason()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  account public.users;
  signed_in_at timestamptz :=
    to_timestamp(nullif((select auth.jwt()) ->> 'auth_time', '')::double precision);
begin
  if caller is null then
    return null;
  end if;
  select * into account from public.users u where u.id = caller;
  if found then
    if account.account_status = 'inactive' then
      return 'deactivated';
    end if;
    if account.sessions_revoked_at is not null
       and coalesce(signed_in_at, '-infinity'::timestamptz) < account.sessions_revoked_at then
      return coalesce(account.sessions_revoked_reason, 'roleChanged');
    end if;
  end if;
  if not (select app.session_alive()) then
    return 'idle';
  end if;
  return null;
end;
$$;

-- As in *_session_inactivity.sql, and not ended by an administrator: the
-- one check every policy and every function goes through. An ended
-- session is nobody, so the old role's permissions end with it.
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
    and (select app.session_end_reason()) is null;
$$;

-- A signed-in caller whose session has ended is told so, and why: the
-- app signs out on PT401 and reads the reason from the hint.
create or replace function app.require_session()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  reason text := (select app.session_end_reason());
begin
  if reason is null then
    return;
  end if;
  raise exception using
    errcode = 'PT401',
    hint = reason,
    message = case reason
      when 'deactivated' then
        'Your account has been deactivated by the Administrator. You have been logged out. '
        || 'If you believe this action was made in error, please contact the GSU Administrator''s Office.'
      when 'roleChanged' then
        'Your account role has been changed by the Administrator, and you have been logged out. '
        || 'If you did not request or expect this change, please visit the GSU Administrator''s Office for clarification.'
      else
        'Your session ended after 15 minutes of inactivity. Sign in again to continue.'
    end;
end;
$$;

-- Every refusal goes through app.refuse. A "you may not" (PT403) to a
-- caller whose session has ended is that ended session talking: they
-- are told so, and why, whichever function refused them first. Null-safe,
-- as *_task_functions.sql made it.
create or replace function app.refuse(code text, message text)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  if coalesce(code, 'PT422') = 'PT403' then
    perform app.require_session();
  end if;
  raise exception using
    errcode = coalesce(code, 'PT422'),
    message = coalesce(message, 'That could not be done. Check the details and try again.');
end;
$$;

-- Where the caller's session stands, without counting as activity: the
-- apps ask whenever their own account changes. 'active', or the reason it
-- ended.
create or replace function app.session_state()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is null then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  return coalesce((select app.session_end_reason()), 'active');
end;
$$;

-- ------------------------------------------------------------ 2. departments

-- The departments and faculties people belong to. Read by anyone, signed
-- in or not: the Create Account form lists them before there is an
-- account. Changed only through the functions below, by an administrator.
create table public.departments (
  id text primary key default app.new_id(),
  name text not null check (char_length(btrim(name)) between 2 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index departments_name_key on public.departments (lower(btrim(name)));

alter table public.departments enable row level security;
revoke all on table public.departments from public, anon, authenticated;
grant select on table public.departments to anon, authenticated;

-- Retired ones only for administrators: they keep the list. Two
-- policies, because a signed-out reader may not call app.is_admin (nor
-- see the app schema at all).
create policy departments_select_anon on public.departments
  for select to anon
  using (is_active);
create policy departments_select on public.departments
  for select to authenticated
  using (is_active or (select app.is_admin()));

alter publication supabase_realtime add table public.departments;

-- From the records there are (docs: "retrieve them from the existing
-- database records"): every department an account already names.
insert into public.departments (name)
select distinct on (lower(btrim(u.department))) btrim(u.department)
from public.users u
where char_length(btrim(coalesce(u.department, ''))) between 2 and 120
order by lower(btrim(u.department)), btrim(u.department)
on conflict do nothing;

-- The listed department [name] stands for, as the list spells it, or a
-- refusal. Null for no department.
create or replace function app.department_named(_name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  wanted text := app.blank_to_null(_name);
  listed text;
begin
  if wanted is null then
    return null;
  end if;
  select d.name into listed
  from public.departments d
  where lower(btrim(d.name)) = lower(wanted) and d.is_active;
  if listed is null then
    perform app.refuse('PT422', 'Choose a department or faculty from the list.');
  end if;
  return listed;
end;
$$;

create or replace function app.create_department(_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean text := regexp_replace(btrim(coalesce(_name, '')), '\s+', ' ', 'g');
  created text;
  existing text;
begin
  perform app.require_admin();
  if char_length(clean) not between 2 and 120 then
    perform app.refuse('PT422', 'Give the department a name of 2 to 120 characters.');
  end if;
  select d.name into existing from public.departments d where lower(btrim(d.name)) = lower(clean);
  if existing is not null then
    perform app.refuse('PT409', existing || ' is already on the list.');
  end if;
  insert into public.departments (name) values (clean) returning id into created;
  perform app.audit('created', 'departments', created, 'Added the department ' || clean,
    jsonb_build_object('name', clean));
  return created;
end;
$$;

-- A new name, also on the accounts that carry the old one: a department
-- is stored on an account by its name.
create or replace function app.rename_department(_id text, _name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.departments;
  clean text := regexp_replace(btrim(coalesce(_name, '')), '\s+', ' ', 'g');
  existing text;
begin
  perform app.require_admin();
  select * into stored from public.departments d where d.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No department ' || _id);
  end if;
  if char_length(clean) not between 2 and 120 then
    perform app.refuse('PT422', 'Give the department a name of 2 to 120 characters.');
  end if;
  if clean = stored.name then
    return;
  end if;
  select d.name into existing from public.departments d
  where lower(btrim(d.name)) = lower(clean) and d.id <> _id;
  if existing is not null then
    perform app.refuse('PT409', existing || ' is already on the list.');
  end if;
  update public.departments d set name = clean, updated_at = now() where d.id = _id;
  update public.users u set department = clean, updated_at = now()
  where lower(btrim(u.department)) = lower(btrim(stored.name));
  perform app.audit('updated', 'departments', _id,
    'Renamed the department ' || stored.name || ' to ' || clean,
    jsonb_build_object('name', jsonb_build_object('from', stored.name, 'to', clean)));
end;
$$;

-- Off the list for new choices, or back on it. The accounts that name it
-- keep it.
create or replace function app.set_department_active(_id text, _active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.departments;
begin
  perform app.require_admin();
  select * into stored from public.departments d where d.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No department ' || _id);
  end if;
  if stored.is_active = _active then
    return;
  end if;
  update public.departments d set is_active = _active, updated_at = now() where d.id = _id;
  perform app.audit('statusChanged', 'departments', _id,
    case when _active then 'Restored the department ' else 'Retired the department ' end || stored.name,
    jsonb_build_object('from', stored.is_active, 'to', _active));
end;
$$;

-- ------------------------------------------------------------ 3. checks

-- An email's shape. The sign-in service is the real judge of an address;
-- this keeps what is stored looking like one.
create or replace function app.check_email(_email text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  clean text := lower(btrim(coalesce(_email, '')));
begin
  if clean !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(clean) > 254 then
    perform app.refuse('PT422', 'Enter a valid email address, such as juan.dc@dorsu.edu.ph.');
  end if;
  return clean;
end;
$$;

-- A Philippine mobile number, 09XXXXXXXXX or +639XXXXXXXXX, spaces and
-- dashes allowed and dropped. Null for none.
create or replace function app.check_contact_number(_number text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  clean text := regexp_replace(coalesce(_number, ''), '[\s-]', '', 'g');
begin
  if clean = '' then
    return null;
  end if;
  if clean !~ '^(09|\+639)[0-9]{9}$' then
    perform app.refuse('PT422',
      'Enter a Philippine mobile number: 11 digits starting with 09, or +63 followed by 9.');
  end if;
  return clean;
end;
$$;

-- Faculty and staff signing themselves up (3.A): now with a department
-- from the list, required once the list has any, and a checked number.
create or replace function app.register_self(
  _full_name text,
  _department text default null,
  _contact_number text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  email text := (select auth.jwt()) ->> 'email';
  name text := regexp_replace(btrim(coalesce(_full_name, '')), '\s+', ' ', 'g');
  department text;
  contact text;
begin
  if caller is null then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  if email is null or email = '' then
    perform app.refuse('PT422', 'Sign in again to finish signing up.');
  end if;
  if exists (select 1 from public.users u where u.id = caller) then
    perform app.refuse('PT409', 'An account profile already exists for this sign-in.');
  end if;
  if name = '' then
    perform app.refuse('PT422', 'Enter your full name.');
  end if;
  if char_length(name) > 120 then
    perform app.refuse('PT422', 'Keep your name to 120 characters or fewer.');
  end if;
  department := app.department_named(_department);
  if department is null and exists (select 1 from public.departments d where d.is_active) then
    perform app.refuse('PT422', 'Choose your department or faculty.');
  end if;
  contact := app.check_contact_number(_contact_number);

  insert into public.users (id, full_name, email, role, account_status, department, contact_number)
  values (caller, name, app.check_email(email), 'requestor', 'pending', department, contact);
end;
$$;

-- An administrator provisioning an account (2.C): the same checks.
create or replace function app.create_account(
  _id text,
  _full_name text,
  _email text,
  _role text,
  _account_status text,
  _department text default null,
  _contact_number text default null,
  _specialization text default null,
  _availability text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  email text;
  department text;
  contact text;
begin
  perform app.require_admin();
  if exists (select 1 from public.users u where u.id = _id) then
    perform app.refuse('PT409', 'An account profile already exists for this sign-in.');
  end if;
  if app.blank_to_null(_full_name) is null then
    perform app.refuse('PT422', 'Enter their full name.');
  end if;
  email := app.check_email(_email);
  department := app.department_named(_department);
  contact := app.check_contact_number(_contact_number);

  insert into public.users (
    id, full_name, email, role, account_status, department, contact_number,
    specialization, availability
  ) values (
    _id, btrim(_full_name), email, _role, _account_status, department, contact,
    _specialization, _availability
  );

  perform app.audit('created', 'users', _id,
    'Created ' || app.role_label(_role) || ' account for ' || btrim(_full_name),
    jsonb_build_object('email', email, 'role', _role));
end;
$$;

-- An administrator's edits (2.C), as before, with two additions: a role
-- change ends the account's sessions, and a department or number must be
-- valid unless it is the one already stored (accounts from before the
-- list keep theirs).
create or replace function app.update_account(
  _id text,
  _full_name text,
  _role text,
  _department text default null,
  _contact_number text default null,
  _specialization text default null,
  _availability text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.users;
  is_personnel boolean := _role = 'maintenancePersonnel';
  department text := app.blank_to_null(_department);
  contact text := app.blank_to_null(_contact_number);
  role_changes boolean;
  proposed jsonb;
  before_edit jsonb;
  changed jsonb := '{}';
  key text;
begin
  perform app.require_admin();
  select * into stored from public.users u where u.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No account ' || _id);
  end if;
  role_changes := _role <> stored.role;

  if role_changes and _id = (select app.uid()) then
    perform app.refuse('PT409', 'You cannot change your own role. Ask another administrator.');
  end if;
  if role_changes and stored.active_task_count > 0 then
    perform app.refuse('PT409', stored.full_name || ' still has '
      || stored.active_task_count || ' active work order'
      || case when stored.active_task_count = 1 then '' else 's' end
      || '. Finish or reassign them before changing their role.');
  end if;
  if app.blank_to_null(_full_name) is null then
    perform app.refuse('PT422', 'Enter their full name.');
  end if;
  if department is distinct from stored.department then
    department := app.department_named(department);
  end if;
  if contact is distinct from stored.contact_number then
    contact := app.check_contact_number(contact);
  end if;

  proposed := jsonb_build_object(
    'fullName', btrim(_full_name),
    'role', _role,
    'department', department,
    'contactNumber', contact,
    'specialization', case when is_personnel then _specialization end,
    'availability', case when is_personnel then coalesce(_availability, 'available') end
  );
  before_edit := jsonb_build_object(
    'fullName', stored.full_name,
    'role', stored.role,
    'department', stored.department,
    'contactNumber', stored.contact_number,
    'specialization', stored.specialization,
    'availability', stored.availability
  );
  for key in select jsonb_object_keys(proposed) loop
    if proposed -> key is distinct from before_edit -> key then
      changed := changed || jsonb_build_object(key,
        jsonb_build_object('from', before_edit -> key, 'to', proposed -> key));
    end if;
  end loop;
  if changed = '{}' then
    return;
  end if;

  update public.users u
  set full_name = proposed ->> 'fullName',
      role = proposed ->> 'role',
      department = proposed ->> 'department',
      contact_number = proposed ->> 'contactNumber',
      specialization = proposed ->> 'specialization',
      availability = proposed ->> 'availability',
      sessions_revoked_at = case when role_changes then now() else u.sessions_revoked_at end,
      sessions_revoked_reason = case when role_changes then 'roleChanged' else u.sessions_revoked_reason end,
      updated_at = now()
  where u.id = _id;

  perform app.audit('updated', 'users', _id,
    case
      when role_changes then 'Changed ' || stored.full_name || ' from '
        || app.role_label(stored.role) || ' to ' || app.role_label(_role)
        || '; their sessions were ended'
      else 'Updated account details for ' || stored.full_name
    end,
    changed || case when role_changes then jsonb_build_object('sessionsEnded', true) else '{}' end);
end;
$$;

-- Activate or deactivate an account, or answer a sign-up request (§1.5),
-- as before; deactivating also ends every session the account has.
create or replace function app.set_account_status(_id text, _status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.users;
  activating boolean := _status = 'active';
  request boolean;
begin
  perform app.require_admin();
  select * into stored from public.users u where u.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No account ' || _id);
  end if;
  if stored.account_status = _status then
    return;
  end if;
  if _id = (select app.uid()) and _status <> 'active' then
    perform app.refuse('PT409', 'You cannot deactivate your own account. Ask another administrator.');
  end if;

  update public.users u
  set account_status = _status,
      sessions_revoked_at = case when activating then u.sessions_revoked_at else now() end,
      sessions_revoked_reason = case when activating then u.sessions_revoked_reason else 'deactivated' end,
      updated_at = now()
  where u.id = _id;

  request := stored.account_status = 'pending';
  perform app.audit('statusChanged', 'users', _id,
    case
      when request and activating then 'Approved the account request of ' || stored.full_name
      when request then 'Declined the account request of ' || stored.full_name
      when activating then 'Reactivated the account of ' || stored.full_name
      else 'Deactivated the account of ' || stored.full_name || '; their sessions were ended'
    end,
    jsonb_build_object('from', stored.account_status, 'to', _status)
      || case when activating then '{}'::jsonb else jsonb_build_object('sessionsEnded', true) end);
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.session_state()
returns text language sql security invoker set search_path = ''
as $$ select app.session_state(); $$;

create or replace function public.create_department(name text)
returns text language sql security invoker set search_path = ''
as $$ select app.create_department(name); $$;

create or replace function public.rename_department(id text, name text)
returns void language sql security invoker set search_path = ''
as $$ select app.rename_department(id, name); $$;

create or replace function public.set_department_active(id text, active boolean)
returns void language sql security invoker set search_path = ''
as $$ select app.set_department_active(id, active); $$;

revoke execute on function
  public.session_state(),
  public.create_department(text),
  public.rename_department(text, text),
  public.set_department_active(text, boolean)
from public, anon;
grant execute on function
  public.session_state(),
  public.create_department(text),
  public.rename_department(text, text),
  public.set_department_active(text, boolean)
to authenticated, service_role;

-- The new app.* functions only: a grant on every function in `app` would
-- hand the scheduler's own app.sweep_tool_requests back to signed-in
-- users (see *_report_review_trail.sql).
revoke execute on function
  app.session_end_reason(),
  app.session_state(),
  app.department_named(text),
  app.create_department(text),
  app.rename_department(text, text),
  app.set_department_active(text, boolean),
  app.check_email(text),
  app.check_contact_number(text)
from public, anon;
grant execute on function
  app.session_end_reason(),
  app.session_state(),
  app.department_named(text),
  app.create_department(text),
  app.rename_department(text, text),
  app.set_department_active(text, boolean),
  app.check_email(text),
  app.check_contact_number(text)
to authenticated, service_role;
