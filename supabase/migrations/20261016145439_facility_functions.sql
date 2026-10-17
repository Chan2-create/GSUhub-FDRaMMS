-- Rooms and equipment (Objective 1, M3): FacilityRepositoryImpl's writes.
-- Administrators only. The app checks a draft's shape before calling
-- (FacilityDraft.problem); these check what only the database can see: the
-- code is free, the room exists, the record is there.

-- A place's name as the audit trail says it: "Building, Room".
create or replace function app.place_name(_building text, _room text)
returns text
language sql
immutable
set search_path = ''
as $$
  select concat_ws(', ', _building, _room);
$$;

create or replace function app.require_free_code(_code text, _except_id text default null)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  owner text := app.qr_code_owner(_code, _except_id);
begin
  if owner is not null then
    perform app.refuse('PT409', 'The code ' || _code || ' is already on ' || owner || '.');
  end if;
end;
$$;

-- The audit trail's {field: {from, to}} for the fields that differ, with
-- the app's field names. Coordinates read as "lat, lng".
create or replace function app.field_changes(_before jsonb, _after jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(a.key, jsonb_build_object('from', _before -> a.key, 'to', a.value)), '{}')
  from jsonb_each(_after) a
  where a.value is distinct from coalesce(_before -> a.key, 'null'::jsonb);
$$;

create or replace function app.facility_fields(
  _building_name text,
  _room_identifier text,
  _location_description text,
  _latitude double precision,
  _longitude double precision,
  _qr_code text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    -- The building is what the report form and the reports show as the
    -- facility's name.
    'name', _building_name,
    'buildingName', _building_name,
    'roomIdentifier', _room_identifier,
    'locationDescription', coalesce(_location_description,
      case when _room_identifier is not null then _building_name || ', ' || _room_identifier end),
    'coordinates', case when _latitude is not null and _longitude is not null
      then _latitude::text || ', ' || _longitude::text end,
    'qrCode', _qr_code
  );
$$;

create or replace function app.create_facility(
  _id text,
  _building_name text,
  _room_identifier text,
  _location_description text,
  _latitude double precision,
  _longitude double precision,
  _qr_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  fields jsonb;
begin
  perform app.require_admin();
  perform app.require_free_code(_qr_code);
  fields := app.facility_fields(btrim(_building_name), app.blank_to_null(_room_identifier),
    app.blank_to_null(_location_description), _latitude, _longitude, _qr_code);

  insert into public.facilities (id, name, building_name, room_identifier, location_description,
    latitude, longitude, qr_code, is_active)
  values (_id, fields ->> 'name', fields ->> 'buildingName', fields ->> 'roomIdentifier',
    fields ->> 'locationDescription', _latitude, _longitude, _qr_code, true);

  perform app.audit('created', 'facilities', _id,
    'Added ' || app.place_name(fields ->> 'buildingName', fields ->> 'roomIdentifier'));
  return _id;
end;
$$;

-- [_qr_code] null keeps the room's code.
create or replace function app.update_facility(
  _id text,
  _building_name text,
  _room_identifier text,
  _location_description text,
  _latitude double precision,
  _longitude double precision,
  _qr_code text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.facilities;
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

  before_edit := app.facility_fields(stored.building_name, stored.room_identifier,
    stored.location_description, stored.latitude, stored.longitude, stored.qr_code);
  -- The stored description is compared as stored, not re-derived.
  before_edit := before_edit || jsonb_build_object('name', stored.name,
    'locationDescription', stored.location_description);
  fields := app.facility_fields(btrim(_building_name), app.blank_to_null(_room_identifier),
    app.blank_to_null(_location_description), _latitude, _longitude, code);
  changes := app.field_changes(before_edit, fields);
  if changes = '{}' then
    return;
  end if;

  update public.facilities f
  set name = fields ->> 'name',
      building_name = fields ->> 'buildingName',
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

create or replace function app.set_facility_active(_id text, _active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.facilities;
begin
  perform app.require_admin();
  select * into stored from public.facilities f where f.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No facilities ' || _id);
  end if;
  if stored.is_active = _active then
    return;
  end if;
  update public.facilities f set is_active = _active, updated_at = now() where f.id = _id;
  perform app.audit('statusChanged', 'facilities', _id,
    case when _active then 'Reactivated ' else 'Deactivated ' end
      || app.place_name(stored.building_name, stored.room_identifier),
    jsonb_build_object('isActive', jsonb_build_object('from', not _active, 'to', _active)));
end;
$$;

create or replace function app.asset_fields(
  _name text,
  _facility_id text,
  _condition text,
  _category text,
  _serial_number text,
  _qr_code text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'name', _name,
    'facilityId', _facility_id,
    'condition', _condition,
    'category', _category,
    'serialNumber', _serial_number,
    'qrCode', _qr_code
  );
$$;

create or replace function app.require_facility(_facility_id text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.facilities f where f.id = _facility_id) then
    perform app.refuse('PT409', 'That room is not registered.');
  end if;
end;
$$;

create or replace function app.create_asset(
  _id text,
  _name text,
  _facility_id text,
  _condition text,
  _category text,
  _serial_number text,
  _qr_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.require_admin();
  perform app.require_free_code(_qr_code);
  perform app.require_facility(btrim(_facility_id));

  insert into public.assets (id, name, qr_code, facility_id, condition, category, serial_number, is_active)
  values (_id, btrim(_name), _qr_code, btrim(_facility_id), _condition,
    app.blank_to_null(_category), app.blank_to_null(_serial_number), true);

  perform app.audit('created', 'assets', _id, 'Added ' || btrim(_name));
  return _id;
end;
$$;

-- [_qr_code] null keeps the equipment's code.
create or replace function app.update_asset(
  _id text,
  _name text,
  _facility_id text,
  _condition text,
  _category text,
  _serial_number text,
  _qr_code text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.assets;
  code text;
  fields jsonb;
  changes jsonb;
begin
  perform app.require_admin();
  select * into stored from public.assets a where a.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No equipment ' || _id);
  end if;
  code := coalesce(_qr_code, stored.qr_code);
  if _qr_code is not null then
    perform app.require_free_code(code, _id);
  end if;
  perform app.require_facility(btrim(_facility_id));

  fields := app.asset_fields(btrim(_name), btrim(_facility_id), _condition,
    app.blank_to_null(_category), app.blank_to_null(_serial_number), code);
  changes := app.field_changes(
    app.asset_fields(stored.name, stored.facility_id, stored.condition, stored.category,
      stored.serial_number, stored.qr_code),
    fields);
  if changes = '{}' then
    return;
  end if;

  update public.assets a
  set name = fields ->> 'name',
      facility_id = fields ->> 'facilityId',
      condition = fields ->> 'condition',
      category = fields ->> 'category',
      serial_number = fields ->> 'serialNumber',
      qr_code = code,
      updated_at = now()
  where a.id = _id;

  perform app.audit('updated', 'assets', _id, 'Updated ' || btrim(_name), changes);
end;
$$;

create or replace function app.set_asset_active(_id text, _active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.assets;
begin
  perform app.require_admin();
  select * into stored from public.assets a where a.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No assets ' || _id);
  end if;
  if stored.is_active = _active then
    return;
  end if;
  update public.assets a set is_active = _active, updated_at = now() where a.id = _id;
  perform app.audit('statusChanged', 'assets', _id,
    case when _active then 'Reactivated ' else 'Deactivated ' end || stored.name,
    jsonb_build_object('isActive', jsonb_build_object('from', not _active, 'to', _active)));
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.create_facility(
  id text, building_name text, room_identifier text, location_description text,
  latitude double precision, longitude double precision, qr_code text
)
returns text language sql security invoker set search_path = ''
as $$
  select app.create_facility(id, building_name, room_identifier, location_description,
    latitude, longitude, qr_code);
$$;

create or replace function public.update_facility(
  id text, building_name text, room_identifier text, location_description text,
  latitude double precision, longitude double precision, qr_code text default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.update_facility(id, building_name, room_identifier, location_description,
    latitude, longitude, qr_code);
$$;

create or replace function public.set_facility_active(id text, active boolean)
returns void language sql security invoker set search_path = ''
as $$ select app.set_facility_active(id, active); $$;

create or replace function public.create_asset(
  id text, name text, facility_id text, condition text, category text,
  serial_number text, qr_code text
)
returns text language sql security invoker set search_path = ''
as $$
  select app.create_asset(id, name, facility_id, condition, category, serial_number, qr_code);
$$;

create or replace function public.update_asset(
  id text, name text, facility_id text, condition text, category text,
  serial_number text, qr_code text default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.update_asset(id, name, facility_id, condition, category, serial_number, qr_code);
$$;

create or replace function public.set_asset_active(id text, active boolean)
returns void language sql security invoker set search_path = ''
as $$ select app.set_asset_active(id, active); $$;

revoke execute on function
  public.create_facility(text, text, text, text, double precision, double precision, text),
  public.update_facility(text, text, text, text, double precision, double precision, text),
  public.set_facility_active(text, boolean),
  public.create_asset(text, text, text, text, text, text, text),
  public.update_asset(text, text, text, text, text, text, text),
  public.set_asset_active(text, boolean)
from public, anon;
grant execute on function
  public.create_facility(text, text, text, text, double precision, double precision, text),
  public.update_facility(text, text, text, text, double precision, double precision, text),
  public.set_facility_active(text, boolean),
  public.create_asset(text, text, text, text, text, text, text),
  public.update_asset(text, text, text, text, text, text, text),
  public.set_asset_active(text, boolean)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
