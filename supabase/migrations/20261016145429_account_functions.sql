-- Accounts (Objective 1, M3): signing up, provisioning, editing,
-- activating. Replaces UserRepositoryImpl's transactions and the users
-- rules in firebase/firestore.rules.
--
-- Each is an app.* function (security definer, checks its caller) behind a
-- public.* wrapper the API exposes. The wrapper runs as the caller, so it
-- can do nothing the app.* function does not allow.

create or replace function app.blank_to_null(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(value), '');
$$;

-- Someone who has just signed themselves up from the faculty and staff app
-- (3.A): a requestor, awaiting an administrator's approval, under the email
-- they signed in with. Nothing they send lets them in.
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
  if app.blank_to_null(_full_name) is null then
    perform app.refuse('PT422', 'Enter your full name.');
  end if;

  insert into public.users (id, full_name, email, role, account_status, department, contact_number)
  values (caller, btrim(_full_name), email, 'requestor', 'pending',
          app.blank_to_null(_department), app.blank_to_null(_contact_number));
end;
$$;

-- An administrator provisioning an account whose sign-in was just created
-- (2.C). Refuses if a profile already exists under that uid.
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
begin
  perform app.require_admin();
  if exists (select 1 from public.users u where u.id = _id) then
    perform app.refuse('PT409', 'An account profile already exists for this sign-in.');
  end if;

  insert into public.users (
    id, full_name, email, role, account_status, department, contact_number,
    specialization, availability
  ) values (
    _id, btrim(_full_name), btrim(_email), _role, _account_status,
    app.blank_to_null(_department), app.blank_to_null(_contact_number),
    _specialization, _availability
  );

  perform app.audit('created', 'users', _id,
    'Created ' || app.role_label(_role) || ' account for ' || btrim(_full_name),
    jsonb_build_object('email', btrim(_email), 'role', _role));
end;
$$;

-- An administrator's edits: name, role, department, contact number, trade
-- and leave. Refuses to change the caller's own role (the last
-- administrator demoting themselves would lock everyone out) or the role
-- of someone still holding work orders.
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

  if _role <> stored.role and _id = (select app.uid()) then
    perform app.refuse('PT409', 'You cannot change your own role. Ask another administrator.');
  end if;
  if _role <> stored.role and stored.active_task_count > 0 then
    perform app.refuse('PT409', stored.full_name || ' still has '
      || stored.active_task_count || ' active work order'
      || case when stored.active_task_count = 1 then '' else 's' end
      || '. Finish or reassign them before changing their role.');
  end if;

  -- A trade and leave status mean something only for maintenance
  -- personnel; anyone else carries neither.
  proposed := jsonb_build_object(
    'fullName', btrim(_full_name),
    'role', _role,
    'department', app.blank_to_null(_department),
    'contactNumber', app.blank_to_null(_contact_number),
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
      updated_at = now()
  where u.id = _id;

  perform app.audit('updated', 'users', _id,
    case
      when _role <> stored.role then 'Changed ' || stored.full_name || ' from '
        || app.role_label(stored.role) || ' to ' || app.role_label(_role)
      else 'Updated account details for ' || stored.full_name
    end,
    changed);
end;
$$;

-- Activate or deactivate an account, or answer a sign-up request (§1.5).
-- Refuses the caller's own account.
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

  update public.users u set account_status = _status, updated_at = now() where u.id = _id;

  request := stored.account_status = 'pending';
  perform app.audit('statusChanged', 'users', _id,
    case
      when request and activating then 'Approved the account request of ' || stored.full_name
      when request then 'Declined the account request of ' || stored.full_name
      when activating then 'Reactivated the account of ' || stored.full_name
      else 'Deactivated the account of ' || stored.full_name
    end,
    jsonb_build_object('from', stored.account_status, 'to', _status));
end;
$$;

-- The device token push notifications go to: one's own only.
create or replace function app.set_fcm_token(_id text, _token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if _id is distinct from (select app.uid()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  update public.users u set fcm_token = _token, updated_at = now() where u.id = _id;
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.register_self(
  full_name text, department text default null, contact_number text default null
)
returns void language sql security invoker set search_path = ''
as $$ select app.register_self(full_name, department, contact_number); $$;

create or replace function public.create_account(
  id text, full_name text, email text, role text, account_status text,
  department text default null, contact_number text default null,
  specialization text default null, availability text default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.create_account(id, full_name, email, role, account_status,
    department, contact_number, specialization, availability);
$$;

create or replace function public.update_account(
  id text, full_name text, role text, department text default null,
  contact_number text default null, specialization text default null,
  availability text default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.update_account(id, full_name, role, department, contact_number,
    specialization, availability);
$$;

create or replace function public.set_account_status(id text, status text)
returns void language sql security invoker set search_path = ''
as $$ select app.set_account_status(id, status); $$;

create or replace function public.set_fcm_token(id text, token text)
returns void language sql security invoker set search_path = ''
as $$ select app.set_fcm_token(id, token); $$;

revoke execute on function
  public.register_self(text, text, text),
  public.create_account(text, text, text, text, text, text, text, text, text),
  public.update_account(text, text, text, text, text, text, text),
  public.set_account_status(text, text),
  public.set_fcm_token(text, text)
from public, anon;
grant execute on function
  public.register_self(text, text, text),
  public.create_account(text, text, text, text, text, text, text, text, text),
  public.update_account(text, text, text, text, text, text, text),
  public.set_account_status(text, text),
  public.set_fcm_token(text, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
