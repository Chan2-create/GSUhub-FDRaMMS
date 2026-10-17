-- Tools (Objective 1, M4): ToolRepositoryImpl. A tool's status and its
-- loan record never disagree (§1.5 accountability): borrowing and
-- returning change both in one transaction.

create or replace function app.require_free_tool_codes(_tool_code text, _qr_code text, _except_id text default null)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.tools t where t.tool_code = _tool_code and t.id is distinct from _except_id) then
    perform app.refuse('PT409', 'Another tool already has the ID ' || _tool_code || '.');
  end if;
  perform app.require_free_code(_qr_code, _except_id);
end;
$$;

create or replace function app.tool_fields(
  _tool_code text,
  _name text,
  _condition text,
  _qr_code text,
  _category text,
  _storage_location text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'toolCode', _tool_code,
    'name', _name,
    'condition', _condition,
    'qrCode', _qr_code,
    'category', _category,
    'storageLocation', _storage_location
  );
$$;

-- A new tool, available. Returns its id.
create or replace function app.create_tool(
  _tool_code text,
  _name text,
  _condition text,
  _qr_code text,
  _category text default null,
  _storage_location text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_tool_id text := app.new_id();
begin
  perform app.require_admin();
  perform app.require_free_tool_codes(btrim(_tool_code), btrim(_qr_code));
  insert into public.tools (id, tool_code, name, status, condition, category, storage_location, qr_code)
  values (new_tool_id, btrim(_tool_code), btrim(_name), 'available', _condition,
    app.blank_to_null(_category), app.blank_to_null(_storage_location), btrim(_qr_code));
  perform app.audit('created', 'tools', new_tool_id,
    'Added ' || btrim(_name) || ' (' || btrim(_tool_code) || ') to the tools');
  return new_tool_id;
end;
$$;

-- A tool's details. One out on loan keeps the condition it left in; its
-- return records what it comes back in.
create or replace function app.update_tool(
  _id text,
  _tool_code text,
  _name text,
  _condition text,
  _qr_code text,
  _category text default null,
  _storage_location text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.tools;
  fields jsonb;
  changes jsonb;
begin
  perform app.require_admin();
  perform app.require_free_tool_codes(btrim(_tool_code), btrim(_qr_code), _id);
  select * into stored from public.tools t where t.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No tool ' || _id);
  end if;

  fields := app.tool_fields(btrim(_tool_code), btrim(_name),
    case when stored.status = 'borrowed' then stored.condition else _condition end,
    btrim(_qr_code), app.blank_to_null(_category), app.blank_to_null(_storage_location));
  changes := app.field_changes(
    app.tool_fields(stored.tool_code, stored.name, stored.condition, stored.qr_code,
      stored.category, stored.storage_location),
    fields);
  if changes = '{}' then
    return;
  end if;

  update public.tools t
  set tool_code = fields ->> 'toolCode',
      name = fields ->> 'name',
      condition = fields ->> 'condition',
      qr_code = fields ->> 'qrCode',
      category = fields ->> 'category',
      storage_location = fields ->> 'storageLocation',
      updated_at = now()
  where t.id = _id;

  perform app.audit('updated', 'tools', _id,
    'Updated ' || (fields ->> 'name') || ' (' || (fields ->> 'toolCode') || ')', changes);
end;
$$;

-- To repair, back from repair, or retired. Lending is borrow_tool's.
create or replace function app.set_tool_status(_id text, _status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.tools;
begin
  perform app.require_admin();
  select * into stored from public.tools t where t.id = _id for update;
  if not found then
    perform app.refuse('PT404', 'No tool ' || _id);
  end if;
  if stored.status = _status then
    return;
  end if;
  if _status = 'borrowed' then
    perform app.refuse('PT409', 'Check a tool out to lend it.');
  end if;
  if stored.status = 'borrowed' then
    perform app.refuse('PT409', stored.name || ' is out with a technician; check it in first.');
  end if;
  if stored.status = 'retired' then
    perform app.refuse('PT409', stored.name || ' is retired.');
  end if;

  update public.tools t set status = _status, updated_at = now() where t.id = _id;
  perform app.audit('statusChanged', 'tools', _id,
    case _status
      when 'inRepair' then 'Sent ' || stored.name || ' to repair'
      when 'retired' then 'Retired ' || stored.name
      else 'Brought ' || stored.name || ' back from repair'
    end,
    jsonb_build_object('status', jsonb_build_object('from', stored.status, 'to', _status)));
end;
$$;

-- A technician borrows a tool for themselves, or an administrator checks
-- one out to a technician from the console (6.B). Returns the loan.
create or replace function app.borrow_tool(
  _tool_id text,
  _borrower_id text,
  _work_order_id text default null,
  _expected_return_at timestamptz default null
)
returns public.tool_loans
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  tool public.tools;
  borrower public.users;
  loan public.tool_loans;
  for_work text := coalesce(' for ' || app.display_id(_work_order_id, 'WO'), '');
begin
  select * into borrower from public.users u where u.id = _borrower_id;
  if not (
    ((select app.is_personnel()) and _borrower_id = caller)
    or ((select app.is_admin()) and found and borrower.role = 'maintenancePersonnel')
  ) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;

  select * into tool from public.tools t where t.id = _tool_id for update;
  if not found then
    perform app.refuse('PT404', 'No tool ' || _tool_id);
  end if;
  if tool.status <> 'available' then
    perform app.refuse('PT409', tool.name || ' cannot be borrowed: it is '
      || lower(app.tool_status_label(tool.status)) || '.');
  end if;

  insert into public.tool_loans (tool_id, tool_name, borrowed_by, work_order_id,
    expected_return_at, condition_on_borrow)
  values (_tool_id, tool.name, _borrower_id, _work_order_id, _expected_return_at, tool.condition)
  returning * into loan;

  update public.tools t
  set status = 'borrowed', current_holder_id = _borrower_id, current_loan_id = loan.id,
      updated_at = now()
  where t.id = _tool_id;

  perform app.audit('created', 'tool_loans', loan.id,
    case when _borrower_id = caller then 'Borrowed ' || tool.name || for_work
      else 'Checked out ' || tool.name || ' to ' || borrower.full_name || for_work end,
    jsonb_build_object('toolId', _tool_id, 'condition', tool.condition)
      || case when _work_order_id is not null then jsonb_build_object('workOrderId', _work_order_id) else '{}' end);
  return loan;
end;
$$;

-- A tool back, by the technician who has it or an administrator. One
-- that comes back in poor condition goes to repair, not back on the
-- shelf: the next technician would be issued something known broken.
create or replace function app.return_tool(_loan_id text, _condition text, _notes text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  loan public.tool_loans;
begin
  select * into loan from public.tool_loans l where l.id = _loan_id for update;
  if not found then
    perform app.refuse('PT404', 'No tool loan ' || _loan_id);
  end if;
  if not (select app.is_admin())
     and not ((select app.is_personnel()) and loan.borrowed_by = (select app.uid())) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  if loan.returned_at is not null then
    perform app.refuse('PT409', loan.tool_name || ' has already been returned.');
  end if;

  perform 1 from public.tools t where t.id = loan.tool_id for update;
  update public.tool_loans l
  set returned_at = now(), condition_on_return = _condition,
      notes = coalesce(app.blank_to_null(_notes), l.notes)
  where l.id = _loan_id;
  update public.tools t
  set status = case when _condition = 'poor' then 'inRepair' else 'available' end,
      condition = _condition,
      current_holder_id = null,
      current_loan_id = null,
      updated_at = now()
  where t.id = loan.tool_id;

  perform app.audit('updated', 'tool_loans', _loan_id,
    'Returned ' || loan.tool_name || ' in ' || lower(app.condition_label(_condition)) || ' condition',
    jsonb_build_object('toolId', loan.tool_id, 'conditionOnBorrow', loan.condition_on_borrow,
      'conditionOnReturn', _condition));
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.create_tool(
  tool_code text, name text, condition text, qr_code text,
  category text default null, storage_location text default null
)
returns text language sql security invoker set search_path = ''
as $$ select app.create_tool(tool_code, name, condition, qr_code, category, storage_location); $$;

create or replace function public.update_tool(
  id text, tool_code text, name text, condition text, qr_code text,
  category text default null, storage_location text default null
)
returns void language sql security invoker set search_path = ''
as $$ select app.update_tool(id, tool_code, name, condition, qr_code, category, storage_location); $$;

create or replace function public.set_tool_status(id text, status text)
returns void language sql security invoker set search_path = ''
as $$ select app.set_tool_status(id, status); $$;

create or replace function public.borrow_tool(
  tool_id text, borrower_id text, work_order_id text default null,
  expected_return_at timestamptz default null
)
returns public.tool_loans language sql security invoker set search_path = ''
as $$ select app.borrow_tool(tool_id, borrower_id, work_order_id, expected_return_at); $$;

create or replace function public.return_tool(loan_id text, condition text, notes text default null)
returns void language sql security invoker set search_path = ''
as $$ select app.return_tool(loan_id, condition, notes); $$;

revoke execute on function
  public.create_tool(text, text, text, text, text, text),
  public.update_tool(text, text, text, text, text, text, text),
  public.set_tool_status(text, text),
  public.borrow_tool(text, text, text, timestamptz),
  public.return_tool(text, text, text)
from public, anon;
grant execute on function
  public.create_tool(text, text, text, text, text, text),
  public.update_tool(text, text, text, text, text, text, text),
  public.set_tool_status(text, text),
  public.borrow_tool(text, text, text, timestamptz),
  public.return_tool(text, text, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
