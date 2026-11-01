-- Notices for administrators (Objective 7.A).
--
-- Until now every notice went to a requestor or a technician, so the
-- console's notification centre (Figma 202:5608) had nothing to show. The
-- administrator is told of the moments the manuscript has them act on
-- (§3.4, Administrator: review reports, monitor progress, sign off work,
-- keep the inventory and the accounts). DERIVED, and flagged in
-- docs/architecture_decisions.md §22:
--
--   reportSubmitted     a report was filed; "urgent" when the requestor's
--                       initial priority is High or Critical (§3.4)
--   workStarted         work began on a work order
--   reviewRequested     an accomplishment report waits for sign-off
--   materialsRequested  a technician asked for materials
--   accountRequested    someone signed up and waits for approval (3.A)
--   lowStockAlert       a material reached its minimum (§1.5: "automatic
--                       low-stock alerts"; the type 1.B defined)
--
-- Each is written by a trigger, in the same transaction as the change, and
-- only for a change made through the app: one with a signed-in caller.
-- Loading the demo data or importing old data (which runs with triggers
-- off) tells nobody. The administrator who made a change is not told of
-- it.

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'reportAcknowledged', 'workOrderAssigned', 'taskAssigned',
  'statusUpdate', 'maintenanceCompleted', 'lowStockAlert',
  'reportSubmitted', 'workStarted', 'reviewRequested',
  'materialsRequested', 'accountRequested'
));

-- One notice to every active administrator but the caller.
create or replace function app.notify_admins(
  _type text,
  _title text,
  _body text,
  _entity_type text,
  _entity_id text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (recipient_id, type, title, body, related_entity_type, related_entity_id)
  select u.id, _type, left(_title, 120), left(_body, 1000), _entity_type, _entity_id
  from public.users u
  where u.role = 'admin'
    and u.account_status = 'active'
    and u.id is distinct from (select app.uid());
$$;

-- The caller's name, for "Juan Luna started work on ...".
create or replace function app.caller_name()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.full_name from public.users u where u.id = (select app.uid());
$$;

-- ------------------------------------------------------------- the notices

create or replace function app.notice_report_submitted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is null then
    return null;
  end if;
  perform app.notify_admins(
    'reportSubmitted',
    case when new.requestor_priority in ('high', 'critical')
      then 'New urgent report submitted'
      else 'New report submitted' end,
    app.display_id(new.id, 'DR') || ' ' || new.title
      || coalesce(' — ' || coalesce(new.facility_name, new.location_description), '') || '.',
    'damage_reports', new.id);
  return null;
end;
$$;

create trigger damage_reports_notify_admins
  after insert on public.damage_reports
  for each row execute function app.notice_report_submitted();

create or replace function app.notice_work_started()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is null then
    return null;
  end if;
  perform app.notify_admins(
    'workStarted',
    'Work started',
    coalesce((select app.caller_name()), 'A technician') || ' started working on '
      || app.display_id(new.id, 'WO') || ' (' || new.title || ').',
    'work_orders', new.id);
  return null;
end;
$$;

create trigger work_orders_notify_admins_started
  after update of status on public.work_orders
  for each row
  when (old.status = 'pending' and new.status = 'inProgress')
  execute function app.notice_work_started();

create or replace function app.notice_review_requested()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_title text;
begin
  if (select app.uid()) is null then
    return null;
  end if;
  select w.title into work_title from public.work_orders w where w.id = new.work_order_id;
  perform app.notify_admins(
    'reviewRequested',
    'Work ready for sign-off',
    coalesce((select app.caller_name()), 'A technician') || ' submitted the accomplishment report for '
      || app.display_id(new.work_order_id, 'WO') || coalesce(' (' || work_title || ')', '')
      || '. Sign it off or send it back.',
    'work_orders', new.work_order_id);
  return null;
end;
$$;

create trigger accomplishment_reports_notify_admins
  after insert on public.accomplishment_reports
  for each row execute function app.notice_review_requested();

create or replace function app.notice_materials_requested()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  lines integer := coalesce(jsonb_array_length(new.items), 0);
begin
  if (select app.uid()) is null then
    return null;
  end if;
  perform app.notify_admins(
    'materialsRequested',
    'Materials requested',
    coalesce(new.requested_by_name, (select app.caller_name()), 'A technician') || ' asked for '
      || lines || case when lines = 1 then ' material' else ' materials' end
      || ' for ' || app.display_id(new.work_order_id, 'WO') || '.',
    'material_requests', new.id);
  return null;
end;
$$;

create trigger material_requests_notify_admins
  after insert on public.material_requests
  for each row execute function app.notice_materials_requested();

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
    new.full_name || ' (' || new.email || ') signed up and is waiting for approval.',
    'users', new.id);
  return null;
end;
$$;

create trigger users_notify_admins_requested
  after insert on public.users
  for each row execute function app.notice_account_requested();

-- A ledger entry that takes a material to its minimum, or below, from
-- above it. The ledger is the only way stock moves (stock_ledger.sql), so
-- every such moment passes here: consumption on an accomplishment report,
-- or a stock count.
create or replace function app.notice_low_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.inventory_items;
begin
  if (select app.uid()) is null then
    return null;
  end if;
  select * into item from public.inventory_items i where i.id = new.inventory_item_id;
  if not found
     or not (new.quantity_before > item.minimum_threshold
             and new.quantity_after <= item.minimum_threshold) then
    return null;
  end if;
  perform app.notify_admins(
    'lowStockAlert',
    case when new.quantity_after <= 0 then 'Out of stock: ' else 'Low stock: ' end || item.name,
    item.name || ' is down to '
      || app.format_quantity(new.quantity_after, item.unit_of_measurement)
      || '; its minimum is '
      || app.format_quantity(item.minimum_threshold, item.unit_of_measurement) || '.',
    'inventory_items', item.id);
  return null;
end;
$$;

create trigger inventory_transactions_notify_low_stock
  after insert on public.inventory_transactions
  for each row execute function app.notice_low_stock();

-- ------------------------------------------------------------ privileges

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
