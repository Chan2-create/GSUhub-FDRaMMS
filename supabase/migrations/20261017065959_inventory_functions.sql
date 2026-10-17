-- The inventory (Objective 1, M4): InventoryRepositoryImpl. Administrators
-- only: the store room is GSU's.
--
-- Stock moves only through the ledger. A new material starts at zero, and
-- its opening stock is its first entry; a delivery and a stock count are
-- entries too. The ledger works out the balances and moves the stock
-- (supabase/migrations/*_stock_ledger.sql), so nothing here writes a
-- quantity.

create or replace function app.inventory_fields(
  _name text,
  _category text,
  _specification text,
  _unit_of_measurement text,
  _storage_location text,
  _qr_code text,
  _minimum_threshold double precision,
  _unit_cost double precision,
  _photo_url text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'name', _name,
    'category', _category,
    'specification', _specification,
    'unitOfMeasurement', _unit_of_measurement,
    'storageLocation', _storage_location,
    'qrCode', _qr_code,
    'minimumThreshold', _minimum_threshold,
    'unitCost', _unit_cost,
    'photoUrl', _photo_url
  );
$$;

-- A new material, with its opening stock as a delivery. Returns its id.
create or replace function app.create_inventory_item(
  _name text,
  _category text,
  _specification text,
  _unit_of_measurement text,
  _storage_location text,
  _qr_code text,
  _minimum_threshold double precision,
  _unit_cost double precision,
  _photo_url text,
  _opening_stock double precision
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_item_id text := app.new_id();
  opening double precision := coalesce(_opening_stock, 0);
  clean_name text := btrim(_name);
  clean_unit text := btrim(_unit_of_measurement);
begin
  perform app.require_admin();
  if opening < 0 then
    perform app.refuse('PT422', 'The opening stock cannot be below zero.');
  end if;
  perform app.require_free_code(btrim(_qr_code));

  insert into public.inventory_items (id, name, category, specification, unit_of_measurement,
    storage_location, qr_code, minimum_threshold, unit_cost, photo_url)
  values (new_item_id, clean_name, btrim(_category), app.blank_to_null(_specification), clean_unit,
    btrim(_storage_location), btrim(_qr_code), coalesce(_minimum_threshold, 0), _unit_cost,
    app.blank_to_null(_photo_url));

  if opening > 0 then
    insert into public.inventory_transactions (inventory_item_id, type, quantity, notes,
      performed_by, performed_by_name)
    select new_item_id, 'replenishment', opening, 'Opening stock', u.id, u.full_name
    from public.users u where u.id = (select app.uid());
  end if;

  perform app.audit('created', 'inventory_items', new_item_id,
    'Added ' || clean_name || ' to the inventory'
      || case when opening > 0 then ' with ' || app.format_quantity(opening, clean_unit) else '' end);
  return new_item_id;
end;
$$;

-- A material's details. Its stock is not among them.
create or replace function app.update_inventory_item(
  _id text,
  _name text,
  _category text,
  _specification text,
  _unit_of_measurement text,
  _storage_location text,
  _qr_code text,
  _minimum_threshold double precision,
  _unit_cost double precision,
  _photo_url text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.inventory_items;
  fields jsonb;
  changes jsonb;
begin
  perform app.require_admin();
  perform app.require_free_code(btrim(_qr_code), _id);
  select * into stored from public.inventory_items i where i.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This material is no longer in the inventory.');
  end if;

  fields := app.inventory_fields(btrim(_name), btrim(_category), app.blank_to_null(_specification),
    btrim(_unit_of_measurement), btrim(_storage_location), btrim(_qr_code),
    coalesce(_minimum_threshold, 0), _unit_cost, app.blank_to_null(_photo_url));
  changes := app.field_changes(
    app.inventory_fields(stored.name, stored.category, stored.specification,
      stored.unit_of_measurement, stored.storage_location, stored.qr_code,
      stored.minimum_threshold, stored.unit_cost, stored.photo_url),
    fields);
  if changes = '{}' then
    return;
  end if;

  update public.inventory_items i
  set name = fields ->> 'name',
      category = fields ->> 'category',
      specification = fields ->> 'specification',
      unit_of_measurement = fields ->> 'unitOfMeasurement',
      storage_location = fields ->> 'storageLocation',
      qr_code = fields ->> 'qrCode',
      minimum_threshold = (fields ->> 'minimumThreshold')::double precision,
      unit_cost = (fields ->> 'unitCost')::double precision,
      photo_url = fields ->> 'photoUrl',
      updated_at = now()
  where i.id = _id;

  perform app.audit('updated', 'inventory_items', _id, 'Updated ' || (fields ->> 'name'), changes);
end;
$$;

-- A delivery, added to stock. Returns the ledger entry.
create or replace function app.record_delivery(
  _item_id text,
  _quantity double precision,
  _notes text default null
)
returns public.inventory_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry public.inventory_transactions;
begin
  perform app.require_admin();
  if _quantity is null or _quantity <= 0 then
    perform app.refuse('PT422', 'Enter a quantity above zero.');
  end if;
  insert into public.inventory_transactions (inventory_item_id, type, quantity, notes,
    performed_by, performed_by_name)
  select _item_id, 'replenishment', _quantity, app.blank_to_null(_notes), u.id, u.full_name
  from public.users u where u.id = (select app.uid())
  returning * into entry;
  return entry;
end;
$$;

-- A stock count that differs from the record, and why. The ledger records
-- the size of the correction and sets the counted balance. Returns the
-- ledger entry.
create or replace function app.record_stock_count(
  _item_id text,
  _counted_quantity double precision,
  _reason text
)
returns public.inventory_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  why text := btrim(coalesce(_reason, ''));
  entry public.inventory_transactions;
begin
  perform app.require_admin();
  if _counted_quantity is null or _counted_quantity < 0 then
    perform app.refuse('PT422', 'The count cannot be below zero.');
  end if;
  if why = '' then
    perform app.refuse('PT422', 'Say why the count differs.');
  end if;
  if char_length(why) > 200 then
    perform app.refuse('PT422', 'Keep the reason to 200 characters.');
  end if;
  insert into public.inventory_transactions (inventory_item_id, type, quantity_after, notes,
    performed_by, performed_by_name)
  select _item_id, 'adjustment', _counted_quantity, why, u.id, u.full_name
  from public.users u where u.id = (select app.uid())
  returning * into entry;
  return entry;
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.create_inventory_item(
  name text, category text, specification text, unit_of_measurement text,
  storage_location text, qr_code text, minimum_threshold double precision,
  unit_cost double precision, photo_url text, opening_stock double precision
)
returns text language sql security invoker set search_path = ''
as $$
  select app.create_inventory_item(name, category, specification, unit_of_measurement,
    storage_location, qr_code, minimum_threshold, unit_cost, photo_url, opening_stock);
$$;

create or replace function public.update_inventory_item(
  id text, name text, category text, specification text, unit_of_measurement text,
  storage_location text, qr_code text, minimum_threshold double precision,
  unit_cost double precision, photo_url text
)
returns void language sql security invoker set search_path = ''
as $$
  select app.update_inventory_item(id, name, category, specification, unit_of_measurement,
    storage_location, qr_code, minimum_threshold, unit_cost, photo_url);
$$;

create or replace function public.record_delivery(item_id text, quantity double precision, notes text default null)
returns public.inventory_transactions language sql security invoker set search_path = ''
as $$ select app.record_delivery(item_id, quantity, notes); $$;

create or replace function public.record_stock_count(item_id text, counted_quantity double precision, reason text)
returns public.inventory_transactions language sql security invoker set search_path = ''
as $$ select app.record_stock_count(item_id, counted_quantity, reason); $$;

revoke execute on function
  public.create_inventory_item(text, text, text, text, text, text, double precision, double precision, text, double precision),
  public.update_inventory_item(text, text, text, text, text, text, text, double precision, double precision, text),
  public.record_delivery(text, double precision, text),
  public.record_stock_count(text, double precision, text)
from public, anon;
grant execute on function
  public.create_inventory_item(text, text, text, text, text, text, double precision, double precision, text, double precision),
  public.update_inventory_item(text, text, text, text, text, text, text, double precision, double precision, text),
  public.record_delivery(text, double precision, text),
  public.record_stock_count(text, double precision, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
