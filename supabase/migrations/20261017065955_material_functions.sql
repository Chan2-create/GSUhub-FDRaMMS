-- Materials on a work order (Objective 1, M4): what a technician records
-- as used (5.C), what GSU sets aside for the work (6.B), and the requests
-- that ask for it (6.B). MaterialUsageRepositoryImpl,
-- MaterialAllocationRepositoryImpl and MaterialRequestRepositoryImpl.
--
-- None of these moves stock: used materials are deducted when the
-- accomplishment report is filed, and set-aside materials stay on the
-- shelf until then.

-- The work order, if it can still take materials: pending or in progress.
create or replace function app.open_work_order(_work_order_id text)
returns public.work_orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
begin
  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  if work_order.status not in ('pending', 'inProgress') then
    perform app.refuse('PT409', app.display_id(_work_order_id, 'WO') || ' is '
      || app.work_order_status_title(work_order.status)
      || '; materials can no longer be assigned to it.');
  end if;
  return work_order;
end;
$$;

-- "4 units of LED Bulbs, 1 roll of Wire": a request's lines as the audit
-- trail says them.
create or replace function app.material_summary(_items jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select string_agg(
    app.format_quantity((i.value ->> 'quantity')::double precision, i.value ->> 'unitOfMeasurement')
      || ' of ' || (i.value ->> 'itemName'),
    ', ' order by i.ordinality)
  from jsonb_array_elements(_items) with ordinality i;
$$;

-- ------------------------------------------------------------ used (5.C)

-- The technician assigned records how much of a material the work used,
-- replacing what was recorded before.
create or replace function app.record_material_use(
  _work_order_id text,
  _inventory_item_id text,
  _quantity double precision
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  item public.inventory_items;
begin
  if not (select app.is_personnel()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  if _quantity is null or _quantity <= 0 then
    perform app.refuse('PT422', 'Enter how much was used.');
  end if;
  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  if not app.is_assigned(work_order) then
    perform app.refuse('PT409', 'This work order is not assigned to you.');
  end if;
  if work_order.status not in ('pending', 'inProgress') then
    perform app.refuse('PT409', 'This work order is ' || app.work_order_status_title(work_order.status)
      || '; materials can no longer be recorded on it.');
  end if;
  select * into item from public.inventory_items i where i.id = _inventory_item_id;
  if not found then
    perform app.refuse('PT404', 'This item is no longer in the inventory.');
  end if;
  if _quantity > item.quantity_available then
    perform app.refuse('PT409', 'Only ' || app.format_amount(item.quantity_available) || ' '
      || item.unit_of_measurement || ' of ' || item.name || ' in stock.');
  end if;

  insert into public.work_order_materials_used (work_order_id, inventory_item_id, item_name,
    quantity_used, unit_of_measurement, recorded_by)
  values (_work_order_id, _inventory_item_id, item.name, _quantity, item.unit_of_measurement,
    (select app.uid()))
  on conflict (work_order_id, inventory_item_id) do update
    set item_name = excluded.item_name,
        quantity_used = excluded.quantity_used,
        unit_of_measurement = excluded.unit_of_measurement,
        recorded_by = excluded.recorded_by,
        recorded_at = now();
end;
$$;

-- A recorded line taken off, by the technician while the work is open, or
-- by an administrator.
create or replace function app.remove_material_use(_work_order_id text, _inventory_item_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
begin
  select * into work_order from public.work_orders w where w.id = _work_order_id;
  if not (select app.is_admin())
     and not (found and app.is_assigned(work_order) and work_order.status in ('pending', 'inProgress')) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  delete from public.work_order_materials_used m
  where m.work_order_id = _work_order_id and m.inventory_item_id = _inventory_item_id;
end;
$$;

-- ------------------------------------------------------------ set aside (6.B)

-- An administrator sets an amount of a material aside for open work,
-- replacing what was set aside before.
create or replace function app.allocate_material(
  _work_order_id text,
  _inventory_item_id text,
  _quantity double precision
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.inventory_items;
begin
  perform app.require_admin();
  if _quantity is null or _quantity <= 0 then
    perform app.refuse('PT422', 'Enter how much to set aside.');
  end if;
  perform app.open_work_order(_work_order_id);
  select * into item from public.inventory_items i where i.id = _inventory_item_id;
  if not found then
    perform app.refuse('PT404', 'This material is no longer in the inventory.');
  end if;
  if _quantity > item.quantity_available then
    perform app.refuse('PT409', 'Only ' || app.format_quantity(item.quantity_available, item.unit_of_measurement)
      || ' of ' || item.name || ' in stock.');
  end if;

  insert into public.work_order_materials_allocated (work_order_id, inventory_item_id, item_name,
    quantity, unit_of_measurement, allocated_by)
  values (_work_order_id, _inventory_item_id, item.name, _quantity, item.unit_of_measurement,
    (select app.uid()))
  on conflict (work_order_id, inventory_item_id) do update
    set item_name = excluded.item_name,
        quantity = excluded.quantity,
        unit_of_measurement = excluded.unit_of_measurement,
        allocated_by = excluded.allocated_by,
        allocated_at = now();

  perform app.audit('updated', 'work_orders', _work_order_id,
    'Pre-assigned ' || app.format_quantity(_quantity, item.unit_of_measurement) || ' of '
      || item.name || ' to ' || app.display_id(_work_order_id, 'WO'),
    jsonb_build_object('inventoryItemId', _inventory_item_id, 'quantity', _quantity));
end;
$$;

create or replace function app.remove_allocation(_work_order_id text, _inventory_item_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed_name text;
begin
  perform app.require_admin();
  perform app.open_work_order(_work_order_id);
  delete from public.work_order_materials_allocated m
  where m.work_order_id = _work_order_id and m.inventory_item_id = _inventory_item_id
  returning m.item_name into removed_name;
  if removed_name is null then
    return;
  end if;
  perform app.audit('updated', 'work_orders', _work_order_id,
    'Took ' || removed_name || ' off ' || app.display_id(_work_order_id, 'WO')
      || '’s pre-assigned materials',
    jsonb_build_object('inventoryItemId', _inventory_item_id));
end;
$$;

-- ------------------------------------------------------------ requests (6.B)

-- The technician assigned asks for materials for their open work. The same
-- material asked for twice is one line. Filing again under the same id is
-- a retry and does nothing.
--
-- [_items]: [{"inventoryItemId", "quantity"}], as MaterialLine.toMap
-- writes it; names and units come from the inventory.
create or replace function app.submit_material_request(
  _id text,
  _work_order_id text,
  _items jsonb,
  _note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  existing_requester text;
  wanted jsonb;
  work_order public.work_orders;
  clean_note text := app.blank_to_null(_note);
  lines jsonb := '[]';
  want record;
  item public.inventory_items;
begin
  if not (select app.is_personnel()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  select r.requested_by into existing_requester from public.material_requests r where r.id = _id;
  if found then
    if existing_requester = caller then
      return;
    end if;
    perform app.refuse('PT409', 'This request could not be filed. Please try again.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('inventoryItemId', w.item, 'quantity', w.total) order by w.first), '[]')
  into wanted
  from (
    select i.value ->> 'inventoryItemId' as item,
           sum((i.value ->> 'quantity')::double precision) as total,
           min(i.ordinality) as first
    from jsonb_array_elements(coalesce(_items, '[]')) with ordinality i
    group by 1
  ) w;
  if jsonb_array_length(wanted) = 0 then
    perform app.refuse('PT422', 'Add the materials you need.');
  end if;
  if jsonb_array_length(wanted) > 20 then
    perform app.refuse('PT422', 'Ask for at most 20 materials at a time.');
  end if;
  if char_length(clean_note) > 300 then
    perform app.refuse('PT422', 'Keep the note to 300 characters.');
  end if;

  work_order := app.open_work_order(_work_order_id);
  if not (caller = any (work_order.assigned_personnel_ids)) then
    perform app.refuse('PT409', 'This work order is not assigned to you.');
  end if;

  for want in
    select w.value ->> 'inventoryItemId' as item_id, (w.value ->> 'quantity')::double precision as quantity
    from jsonb_array_elements(wanted) w
  loop
    if want.quantity is null or want.quantity <= 0 then
      perform app.refuse('PT422', 'Enter a quantity above zero.');
    end if;
    select * into item from public.inventory_items i where i.id = want.item_id;
    if not found then
      perform app.refuse('PT404', 'A material you picked is no longer in the inventory.');
    end if;
    lines := lines || jsonb_build_array(jsonb_build_object(
      'inventoryItemId', want.item_id,
      'itemName', item.name,
      'quantity', want.quantity,
      'unitOfMeasurement', item.unit_of_measurement));
  end loop;

  insert into public.material_requests (id, work_order_id, requested_by, requested_by_name, items, status, note)
  select _id, _work_order_id, caller, u.full_name, lines, 'pending', clean_note
  from public.users u where u.id = caller;

  perform app.audit('created', 'material_requests', _id,
    'Requested ' || app.material_summary(lines) || ' for ' || app.display_id(_work_order_id, 'WO'));
end;
$$;

create or replace function app.pending_request(_id text)
returns public.material_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.material_requests;
begin
  select * into request from public.material_requests r where r.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No material request ' || _id);
  end if;
  if request.status <> 'pending' then
    perform app.refuse('PT409', app.display_id(_id, 'RQ') || ' was already '
      || lower(app.request_status_label(request.status)) || '.');
  end if;
  return request;
end;
$$;

-- An administrator grants a request: each line is added to what is set
-- aside for the work, and the technician is told.
create or replace function app.approve_material_request(_id text, _note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.material_requests;
  work_order public.work_orders;
  clean_note text := app.blank_to_null(_note);
  line jsonb;
  item public.inventory_items;
begin
  perform app.require_admin();
  if char_length(clean_note) > 300 then
    perform app.refuse('PT422', 'Keep the note to 300 characters.');
  end if;
  request := app.pending_request(_id);
  work_order := app.open_work_order(request.work_order_id);

  -- Every line checked before any is set aside.
  for line in select value from jsonb_array_elements(request.items) loop
    select * into item from public.inventory_items i where i.id = line ->> 'inventoryItemId';
    if not found then
      perform app.refuse('PT404', (line ->> 'itemName') || ' is no longer in the inventory.');
    end if;
    if (line ->> 'quantity')::double precision > item.quantity_available then
      perform app.refuse('PT409', 'Only ' || app.format_quantity(item.quantity_available, item.unit_of_measurement)
        || ' of ' || item.name || ' in stock.');
    end if;
  end loop;

  for line in select value from jsonb_array_elements(request.items) loop
    select * into item from public.inventory_items i where i.id = line ->> 'inventoryItemId';
    insert into public.work_order_materials_allocated (work_order_id, inventory_item_id, item_name,
      quantity, unit_of_measurement, allocated_by)
    values (request.work_order_id, item.id, item.name, (line ->> 'quantity')::double precision,
      item.unit_of_measurement, (select app.uid()))
    on conflict (work_order_id, inventory_item_id) do update
      set item_name = excluded.item_name,
          quantity = public.work_order_materials_allocated.quantity + excluded.quantity,
          unit_of_measurement = excluded.unit_of_measurement,
          allocated_by = excluded.allocated_by,
          allocated_at = now();
  end loop;

  update public.material_requests r
  set status = 'approved', admin_note = clean_note, reviewed_by = (select app.uid()),
      reviewed_at = now(), updated_at = now()
  where r.id = _id;

  perform app.audit('statusChanged', 'material_requests', _id,
    'Approved ' || app.display_id(_id, 'RQ') || ' (' || app.material_summary(request.items) || ') for '
      || app.display_id(request.work_order_id, 'WO'),
    jsonb_build_object('status', 'approved')
      || case when clean_note is not null then jsonb_build_object('adminNote', clean_note) else '{}' end);
  -- PersonnelNotice.materialsApproved
  perform app.notify(request.requested_by, 'statusUpdate', 'Materials approved',
    'GSU approved request ' || app.display_id(_id, 'RQ') || ' for "' || work_order.title
      || '". The materials are on the work order.'
      || coalesce(' GSU: "' || clean_note || '"', ''),
    'work_orders', request.work_order_id);
end;
$$;

-- An administrator refuses a request, and must say why.
create or replace function app.decline_material_request(_id text, _note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.material_requests;
  clean_note text := app.blank_to_null(_note);
  work_title text;
begin
  perform app.require_admin();
  if clean_note is null then
    perform app.refuse('PT422', 'Say why the request is declined.');
  end if;
  if char_length(clean_note) > 300 then
    perform app.refuse('PT422', 'Keep the note to 300 characters.');
  end if;
  request := app.pending_request(_id);
  work_title := coalesce((select w.title from public.work_orders w where w.id = request.work_order_id),
    app.display_id(request.work_order_id, 'WO'));

  update public.material_requests r
  set status = 'declined', admin_note = clean_note, reviewed_by = (select app.uid()),
      reviewed_at = now(), updated_at = now()
  where r.id = _id;

  perform app.audit('statusChanged', 'material_requests', _id,
    'Declined ' || app.display_id(_id, 'RQ') || ' (' || app.material_summary(request.items) || ') for '
      || app.display_id(request.work_order_id, 'WO'),
    jsonb_build_object('status', 'declined', 'adminNote', clean_note));
  -- PersonnelNotice.materialsDeclined
  perform app.notify(request.requested_by, 'statusUpdate', 'Materials request declined',
    'GSU declined request ' || app.display_id(_id, 'RQ') || ' for "' || work_title || '": "' || clean_note || '"',
    'work_orders', request.work_order_id);
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.record_material_use(work_order_id text, inventory_item_id text, quantity double precision)
returns void language sql security invoker set search_path = ''
as $$ select app.record_material_use(work_order_id, inventory_item_id, quantity); $$;

create or replace function public.remove_material_use(work_order_id text, inventory_item_id text)
returns void language sql security invoker set search_path = ''
as $$ select app.remove_material_use(work_order_id, inventory_item_id); $$;

create or replace function public.allocate_material(work_order_id text, inventory_item_id text, quantity double precision)
returns void language sql security invoker set search_path = ''
as $$ select app.allocate_material(work_order_id, inventory_item_id, quantity); $$;

create or replace function public.remove_allocation(work_order_id text, inventory_item_id text)
returns void language sql security invoker set search_path = ''
as $$ select app.remove_allocation(work_order_id, inventory_item_id); $$;

create or replace function public.submit_material_request(id text, work_order_id text, items jsonb, note text default null)
returns void language sql security invoker set search_path = ''
as $$ select app.submit_material_request(id, work_order_id, items, note); $$;

create or replace function public.approve_material_request(id text, note text default null)
returns void language sql security invoker set search_path = ''
as $$ select app.approve_material_request(id, note); $$;

create or replace function public.decline_material_request(id text, note text)
returns void language sql security invoker set search_path = ''
as $$ select app.decline_material_request(id, note); $$;

revoke execute on function
  public.record_material_use(text, text, double precision),
  public.remove_material_use(text, text),
  public.allocate_material(text, text, double precision),
  public.remove_allocation(text, text),
  public.submit_material_request(text, text, jsonb, text),
  public.approve_material_request(text, text),
  public.decline_material_request(text, text)
from public, anon;
grant execute on function
  public.record_material_use(text, text, double precision),
  public.remove_material_use(text, text),
  public.allocate_material(text, text, double precision),
  public.remove_allocation(text, text),
  public.submit_material_request(text, text, jsonb, text),
  public.approve_material_request(text, text),
  public.decline_material_request(text, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
