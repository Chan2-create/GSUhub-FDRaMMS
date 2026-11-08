-- Deleting a material (Chris, 2026-11-05: "add a delete option in
-- consumable materials").
--
-- A material that ever held stock cannot leave the table: its ledger
-- entries point at it, and the ledger is never changed or removed
-- (20261016130009_stock_ledger.sql, §3.4 Auditability). So deleting marks
-- it deleted instead, as a room is deactivated and a tool retired:
--
--   * the app leaves it out of the inventory, scans and material lists;
--   * its stock history, and the work orders, requests and reports that
--     name it, keep it as they recorded it;
--   * nothing new happens to it: no ledger entry, no edit, no recorded
--     use, no set-aside, no request;
--   * its code is free for another material.
--
-- Refused while work still counts on it.

alter table public.inventory_items add column deleted_at timestamptz;

-- The code is unique among the materials still in the inventory.
alter table public.inventory_items drop constraint inventory_items_qr_code_key;
create unique index inventory_items_qr_code_key on public.inventory_items (qr_code)
  where deleted_at is null;

-- As in server_helpers.sql, with deleted materials no longer holding a code.
create or replace function app.qr_code_owner(_code text, _except_id text default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select owner from (
    select 1 as rank, 'a material' as owner from public.inventory_items i
      where i.qr_code = _code and i.id is distinct from _except_id and i.deleted_at is null
    union all
    select 2, 'a tool' from public.tools t
      where t.qr_code = _code and t.id is distinct from _except_id
    union all
    select 3, 'a room' from public.facilities f
      where f.qr_code = _code and f.id is distinct from _except_id
    union all
    select 4, 'equipment' from public.assets a
      where a.qr_code = _code and a.id is distinct from _except_id
  ) owners
  order by rank
  limit 1;
$$;

-- ------------------------------------------------------------ the guards

-- A deleted material's row never changes again. Every ledger entry moves
-- its material's stock (stock_ledger.sql), so this refuses deliveries,
-- counts and consumption too, as well as edits.
create or replace function app.refuse_deleted_material_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is not null then
    raise exception using
      errcode = 'PT404',
      message = old.name || ' is no longer in the inventory.';
  end if;
  return new;
end;
$$;

create trigger inventory_items_deleted_guard
  before update on public.inventory_items
  for each row execute function app.refuse_deleted_material_change();

-- Nor is it recorded as used, or set aside, on a work order.
create or replace function app.refuse_deleted_material()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  gone text;
begin
  select i.name into gone from public.inventory_items i
  where i.id = new.inventory_item_id and i.deleted_at is not null;
  if found then
    raise exception using
      errcode = 'PT404',
      message = gone || ' is no longer in the inventory.';
  end if;
  return new;
end;
$$;

create trigger work_order_materials_used_deleted_guard
  before insert or update on public.work_order_materials_used
  for each row execute function app.refuse_deleted_material();
create trigger work_order_materials_allocated_deleted_guard
  before insert or update on public.work_order_materials_allocated
  for each row execute function app.refuse_deleted_material();

-- Nor asked for.
create or replace function app.refuse_deleted_material_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  gone text;
begin
  select i.name into gone
  from jsonb_array_elements(new.items) line
  join public.inventory_items i on i.id = line ->> 'inventoryItemId'
  where i.deleted_at is not null
  limit 1;
  if found then
    raise exception using
      errcode = 'PT404',
      message = gone || ' is no longer in the inventory.';
  end if;
  return new;
end;
$$;

create trigger material_requests_deleted_guard
  before insert on public.material_requests
  for each row execute function app.refuse_deleted_material_request();

-- ------------------------------------------------------------ deleting

-- An administrator deletes a material. Refused while open work still
-- counts on it: recorded as used and not yet off stock, set aside, or on
-- a request waiting for review. Deleting it again does nothing.
create or replace function app.delete_inventory_item(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.inventory_items;
  holder text;
begin
  perform app.require_admin();
  select * into item from public.inventory_items i where i.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This material is no longer in the inventory.');
  end if;
  if item.deleted_at is not null then
    return;
  end if;

  select m.work_order_id into holder
  from public.work_order_materials_used m
  join public.work_orders w on w.id = m.work_order_id
  where m.inventory_item_id = _id and w.status in ('pending', 'inProgress')
  order by m.recorded_at
  limit 1;
  if found then
    perform app.refuse('PT409', item.name || ' is recorded as used on '
      || app.display_id(holder, 'WO') || ' and comes off stock when that work is '
      || 'finished. Delete it after that.');
  end if;

  select a.work_order_id into holder
  from public.work_order_materials_allocated a
  join public.work_orders w on w.id = a.work_order_id
  where a.inventory_item_id = _id and w.status in ('pending', 'inProgress')
  order by a.allocated_at
  limit 1;
  if found then
    perform app.refuse('PT409', item.name || ' is set aside for '
      || app.display_id(holder, 'WO') || '. Take it off that work order first.');
  end if;

  select r.id into holder
  from public.material_requests r
  where r.status = 'pending'
    and r.items @> jsonb_build_array(jsonb_build_object('inventoryItemId', _id))
  order by r.created_at
  limit 1;
  if found then
    perform app.refuse('PT409', item.name || ' is on ' || app.display_id(holder, 'RQ')
      || ', a material request waiting for review. Approve or decline it first.');
  end if;

  update public.inventory_items i
  set deleted_at = now(),
      updated_at = now()
  where i.id = _id;

  perform app.audit('deleted', 'inventory_items', _id,
    'Deleted ' || item.name || ' from the inventory'
      || case when item.quantity_available > 0
           then ', with ' || app.format_quantity(item.quantity_available, item.unit_of_measurement)
             || ' still recorded'
           else '' end);
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.delete_inventory_item(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_inventory_item(id); $$;

revoke execute on function public.delete_inventory_item(text) from public, anon;
grant execute on function public.delete_inventory_item(text) to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
