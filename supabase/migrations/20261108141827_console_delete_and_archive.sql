-- Deleting from the console's lists, and archiving (Chris, 2026-11-08:
-- "add a delete button for everything that appears in a list ... damage
-- reports and work orders should be archived, not hard-deleted").
--
-- What each delete does, and why (docs/architecture_decisions.md §24):
--
--   * tools, rooms, equipment: marked deleted, as a material is
--     (20261105104825_delete_material.sql). Loans, reports and work orders
--     point at them and keep pointing; the app leaves them out of every
--     list, scan and picker, and nothing new happens to them. Their codes
--     are free again. Refused while something open depends on them.
--   * accounts: the profile row is removed when nothing refers to it (a
--     sign-up never used, an account made by mistake). One with records
--     (reports, work, loans, history) is refused: deactivate it instead,
--     so the records keep their name. Signing in needs the profile, so a
--     deleted account is signed out for good; its Firebase login itself
--     can only be removed from the Firebase console (no server here).
--   * damage reports and work orders: archived, never deleted. Archiving
--     sets archived_at and changes nothing else: the status, the timeline,
--     the audit trail, the requestor's and the technician's views all stay.
--     The console's lists leave archived ones out unless asked. Only
--     finished work can be archived, and it can be restored.
--
-- Every one of them is an administrator's, checked here, and audited.

alter table public.tools add column deleted_at timestamptz;
alter table public.facilities add column deleted_at timestamptz;
alter table public.assets add column deleted_at timestamptz;
alter table public.damage_reports add column archived_at timestamptz;
alter table public.work_orders add column archived_at timestamptz;

-- Codes are unique among what is still in use.
alter table public.tools drop constraint tools_tool_code_key;
alter table public.tools drop constraint tools_qr_code_key;
create unique index tools_tool_code_key on public.tools (tool_code) where deleted_at is null;
create unique index tools_qr_code_key on public.tools (qr_code) where deleted_at is null;
alter table public.facilities drop constraint facilities_qr_code_key;
create unique index facilities_qr_code_key on public.facilities (qr_code) where deleted_at is null;
alter table public.assets drop constraint assets_qr_code_key;
create unique index assets_qr_code_key on public.assets (qr_code) where deleted_at is null;

-- As in server_helpers.sql and delete_material.sql, with nothing deleted
-- holding a code.
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
      where t.qr_code = _code and t.id is distinct from _except_id and t.deleted_at is null
    union all
    select 3, 'a room' from public.facilities f
      where f.qr_code = _code and f.id is distinct from _except_id and f.deleted_at is null
    union all
    select 4, 'equipment' from public.assets a
      where a.qr_code = _code and a.id is distinct from _except_id and a.deleted_at is null
  ) owners
  order by rank
  limit 1;
$$;

-- As in tool_functions.sql, with a deleted tool's ID free.
create or replace function app.require_free_tool_codes(_tool_code text, _qr_code text, _except_id text default null)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.tools t
             where t.tool_code = _tool_code and t.id is distinct from _except_id
               and t.deleted_at is null) then
    perform app.refuse('PT409', 'Another tool already has the ID ' || _tool_code || '.');
  end if;
  perform app.require_free_code(_qr_code, _except_id);
end;
$$;

-- ------------------------------------------------------------ the guards

-- A deleted tool, room or piece of equipment never changes again: no
-- edit, no status, no loan (borrowing marks the tool out).
create or replace function app.refuse_deleted_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is not null then
    raise exception using
      errcode = 'PT404',
      message = (to_jsonb(old) ->> 'name') || ' has been deleted.';
  end if;
  return new;
end;
$$;

create trigger tools_deleted_guard
  before update on public.tools
  for each row execute function app.refuse_deleted_change();
create trigger facilities_deleted_guard
  before update on public.facilities
  for each row execute function app.refuse_deleted_change();
create trigger assets_deleted_guard
  before update on public.assets
  for each row execute function app.refuse_deleted_change();

-- No new report against a deleted room or piece of equipment.
create or replace function app.refuse_report_on_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.facilities f
             where f.id = new.facility_id and f.deleted_at is not null) then
    raise exception using errcode = 'PT404', message = 'That room has been deleted.';
  end if;
  if exists (select 1 from public.assets a
             where a.id = new.asset_id and a.deleted_at is not null) then
    raise exception using errcode = 'PT404', message = 'That equipment has been deleted.';
  end if;
  return new;
end;
$$;

create trigger damage_reports_deleted_guard
  before insert on public.damage_reports
  for each row execute function app.refuse_report_on_deleted();

-- No equipment added to, or moved into, a deleted room.
create or replace function app.refuse_asset_in_deleted_room()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.facilities f
             where f.id = new.facility_id and f.deleted_at is not null) then
    raise exception using errcode = 'PT404', message = 'That room has been deleted.';
  end if;
  return new;
end;
$$;

create trigger assets_room_deleted_guard
  before insert or update of facility_id on public.assets
  for each row execute function app.refuse_asset_in_deleted_room();

-- ------------------------------------------------------------ deleting

-- A tool, unless it is out on loan.
create or replace function app.delete_tool(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  tool public.tools;
  holder text;
begin
  perform app.require_admin();
  select * into tool from public.tools t where t.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This tool is no longer in the inventory.');
  end if;
  if tool.deleted_at is not null then
    return;
  end if;
  if tool.status = 'borrowed'
     or exists (select 1 from public.tool_loans l where l.tool_id = _id and l.returned_at is null) then
    select u.full_name into holder from public.users u where u.id = tool.current_holder_id;
    perform app.refuse('PT409', tool.name || ' is on loan to ' || coalesce(holder, 'a technician')
      || '. Check it in first.');
  end if;

  update public.tools t set deleted_at = now(), updated_at = now() where t.id = _id;
  perform app.audit('deleted', 'tools', _id,
    'Deleted ' || tool.name || ' (' || tool.tool_code || ') from the tools');
end;
$$;

-- A room, unless open reports or work orders are about it, or equipment
-- is still registered in it.
create or replace function app.delete_facility(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  room public.facilities;
  place text;
  open_count integer;
begin
  perform app.require_admin();
  select * into room from public.facilities f where f.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This room is no longer registered.');
  end if;
  if room.deleted_at is not null then
    return;
  end if;
  place := app.place_name(room.building_name, room.room_identifier);

  select count(*) into open_count from public.damage_reports r
  where r.facility_id = _id and app.report_is_open(r.status);
  if open_count > 0 then
    perform app.refuse('PT409', place || ' has ' || open_count || ' open report'
      || case when open_count = 1 then '' else 's' end
      || '. Finish, reject or merge them first.');
  end if;
  select count(*) into open_count from public.work_orders w
  where w.facility_id = _id and w.status <> 'completed';
  if open_count > 0 then
    perform app.refuse('PT409', place || ' has ' || open_count || ' open work order'
      || case when open_count = 1 then '' else 's' end || '. Finish them first.');
  end if;
  select count(*) into open_count from public.assets a
  where a.facility_id = _id and a.deleted_at is null;
  if open_count > 0 then
    perform app.refuse('PT409', place || ' still has ' || open_count || ' piece'
      || case when open_count = 1 then '' else 's' end
      || ' of equipment. Delete it or move it to another room first.');
  end if;

  update public.facilities f set deleted_at = now(), updated_at = now() where f.id = _id;
  perform app.audit('deleted', 'facilities', _id, 'Deleted ' || place);
end;
$$;

-- A piece of equipment, unless open reports are about it.
create or replace function app.delete_asset(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  asset public.assets;
  open_count integer;
begin
  perform app.require_admin();
  select * into asset from public.assets a where a.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This equipment is no longer registered.');
  end if;
  if asset.deleted_at is not null then
    return;
  end if;
  select count(*) into open_count from public.damage_reports r
  where r.asset_id = _id and app.report_is_open(r.status);
  if open_count > 0 then
    perform app.refuse('PT409', asset.name || ' has ' || open_count || ' open report'
      || case when open_count = 1 then '' else 's' end
      || '. Finish, reject or merge them first.');
  end if;

  update public.assets a set deleted_at = now(), updated_at = now() where a.id = _id;
  perform app.audit('deleted', 'assets', _id, 'Deleted ' || asset.name);
end;
$$;

-- An account with no records. Never one's own; never one holding open
-- work or a tool; one with any record is refused, to be deactivated.
create or replace function app.delete_account(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  person public.users;
  open_count integer;
  tool_name text;
begin
  perform app.require_admin();
  select * into person from public.users u where u.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'This account no longer exists.');
  end if;
  if _id = (select app.uid()) then
    perform app.refuse('PT409', 'You cannot delete your own account. Ask another administrator.');
  end if;

  select count(*) into open_count from public.work_orders w
  where _id = any (w.assigned_personnel_ids) and w.status <> 'completed';
  if open_count > 0 then
    perform app.refuse('PT409', person.full_name || ' is assigned to ' || open_count
      || ' open work order' || case when open_count = 1 then '' else 's' end
      || '. Reassign ' || case when open_count = 1 then 'it' else 'them' end || ' first.');
  end if;
  select l.tool_name into tool_name from public.tool_loans l
  where l.borrowed_by = _id and l.returned_at is null
  order by l.borrowed_at
  limit 1;
  if found then
    perform app.refuse('PT409', person.full_name || ' still has ' || tool_name
      || ' on loan. Check it in first.');
  end if;

  -- Their notifications go with them; any other row that names them keeps
  -- the account, and nothing is removed.
  begin
    delete from public.notifications n where n.recipient_id = _id;
    delete from public.users u where u.id = _id;
  exception when foreign_key_violation then
    perform app.refuse('PT409', person.full_name || ' has records in GSUhub (reports, work '
      || 'or history), so the account stays to keep them. Deactivate it instead.');
  end;

  perform app.audit('deleted', 'users', _id,
    'Deleted the account of ' || person.full_name || ' (' || person.email || ')');
end;
$$;

-- ------------------------------------------------------------ archiving

-- A finished report out of the console's lists, or back.
create or replace function app.set_report_archived(_id text, _archived boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  report public.damage_reports;
  label text := app.display_id(_id, 'DR');
begin
  perform app.require_admin();
  select * into report from public.damage_reports r where r.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No report ' || _id);
  end if;
  if (report.archived_at is not null) = coalesce(_archived, false) then
    return;
  end if;
  if _archived and report.status not in ('closed', 'merged', 'rejected', 'archived') then
    perform app.refuse('PT409', label || ' is ' || lower(app.report_status_label(report.status))
      || '. Only a closed, merged or rejected report can be archived.');
  end if;

  update public.damage_reports r
  set archived_at = case when _archived then now() end
  where r.id = _id;
  perform app.audit('updated', 'damage_reports', _id,
    case when _archived then 'Archived report ' || label
      else 'Restored report ' || label || ' from the archive' end,
    jsonb_build_object('archived', jsonb_build_object('from', not _archived, 'to', _archived)));
end;
$$;

-- A completed work order off the board, or back.
create or replace function app.set_work_order_archived(_id text, _archived boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  label text := app.display_id(_id, 'WO');
begin
  perform app.require_admin();
  select * into work_order from public.work_orders w where w.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _id);
  end if;
  if (work_order.archived_at is not null) = coalesce(_archived, false) then
    return;
  end if;
  if _archived and work_order.status <> 'completed' then
    perform app.refuse('PT409', label || ' is ' || app.work_order_status_title(work_order.status)
      || '. Only a completed work order can be archived.');
  end if;

  update public.work_orders w
  set archived_at = case when _archived then now() end
  where w.id = _id;
  perform app.audit('updated', 'work_orders', _id,
    case when _archived then 'Archived work order ' || label
      else 'Restored work order ' || label || ' from the archive' end,
    jsonb_build_object('archived', jsonb_build_object('from', not _archived, 'to', _archived)));
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.delete_tool(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_tool(id); $$;

create or replace function public.delete_facility(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_facility(id); $$;

create or replace function public.delete_asset(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_asset(id); $$;

create or replace function public.delete_account(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_account(id); $$;

create or replace function public.set_report_archived(id text, archived boolean)
returns void language sql security invoker set search_path = ''
as $$ select app.set_report_archived(id, archived); $$;

create or replace function public.set_work_order_archived(id text, archived boolean)
returns void language sql security invoker set search_path = ''
as $$ select app.set_work_order_archived(id, archived); $$;

revoke execute on function
  public.delete_tool(text),
  public.delete_facility(text),
  public.delete_asset(text),
  public.delete_account(text),
  public.set_report_archived(text, boolean),
  public.set_work_order_archived(text, boolean)
from public, anon;
grant execute on function
  public.delete_tool(text),
  public.delete_facility(text),
  public.delete_asset(text),
  public.delete_account(text),
  public.set_report_archived(text, boolean),
  public.set_work_order_archived(text, boolean)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
