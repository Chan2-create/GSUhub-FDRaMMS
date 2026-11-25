-- The adviser's consultation (2026-11-26): a report handled from start to
-- finish on its own page, buildings the administrator keeps, a sign-up
-- that says whether the person is faculty or utility, the navigation's
-- numbered badges, and no more deleting accounts.
--
--   1. buildings: the campus buildings, each with a pin; rooms belong to
--      one and carry a floor.
--   2. reschedule_report: an approved report that cannot be assigned yet
--      (no one free, no equipment) waits for a date, with a reason, both
--      shown to the requestor.
--   3. register_self takes the role the person signs up for (Faculty is
--      requestor, Utility is maintenance personnel); no department is
--      asked for. Approving a utility account needs their trade.
--   4. mark_notifications_read: the notices of one section, read when the
--      section is opened (the navigation's badges).
--   5. delete_account is gone: accounts are deactivated, never deleted.

-- ================================================================ 1. buildings

create table public.buildings (
  id text primary key default app.new_id(),
  name text not null check (char_length(name) between 1 and 120),
  description text check (char_length(description) <= 200),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);
-- One building of a name among those still registered.
create unique index buildings_name_key on public.buildings (lower(btrim(name)))
  where deleted_at is null;

alter table public.facilities
  add column building_id text references public.buildings (id),
  add column floor text check (char_length(floor) <= 40);
create index facilities_building_id_idx on public.facilities (building_id);

-- The rooms already registered keep their building: one record for each
-- building name they use. Nothing is added for a room that was deleted,
-- so a database whose rooms are all gone gets no buildings at all.
insert into public.buildings (name)
select distinct on (lower(btrim(f.building_name))) btrim(f.building_name)
from public.facilities f
where f.deleted_at is null
order by lower(btrim(f.building_name)), f.created_at;

update public.facilities f
set building_id = b.id
from public.buildings b
where b.deleted_at is null
  and lower(btrim(b.name)) = lower(btrim(f.building_name))
  and f.deleted_at is null;

alter table public.buildings enable row level security;
revoke all on table public.buildings from public, anon, authenticated;
grant select on table public.buildings to authenticated;
grant all on table public.buildings to service_role;

-- As the rooms: any active user reads them, for the report form and the
-- map.
create policy buildings_select on public.buildings
  for select to authenticated
  using ((select app.is_active()));

alter publication supabase_realtime add table public.buildings;

-- A building of [_name], registered when there is none yet: the rooms an
-- older console adds by typing the building's name still land in one.
create or replace function app.building_for_name(_name text)
returns public.buildings
language plpgsql
security definer
set search_path = ''
as $$
declare
  wanted text := regexp_replace(btrim(coalesce(_name, '')), '\s+', ' ', 'g');
  found_building public.buildings;
begin
  if wanted = '' then
    perform app.refuse('PT422', 'Choose the building.');
  end if;
  select * into found_building from public.buildings b
  where b.deleted_at is null and lower(btrim(b.name)) = lower(wanted);
  if found then
    return found_building;
  end if;
  insert into public.buildings (name) values (wanted) returning * into found_building;
  perform app.audit('created', 'buildings', found_building.id, 'Added ' || wanted);
  return found_building;
end;
$$;

-- The checks a building's fields pass before they are saved.
create or replace function app.building_name_checked(_name text, _except_id text default null)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  clean_name text := regexp_replace(btrim(coalesce(_name, '')), '\s+', ' ', 'g');
begin
  if clean_name = '' then
    perform app.refuse('PT422', 'Enter the building''s name.');
  end if;
  if char_length(clean_name) > 120 then
    perform app.refuse('PT422', 'Keep the name to 120 characters or fewer.');
  end if;
  if exists (select 1 from public.buildings b
             where b.deleted_at is null and lower(btrim(b.name)) = lower(clean_name)
               and b.id is distinct from _except_id) then
    perform app.refuse('PT409', 'A building named ' || clean_name || ' is already registered.');
  end if;
  return clean_name;
end;
$$;

create or replace function app.check_pin(_latitude double precision, _longitude double precision)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if (_latitude is null) <> (_longitude is null) then
    perform app.refuse('PT422', 'Give both the latitude and the longitude, or neither.');
  end if;
  if _latitude is not null and (_latitude not between -90 and 90 or _longitude not between -180 and 180) then
    perform app.refuse('PT422', 'That pin is not a place on the map.');
  end if;
end;
$$;

create or replace function app.create_building(
  _name text,
  _description text default null,
  _latitude double precision default null,
  _longitude double precision default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_name text;
  clean_description text := app.blank_to_null(_description);
  new_id text;
begin
  perform app.require_admin();
  clean_name := app.building_name_checked(_name);
  if char_length(clean_description) > 200 then
    perform app.refuse('PT422', 'Keep the description to 200 characters or fewer.');
  end if;
  perform app.check_pin(_latitude, _longitude);

  insert into public.buildings (name, description, latitude, longitude)
  values (clean_name, clean_description, _latitude, _longitude)
  returning id into new_id;
  perform app.audit('created', 'buildings', new_id, 'Added ' || clean_name);
  return new_id;
end;
$$;

-- Renaming a building renames it on its rooms too: they carry the name
-- the report form lists them under.
create or replace function app.update_building(
  _id text,
  _name text,
  _description text default null,
  _latitude double precision default null,
  _longitude double precision default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.buildings;
  clean_name text;
  clean_description text := app.blank_to_null(_description);
  changes jsonb;
begin
  perform app.require_admin();
  select * into stored from public.buildings b where b.id = _id for update;
  if not found or stored.deleted_at is not null then
    perform app.refuse('PT404', 'This building is no longer registered.');
  end if;
  clean_name := app.building_name_checked(_name, _id);
  if char_length(clean_description) > 200 then
    perform app.refuse('PT422', 'Keep the description to 200 characters or fewer.');
  end if;
  perform app.check_pin(_latitude, _longitude);

  changes := app.field_changes(
    jsonb_build_object('name', stored.name, 'description', stored.description,
      'latitude', stored.latitude, 'longitude', stored.longitude),
    jsonb_build_object('name', clean_name, 'description', clean_description,
      'latitude', _latitude, 'longitude', _longitude));
  if changes = '{}' then
    return;
  end if;

  update public.buildings b
  set name = clean_name, description = clean_description, latitude = _latitude,
      longitude = _longitude, updated_at = now()
  where b.id = _id;

  if clean_name <> stored.name then
    update public.facilities f
    set building_name = clean_name,
        name = case when f.name = stored.name then clean_name else f.name end,
        updated_at = now()
    where f.building_id = _id and f.deleted_at is null;
  end if;

  perform app.audit('updated', 'buildings', _id, 'Updated ' || clean_name, changes);
end;
$$;

-- A building with rooms still registered stays: its rooms go first, each
-- checked by delete_facility.
create or replace function app.delete_building(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.buildings;
  rooms integer;
begin
  perform app.require_admin();
  select * into stored from public.buildings b where b.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This building is no longer registered.');
  end if;
  if stored.deleted_at is not null then
    return;
  end if;
  select count(*) into rooms from public.facilities f
  where f.building_id = _id and f.deleted_at is null;
  if rooms > 0 then
    perform app.refuse('PT409', stored.name || ' still has ' || rooms || ' room'
      || case when rooms = 1 then '' else 's' end
      || '. Delete them or move them to another building first.');
  end if;
  update public.buildings b set deleted_at = now(), updated_at = now() where b.id = _id;
  perform app.audit('deleted', 'buildings', _id, 'Deleted ' || stored.name);
end;
$$;

-- Rooms: in a building chosen from the list ([_building_id]), on a floor.
-- [_building_name] stays for the console of before this change, which
-- types the building: it finds or registers the building of that name.
drop function public.create_facility(text, text, text, text, double precision, double precision, text);
drop function public.update_facility(text, text, text, text, double precision, double precision, text);
drop function app.create_facility(text, text, text, text, double precision, double precision, text);
drop function app.update_facility(text, text, text, text, double precision, double precision, text);

create or replace function app.room_building(_building_id text, _building_name text)
returns public.buildings
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen public.buildings;
begin
  if _building_id is null then
    return app.building_for_name(_building_name);
  end if;
  select * into chosen from public.buildings b where b.id = _building_id;
  if not found or chosen.deleted_at is not null then
    perform app.refuse('PT404', 'That building is no longer registered. Choose another.');
  end if;
  return chosen;
end;
$$;

create or replace function app.create_facility(
  _id text,
  _building_name text,
  _room_identifier text,
  _location_description text,
  _latitude double precision,
  _longitude double precision,
  _qr_code text,
  _building_id text default null,
  _floor text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  building public.buildings;
  clean_floor text := app.blank_to_null(_floor);
  fields jsonb;
begin
  perform app.require_admin();
  perform app.require_free_code(_qr_code);
  perform app.check_pin(_latitude, _longitude);
  if char_length(clean_floor) > 40 then
    perform app.refuse('PT422', 'Keep the floor to 40 characters or fewer.');
  end if;
  building := app.room_building(_building_id, _building_name);
  fields := app.facility_fields(building.name, app.blank_to_null(_room_identifier),
    app.blank_to_null(_location_description), _latitude, _longitude, _qr_code);

  insert into public.facilities (id, name, building_name, building_id, floor, room_identifier,
    location_description, latitude, longitude, qr_code, is_active)
  values (_id, fields ->> 'name', fields ->> 'buildingName', building.id, clean_floor,
    fields ->> 'roomIdentifier', fields ->> 'locationDescription', _latitude, _longitude,
    _qr_code, true);

  perform app.audit('created', 'facilities', _id,
    'Added ' || app.place_name(fields ->> 'buildingName', fields ->> 'roomIdentifier'));
  return _id;
end;
$$;

create or replace function app.update_facility(
  _id text,
  _building_name text,
  _room_identifier text,
  _location_description text,
  _latitude double precision,
  _longitude double precision,
  _qr_code text default null,
  _building_id text default null,
  _floor text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.facilities;
  building public.buildings;
  clean_floor text := app.blank_to_null(_floor);
  code text;
  before_edit jsonb;
  fields jsonb;
  changes jsonb;
begin
  perform app.require_admin();
  select * into stored from public.facilities f where f.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No room ' || _id);
  end if;
  code := coalesce(_qr_code, stored.qr_code);
  if _qr_code is not null then
    perform app.require_free_code(code, _id);
  end if;
  perform app.check_pin(_latitude, _longitude);
  if char_length(clean_floor) > 40 then
    perform app.refuse('PT422', 'Keep the floor to 40 characters or fewer.');
  end if;
  building := app.room_building(_building_id, _building_name);

  before_edit := app.facility_fields(stored.building_name, stored.room_identifier,
    stored.location_description, stored.latitude, stored.longitude, stored.qr_code);
  before_edit := before_edit || jsonb_build_object('name', stored.name,
    'locationDescription', stored.location_description, 'floor', stored.floor);
  fields := app.facility_fields(building.name, app.blank_to_null(_room_identifier),
    app.blank_to_null(_location_description), _latitude, _longitude, code)
    || jsonb_build_object('floor', clean_floor);
  changes := app.field_changes(before_edit, fields);
  if changes = '{}' and stored.building_id is not distinct from building.id then
    return;
  end if;

  update public.facilities f
  set name = fields ->> 'name',
      building_name = fields ->> 'buildingName',
      building_id = building.id,
      floor = clean_floor,
      room_identifier = fields ->> 'roomIdentifier',
      location_description = fields ->> 'locationDescription',
      latitude = _latitude,
      longitude = _longitude,
      qr_code = code,
      updated_at = now()
  where f.id = _id;

  perform app.audit('updated', 'facilities', _id,
    'Updated ' || app.place_name(fields ->> 'buildingName', fields ->> 'roomIdentifier'),
    changes);
end;
$$;

-- ================================================================ 2. rescheduling

alter table public.damage_reports
  add column rescheduled_to timestamptz,
  add column reschedule_reason text check (char_length(reschedule_reason) <= 500);

-- A rescheduling is an entry on the report's timeline beside its moves:
-- the report stays approved, waiting for the date.
alter table public.report_status_history
  add column rescheduled_to timestamptz;

create or replace function app.reschedule_report(
  _report_id text,
  _reason text,
  _rescheduled_to timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.damage_reports;
  reason text := btrim(coalesce(_reason, ''));
  shown_date text;
begin
  perform app.require_admin();
  if reason = '' then
    perform app.refuse('PT422', 'Give the reason the work has to wait.');
  end if;
  if char_length(reason) > 500 then
    perform app.refuse('PT422', 'Keep the reason to 500 characters or fewer.');
  end if;
  if _rescheduled_to is null then
    perform app.refuse('PT422', 'Choose the date the work is moved to.');
  end if;
  -- A day of leeway for the time zones: the console checks the calendar
  -- day itself.
  if _rescheduled_to < now() - interval '1 day' then
    perform app.refuse('PT422', 'Choose today or a later date.');
  end if;

  select * into stored from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if stored.status <> 'approved' or stored.work_order_id is not null then
    perform app.refuse('PT409', 'Only an approved report that is not assigned yet can be '
      || 'rescheduled. This one is ' || app.report_status_label(stored.status) || '.');
  end if;

  update public.damage_reports r
  set rescheduled_to = _rescheduled_to,
      reschedule_reason = reason,
      updated_at = now()
  where r.id = _report_id;

  insert into public.report_status_history (report_id, status, changed_by, note, rescheduled_to)
  values (_report_id, stored.status, (select app.uid()), reason, _rescheduled_to);

  shown_date := to_char(_rescheduled_to + interval '8 hours', 'FMMon FMDD, YYYY');
  perform app.notify(stored.reporter_id, 'statusUpdate', 'Report rescheduled',
    left('The work on your report "' || stored.title || '" is rescheduled to '
      || shown_date || ': ' || reason, 1000),
    'damage_reports', _report_id);
  perform app.audit('updated', 'damage_reports', _report_id,
    'Rescheduled to ' || shown_date || ': ' || reason,
    jsonb_build_object('rescheduledTo', jsonb_build_object(
        'from', stored.rescheduled_to, 'to', _rescheduled_to),
      'reason', reason));
end;
$$;

-- ================================================================ 3. sign-up role, approval

-- What the person signed up as, in the words the sign-up form uses.
create or replace function app.sign_up_role_label(_role text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case _role
    when 'requestor' then 'Faculty'
    when 'maintenancePersonnel' then 'Utility'
    else _role
  end;
$$;

drop function public.register_self(text, text, text);
drop function app.register_self(text, text, text);

-- [_role] is what the person chose: Faculty (requestor) or Utility
-- (maintenance personnel). Either waits for an administrator. The
-- department is no longer asked for; one given is still checked.
create or replace function app.register_self(
  _full_name text,
  _department text default null,
  _contact_number text default null,
  _role text default 'requestor'
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
  chosen_role text := coalesce(_role, 'requestor');
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
  if chosen_role not in ('requestor', 'maintenancePersonnel') then
    perform app.refuse('PT422', 'Choose Faculty or Utility.');
  end if;
  department := app.department_named(_department);
  contact := app.check_contact_number(_contact_number);

  insert into public.users (id, full_name, email, role, account_status, department, contact_number)
  values (caller, name, app.check_email(email), chosen_role, 'pending', department, contact);
end;
$$;

create or replace function public.register_self(
  full_name text,
  department text default null,
  contact_number text default null,
  role text default 'requestor'
)
returns void language sql security invoker set search_path = ''
as $$ select app.register_self(full_name, department, contact_number, role); $$;

revoke execute on function public.register_self(text, text, text, text) from public, anon;
grant execute on function public.register_self(text, text, text, text) to authenticated, service_role;

-- The administrators' notice names what the person signed up as.
create or replace function app.notice_account_requested()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is null or new.account_status <> 'pending' then
    return null;
  end if;
  perform app.notify_admins(
    'accountRequested',
    'Account request',
    new.full_name || ' (' || new.email || ') signed up as '
      || app.sign_up_role_label(new.role) || ' and is waiting for approval.',
    'users', new.id);
  return null;
end;
$$;

-- As before, and: a utility account is approved with its trade, which
-- routes work to it (Table 3.3).
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
  request := stored.account_status = 'pending';
  if request and activating and stored.role = 'maintenancePersonnel'
     and stored.specialization is null then
    perform app.refuse('PT422', 'Choose ' || stored.full_name
      || '''s trade before approving the account.');
  end if;

  update public.users u
  set account_status = _status,
      sessions_revoked_at = case when activating then u.sessions_revoked_at else now() end,
      sessions_revoked_reason = case when activating then u.sessions_revoked_reason else 'deactivated' end,
      updated_at = now()
  where u.id = _id;

  perform app.audit('statusChanged', 'users', _id,
    case
      when request and activating then 'Approved the account request of ' || stored.full_name
        || ' (' || app.sign_up_role_label(stored.role) || ')'
      when request then 'Declined the account request of ' || stored.full_name
      when activating then 'Reactivated the account of ' || stored.full_name
      else 'Deactivated the account of ' || stored.full_name || '; their sessions were ended'
    end,
    jsonb_build_object('from', stored.account_status, 'to', _status)
      || case when activating then '{}'::jsonb else jsonb_build_object('sessionsEnded', true) end);
end;
$$;

-- ================================================================ 4. a section's notices, read

-- The caller's own notices among [_ids] are marked read; anyone else's
-- are left alone, and so are ids that no longer exist.
create or replace function app.mark_notifications_read(_ids text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is null then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  update public.notifications n
  set is_read = true, read_at = now()
  where n.id = any (coalesce(_ids, '{}'))
    and n.recipient_id = (select app.uid())
    and not n.is_read;
end;
$$;

create or replace function public.mark_notifications_read(ids text[])
returns void language sql security invoker set search_path = ''
as $$ select app.mark_notifications_read(ids); $$;

-- ================================================================ 5. no deleting accounts

drop function public.delete_account(text);
drop function app.delete_account(text);

-- ================================================================ the API

create or replace function public.create_building(
  name text, description text default null,
  latitude double precision default null, longitude double precision default null
)
returns text language sql security invoker set search_path = ''
as $$ select app.create_building(name, description, latitude, longitude); $$;

create or replace function public.update_building(
  id text, name text, description text default null,
  latitude double precision default null, longitude double precision default null
)
returns void language sql security invoker set search_path = ''
as $$ select app.update_building(id, name, description, latitude, longitude); $$;

create or replace function public.delete_building(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_building(id); $$;

create or replace function public.create_facility(
  id text, building_name text, room_identifier text, location_description text,
  latitude double precision, longitude double precision, qr_code text,
  building_id text default null, floor text default null
)
returns text language sql security invoker set search_path = ''
as $$
  select app.create_facility(id, building_name, room_identifier, location_description,
    latitude, longitude, qr_code, building_id, floor);
$$;

create or replace function public.update_facility(
  id text, building_name text, room_identifier text, location_description text,
  latitude double precision, longitude double precision, qr_code text default null,
  building_id text default null, floor text default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.update_facility(id, building_name, room_identifier, location_description,
    latitude, longitude, qr_code, building_id, floor);
$$;

create or replace function public.reschedule_report(
  report_id text, reason text, rescheduled_to timestamptz
)
returns void language sql security invoker set search_path = ''
as $$ select app.reschedule_report(report_id, reason, rescheduled_to); $$;

revoke execute on function
  public.create_building(text, text, double precision, double precision),
  public.update_building(text, text, text, double precision, double precision),
  public.delete_building(text),
  public.create_facility(text, text, text, text, double precision, double precision, text, text, text),
  public.update_facility(text, text, text, text, double precision, double precision, text, text, text),
  public.reschedule_report(text, text, timestamptz),
  public.mark_notifications_read(text[])
from public, anon;
grant execute on function
  public.create_building(text, text, double precision, double precision),
  public.update_building(text, text, text, double precision, double precision),
  public.delete_building(text),
  public.create_facility(text, text, text, text, double precision, double precision, text, text, text),
  public.update_facility(text, text, text, text, double precision, double precision, text, text, text),
  public.reschedule_report(text, text, timestamptz),
  public.mark_notifications_read(text[])
to authenticated, service_role;

-- The new implementations, to signed-in callers only (each checks who is
-- asking). Not a blanket grant over the schema: that would reopen the
-- scheduler-only sweeps earlier migrations closed.
revoke execute on all functions in schema app from public, anon;
grant execute on function
  app.building_for_name(text),
  app.building_name_checked(text, text),
  app.check_pin(double precision, double precision),
  app.create_building(text, text, double precision, double precision),
  app.update_building(text, text, text, double precision, double precision),
  app.delete_building(text),
  app.room_building(text, text),
  app.create_facility(text, text, text, text, double precision, double precision, text, text, text),
  app.update_facility(text, text, text, text, double precision, double precision, text, text, text),
  app.reschedule_report(text, text, timestamptz),
  app.sign_up_role_label(text),
  app.register_self(text, text, text, text),
  app.mark_notifications_read(text[])
to authenticated, service_role;
