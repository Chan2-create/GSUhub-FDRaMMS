-- Tool requests (Chris, 2026-11-16): an administrator asks, the technician
-- confirms by scanning the tool.
--
-- Until now the console's Check Out lent a tool on the spot and its Check
-- In closed the loan on the spot, whether or not the tool had changed
-- hands. Now neither moves the tool:
--
--   Check Out  asks a technician to collect a tool. The tool is reserved
--              for them, and becomes theirs (a loan, as before) only when
--              they scan its QR code and confirm they have it.
--   Check In   asks the technician holding a tool to return it by a date
--              and time. The loan closes only when they scan the tool and
--              confirm they have handed it back.
--
-- A request is one row of public.tool_requests, kept for good as the
-- history of what was asked, by whom, of whom, and how it ended:
--
--   kind      status      shown as
--   checkOut  pending     Pending Confirmation
--   checkOut  confirmed   Borrowed
--   checkOut  cancelled   Cancelled
--   checkOut  expired     Expired (not collected in time)
--   checkIn   pending     Awaiting Return, or Overdue once due_at passes
--   checkIn   confirmed   Returned
--   checkIn   cancelled   Cancelled
--
-- The loan itself stays what it was: a tool out with a technician,
-- tool_loans, opened and closed in the same transaction as the tool's
-- status. Every hand-over, either way, is confirmed with the code scanned
-- from the tool itself, checked here, not in the app.
--
-- Time-based moments (a checkout never collected, a return due within the
-- hour, a return overdue) are swept every five minutes by pg_cron where
-- the database has it, as the hosted project does.

-- ------------------------------------------------------------ tool status

-- Reserved: a checkout request waits for the technician to collect it.
alter table public.tools drop constraint tools_status_check;
alter table public.tools add constraint tools_status_check
  check (status in ('available', 'reserved', 'borrowed', 'inRepair', 'retired'));

create or replace function app.tool_status_label(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'available' then 'Available'
    when 'reserved' then 'Reserved'
    when 'borrowed' then 'Borrowed'
    when 'inRepair' then 'In repair'
    when 'retired' then 'Retired'
    else status
  end;
$$;

-- ------------------------------------------------------------ notifications

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'reportAcknowledged', 'workOrderAssigned', 'taskAssigned',
  'statusUpdate', 'maintenanceCompleted', 'lowStockAlert',
  'reportSubmitted', 'workStarted', 'reviewRequested',
  'materialsRequested', 'accountRequested',
  -- To the technician.
  'toolCheckoutRequested', 'toolReturnRequested', 'toolReturnDue',
  -- To the administrators.
  'toolCheckoutConfirmed', 'toolReturned', 'toolCheckoutPending',
  -- To either.
  'toolOverdue', 'toolRequestCancelled'
));

-- ------------------------------------------------------------ the table

create table public.tool_requests (
  id text primary key default app.new_id(),
  kind text not null check (kind in ('checkOut', 'checkIn')),
  tool_id text not null references public.tools (id),
  -- As the tool was when asked, so the history reads the same after the
  -- tool is renamed, relabelled or deleted.
  tool_name text not null,
  tool_code text not null,
  qr_code text not null,
  -- The technician asked to collect or return it.
  personnel_id text not null references public.users (id),
  -- The administrator who asked.
  requested_by text not null references public.users (id),
  requested_at timestamptz not null default now(),
  -- Check Out: when the technician is to collect the tool.
  checkout_at timestamptz,
  -- Check Out: when it is expected back. Check In: when it is to be back.
  due_at timestamptz,
  -- Check Out: when an uncollected request lapses and the tool is freed.
  expires_at timestamptz,
  purpose text check (char_length(purpose) <= 200),
  -- The administrator's instructions or message.
  message text check (char_length(message) <= 500),
  work_order_id text references public.work_orders (id),
  -- Check Out: the loan its confirmation opened. Check In: the loan to close.
  loan_id text references public.tool_loans (id),
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'cancelled', 'expired')),
  confirmed_at timestamptz,
  -- When it was cancelled or lapsed, and who cancelled it.
  closed_at timestamptz,
  closed_by text references public.users (id),
  -- The sweep's own marks, so each reminder goes once.
  reminded_at timestamptz,
  overdue_notified_at timestamptz,
  check (status <> 'confirmed' or confirmed_at is not null),
  check (status not in ('cancelled', 'expired') or closed_at is not null),
  check (kind <> 'checkOut' or (checkout_at is not null and purpose is not null and expires_at is not null)),
  check (kind <> 'checkIn' or (loan_id is not null and due_at is not null)),
  check (due_at is null or checkout_at is null or due_at > checkout_at)
);

-- One open request per tool: a tool is not asked of two people at once.
create unique index tool_requests_one_pending_per_tool
  on public.tool_requests (tool_id) where status = 'pending';
create index tool_requests_tool_idx on public.tool_requests (tool_id, requested_at desc);
create index tool_requests_personnel_idx on public.tool_requests (personnel_id, requested_at desc);
create index tool_requests_pending_idx on public.tool_requests (kind, requested_at) where status = 'pending';
create index tool_requests_requested_by_idx on public.tool_requests (requested_by);
create index tool_requests_loan_idx on public.tool_requests (loan_id);
create index tool_requests_work_order_idx on public.tool_requests (work_order_id);
create index tool_requests_closed_by_idx on public.tool_requests (closed_by);

alter table public.tool_requests enable row level security;
revoke all on table public.tool_requests from public, anon, authenticated;
grant select on table public.tool_requests to authenticated;
grant all on table public.tool_requests to service_role;

-- Administrators see every request; a technician, those made of them.
-- Nobody writes a row directly: the functions below do.
create policy tool_requests_select on public.tool_requests
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_personnel()) and personnel_id = (select app.uid()))
  );

alter publication supabase_realtime add table public.tool_requests;

-- ------------------------------------------------------------ helpers

-- A moment as people on campus read it. The Philippines keeps UTC+8 all
-- year, so no time zone database is needed.
create or replace function app.local_time(_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char((_at at time zone 'UTC') + interval '8 hours', 'Mon FMDD, YYYY FMHH12:MI AM');
$$;

-- Refuses unless [_scanned_code] is the QR code on the tool, saying which
-- tool was scanned instead when it is another one.
create or replace function app.require_scanned_tool(_tool_id text, _scanned_code text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  tool public.tools;
  other public.tools;
  code text := upper(btrim(coalesce(_scanned_code, '')));
begin
  select * into tool from public.tools t where t.id = _tool_id;
  if code = '' then
    perform app.refuse('PT422', 'Scan the QR code on ' || tool.name || ' (' || tool.tool_code || ').');
  end if;
  if code = upper(tool.qr_code) then
    return;
  end if;
  select * into other from public.tools t
  where upper(t.qr_code) = code and t.deleted_at is null
  limit 1;
  if found then
    perform app.refuse('PT409', 'That is ' || other.name || ' (' || other.tool_code || '), not '
      || tool.name || ' (' || tool.tool_code || '). Scan the QR code on ' || tool.name || '.');
  end if;
  perform app.refuse('PT409', 'That code is not on ' || tool.name || ' (' || tool.tool_code
    || '). Scan the QR code on ' || tool.name || '.');
end;
$$;

-- A notice, cut to the table's limits.
create or replace function app.notify_tool(
  _recipient_id text,
  _type text,
  _title text,
  _body text,
  _request_id text
)
returns void
language sql
security definer
set search_path = ''
as $$
  select app.notify(_recipient_id, _type, left(_title, 120), left(_body, 1000),
    'tool_requests', _request_id);
$$;

-- ------------------------------------------------------------ Check Out

-- An administrator asks a technician to collect a tool on the shelf. The
-- tool is reserved for them until they confirm by scanning it, or the
-- request is cancelled or lapses. Returns the request's id.
create or replace function app.request_tool_checkout(
  _tool_id text,
  _personnel_id text,
  _checkout_at timestamptz,
  _due_at timestamptz,
  _purpose text,
  _message text default null,
  _work_order_id text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_id text := app.new_id();
  tool public.tools;
  person public.users;
  checkout_at timestamptz := coalesce(_checkout_at, now());
  purpose text := app.blank_to_null(_purpose);
  message text := app.blank_to_null(_message);
  expires_at timestamptz;
begin
  perform app.require_admin();

  select * into person from public.users u where u.id = _personnel_id;
  if not found or person.role <> 'maintenancePersonnel' or person.account_status <> 'active' then
    perform app.refuse('PT422', 'Pick an active technician to check the tool out to.');
  end if;
  if purpose is null then
    perform app.refuse('PT422', 'Say what the tool is for.');
  end if;
  if _due_at is not null and _due_at <= greatest(checkout_at, now()) then
    perform app.refuse('PT422', 'The expected return must be after the checkout.');
  end if;

  select * into tool from public.tools t where t.id = _tool_id for update;
  if not found then
    perform app.refuse('PT404', 'This tool is no longer in the inventory.');
  end if;
  if tool.deleted_at is not null then
    perform app.refuse('PT404', tool.name || ' has been deleted.');
  end if;
  if tool.status <> 'available' then
    perform app.refuse('PT409', tool.name || ' cannot be checked out: it is '
      || lower(app.tool_status_label(tool.status)) || '.');
  end if;

  -- Lapses a day after the agreed time, or at the expected return if
  -- sooner; never within the hour of being asked.
  expires_at := greatest(
    least(checkout_at + interval '24 hours', coalesce(_due_at, 'infinity'::timestamptz)),
    now() + interval '1 hour');

  insert into public.tool_requests (id, kind, tool_id, tool_name, tool_code, qr_code,
    personnel_id, requested_by, checkout_at, due_at, expires_at, purpose, message, work_order_id)
  values (request_id, 'checkOut', tool.id, tool.name, tool.tool_code, tool.qr_code,
    person.id, (select app.uid()), checkout_at, _due_at, expires_at, purpose, message,
    _work_order_id);

  update public.tools t set status = 'reserved', updated_at = now() where t.id = tool.id;

  perform app.audit('created', 'tool_requests', request_id,
    'Asked ' || person.full_name || ' to collect ' || tool.name || ' (' || tool.tool_code || ')',
    jsonb_build_object('toolId', tool.id, 'kind', 'checkOut', 'personnelId', person.id,
      'checkoutAt', checkout_at, 'dueAt', _due_at));

  perform app.notify_tool(person.id, 'toolCheckoutRequested',
    'Collect ' || tool.name || ' (' || tool.tool_code || ')',
    'GSU has checked out ' || tool.name || ' (' || tool.tool_code || ') to you. Collect it on '
      || app.local_time(checkout_at)
      || coalesce('; it is expected back by ' || app.local_time(_due_at), '') || '.'
      || ' Purpose: ' || purpose || '.'
      || coalesce(' ' || message, '')
      || ' When you have it, scan its QR code in GSUhub to confirm.',
    request_id);

  return request_id;
end;
$$;

-- The technician it was asked of confirms they have the tool, with the
-- code scanned from it. Opens the loan, as a borrow always has. Returns it.
create or replace function app.confirm_tool_checkout(_request_id text, _scanned_code text)
returns public.tool_loans
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  request public.tool_requests;
  tool public.tools;
  person public.users;
  loan public.tool_loans;
begin
  perform app.require_session();
  select * into request from public.tool_requests r where r.id = _request_id for update;
  if not found or request.kind <> 'checkOut' then
    perform app.refuse('PT404', 'This checkout request is no longer there.');
  end if;
  if not (select app.is_personnel()) or request.personnel_id <> caller then
    perform app.refuse('PT403', 'This checkout is for another technician; only they can confirm it.');
  end if;
  if request.status = 'confirmed' then
    perform app.refuse('PT409', 'You have already confirmed receiving ' || request.tool_name || '.');
  end if;
  if request.status = 'cancelled' then
    perform app.refuse('PT409', 'GSU cancelled this checkout of ' || request.tool_name || '.');
  end if;
  if request.status = 'expired' or request.expires_at <= now() then
    perform app.refuse('PT409', 'This checkout of ' || request.tool_name
      || ' has lapsed. Ask GSU to send it again.');
  end if;

  perform app.require_scanned_tool(request.tool_id, _scanned_code);

  select * into tool from public.tools t where t.id = request.tool_id for update;
  if tool.status <> 'reserved' then
    perform app.refuse('PT409', tool.name || ' is ' || lower(app.tool_status_label(tool.status))
      || ', not waiting for you. Ask GSU.');
  end if;
  select * into person from public.users u where u.id = caller;

  insert into public.tool_loans (tool_id, tool_name, borrowed_by, work_order_id,
    expected_return_at, condition_on_borrow)
  values (tool.id, tool.name, caller, request.work_order_id, request.due_at, tool.condition)
  returning * into loan;

  update public.tools t
  set status = 'borrowed', current_holder_id = caller, current_loan_id = loan.id, updated_at = now()
  where t.id = tool.id;

  update public.tool_requests r
  set status = 'confirmed', confirmed_at = now(), loan_id = loan.id
  where r.id = request.id;

  perform app.audit('created', 'tool_loans', loan.id,
    'Received ' || tool.name || ' (' || tool.tool_code || '), confirmed by scanning it',
    jsonb_build_object('toolId', tool.id, 'requestId', request.id, 'condition', tool.condition)
      || case when request.work_order_id is not null
           then jsonb_build_object('workOrderId', request.work_order_id) else '{}' end);

  perform app.notify_admins('toolCheckoutConfirmed',
    left(person.full_name || ' received ' || tool.name, 120),
    left(person.full_name || ' scanned ' || tool.name || ' (' || tool.tool_code || ') and confirmed '
      || 'receiving it on ' || app.local_time(now())
      || coalesce('. It is expected back by ' || app.local_time(request.due_at), '') || '.', 1000),
    'tool_requests', request.id);

  return loan;
end;
$$;

-- ------------------------------------------------------------ Check In

-- An administrator asks the technician holding a tool to return it by a
-- date and time. Nothing moves until they scan it back. Returns the
-- request's id.
create or replace function app.request_tool_return(_loan_id text, _due_at timestamptz, _message text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_id text := app.new_id();
  loan public.tool_loans;
  tool public.tools;
  person public.users;
  message text := app.blank_to_null(_message);
begin
  perform app.require_admin();

  select * into loan from public.tool_loans l where l.id = _loan_id for update;
  if not found then
    perform app.refuse('PT404', 'No tool loan ' || coalesce(_loan_id, ''));
  end if;
  if loan.returned_at is not null then
    perform app.refuse('PT409', loan.tool_name || ' has already been returned.');
  end if;
  if _due_at is null or _due_at <= now() then
    perform app.refuse('PT422', 'Pick a return date and time that has not passed.');
  end if;
  if exists (select 1 from public.tool_requests r where r.tool_id = loan.tool_id and r.status = 'pending') then
    perform app.refuse('PT409', 'A return of ' || loan.tool_name || ' is already requested.');
  end if;

  select * into tool from public.tools t where t.id = loan.tool_id;
  select * into person from public.users u where u.id = loan.borrowed_by;

  insert into public.tool_requests (id, kind, tool_id, tool_name, tool_code, qr_code,
    personnel_id, requested_by, due_at, message, work_order_id, loan_id)
  values (request_id, 'checkIn', tool.id, tool.name, tool.tool_code, tool.qr_code,
    loan.borrowed_by, (select app.uid()), _due_at, message, loan.work_order_id, loan.id);

  perform app.audit('created', 'tool_requests', request_id,
    'Asked ' || person.full_name || ' to return ' || tool.name || ' (' || tool.tool_code || ') by '
      || app.local_time(_due_at),
    jsonb_build_object('toolId', tool.id, 'kind', 'checkIn', 'loanId', loan.id, 'dueAt', _due_at));

  perform app.notify_tool(person.id, 'toolReturnRequested',
    'Return ' || tool.name || ' (' || tool.tool_code || ')',
    'GSU asks you to return ' || tool.name || ' (' || tool.tool_code || ') by '
      || app.local_time(_due_at) || '.'
      || coalesce(' ' || message, '')
      || ' When you hand it back, scan its QR code in GSUhub to confirm the return.',
    request_id);

  return request_id;
end;
$$;

-- The technician holding a tool hands it back, confirmed with the code
-- scanned from it, saying what condition it is in. Closes the loan as a
-- return always has (poor goes to repair), and the return request if
-- there is one.
create or replace function app.confirm_tool_return(
  _loan_id text,
  _scanned_code text,
  _condition text,
  _notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  loan public.tool_loans;
  tool public.tools;
  person public.users;
  request public.tool_requests;
  late text := '';
begin
  perform app.require_session();
  select * into loan from public.tool_loans l where l.id = _loan_id for update;
  if not found then
    perform app.refuse('PT404', 'No tool loan ' || coalesce(_loan_id, ''));
  end if;
  if not (select app.is_personnel()) or loan.borrowed_by <> caller then
    perform app.refuse('PT403', 'This tool is on loan to another technician; only they can return it.');
  end if;
  if loan.returned_at is not null then
    perform app.refuse('PT409', loan.tool_name || ' has already been returned.');
  end if;
  if not app.is_condition(_condition) then
    perform app.refuse('PT422', 'Say what condition the tool is in.');
  end if;

  perform app.require_scanned_tool(loan.tool_id, _scanned_code);

  select * into tool from public.tools t where t.id = loan.tool_id for update;
  select * into person from public.users u where u.id = caller;
  select * into request from public.tool_requests r
  where r.loan_id = loan.id and r.kind = 'checkIn' and r.status = 'pending'
  for update;

  update public.tool_loans l
  set returned_at = now(), condition_on_return = _condition,
      notes = coalesce(app.blank_to_null(_notes), l.notes)
  where l.id = loan.id;
  update public.tools t
  set status = case when _condition = 'poor' then 'inRepair' else 'available' end,
      condition = _condition,
      current_holder_id = null,
      current_loan_id = null,
      updated_at = now()
  where t.id = tool.id;

  if request.id is not null then
    update public.tool_requests r set status = 'confirmed', confirmed_at = now() where r.id = request.id;
    if request.due_at < now() then
      late := ', after it was due on ' || app.local_time(request.due_at);
    end if;
  end if;

  perform app.audit('updated', 'tool_loans', loan.id,
    'Returned ' || loan.tool_name || ' in ' || lower(app.condition_label(_condition))
      || ' condition, confirmed by scanning it',
    jsonb_build_object('toolId', loan.tool_id, 'conditionOnBorrow', loan.condition_on_borrow,
      'conditionOnReturn', _condition)
      || case when request.id is not null then jsonb_build_object('requestId', request.id) else '{}' end);

  perform app.notify_admins('toolReturned',
    left(person.full_name || ' returned ' || tool.name, 120),
    left(person.full_name || ' scanned ' || tool.name || ' (' || tool.tool_code || ') and confirmed '
      || 'returning it on ' || app.local_time(now()) || late || ', in '
      || lower(app.condition_label(_condition)) || ' condition'
      || case when _condition = 'poor' then '; it went to repair' else '' end || '.'
      || coalesce(' Note: ' || app.blank_to_null(_notes), ''), 1000),
    case when request.id is null then 'tool_loans' else 'tool_requests' end,
    coalesce(request.id, loan.id));
end;
$$;

-- ------------------------------------------------------------ cancelling

-- An administrator withdraws a request still waiting. A reserved tool goes
-- back on the shelf.
create or replace function app.cancel_tool_request(_request_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.tool_requests;
  what text;
begin
  perform app.require_admin();
  select * into request from public.tool_requests r where r.id = _request_id for update;
  if not found then
    perform app.refuse('PT404', 'This request is no longer there.');
  end if;
  if request.status <> 'pending' then
    perform app.refuse('PT409', 'This request is already ' || case request.status
      when 'confirmed' then 'confirmed' when 'cancelled' then 'cancelled' else 'lapsed' end || '.');
  end if;

  update public.tool_requests r
  set status = 'cancelled', closed_at = now(), closed_by = (select app.uid())
  where r.id = request.id;
  if request.kind = 'checkOut' then
    update public.tools t set status = 'available', updated_at = now()
    where t.id = request.tool_id and t.status = 'reserved';
  end if;

  what := case request.kind when 'checkOut' then 'checkout' else 'return' end;
  perform app.audit('statusChanged', 'tool_requests', request.id,
    'Cancelled the ' || what || ' of ' || request.tool_name || ' (' || request.tool_code || ')',
    jsonb_build_object('status', jsonb_build_object('from', 'pending', 'to', 'cancelled')));

  perform app.notify_tool(request.personnel_id, 'toolRequestCancelled',
    'Cancelled: ' || what || ' of ' || request.tool_name,
    'GSU cancelled the request to ' || case request.kind when 'checkOut' then 'collect '
      else 'return ' end || request.tool_name || ' (' || request.tool_code || '). '
      || case request.kind when 'checkOut' then 'You do not need to collect it.'
         else 'Keep it until GSU asks again.' end,
    request.id);
  perform app.notify_admins('toolRequestCancelled',
    left('Cancelled: ' || what || ' of ' || request.tool_name, 120),
    left((select u.full_name from public.users u where u.id = (select app.uid()))
      || ' cancelled the ' || what || ' of ' || request.tool_name || ' (' || request.tool_code || ').', 1000),
    'tool_requests', request.id);
end;
$$;

-- ------------------------------------------------------------ the sweep

-- What time alone changes, every five minutes: a checkout never collected
-- lapses and frees the tool; administrators hear of one still waiting an
-- hour after the agreed time; a technician hears of a return due within
-- the hour; and everyone concerned hears of a return overdue. Each notice
-- goes once. Runs with nobody signed in, so its audit entries are
-- GSUhub's own.
create or replace function app.sweep_tool_requests()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  request public.tool_requests;
  person text;
begin
  for request in
    select * from public.tool_requests r
    where r.status = 'pending' and r.kind = 'checkOut' and r.expires_at <= now()
    for update skip locked
  loop
    select u.full_name into person from public.users u where u.id = request.personnel_id;
    update public.tool_requests r set status = 'expired', closed_at = now() where r.id = request.id;
    update public.tools t set status = 'available', updated_at = now()
    where t.id = request.tool_id and t.status = 'reserved';
    insert into public.audit_logs (actor_id, actor_name, action, entity_type, entity_id, description, changes)
    values ('system', 'GSUhub', 'statusChanged', 'tool_requests', request.id,
      'The checkout of ' || request.tool_name || ' (' || request.tool_code || ') lapsed uncollected',
      jsonb_build_object('status', jsonb_build_object('from', 'pending', 'to', 'expired')));
    perform app.notify_tool(request.personnel_id, 'toolRequestCancelled',
      'Lapsed: checkout of ' || request.tool_name,
      'The request to collect ' || request.tool_name || ' (' || request.tool_code || ') lapsed on '
        || app.local_time(request.expires_at) || ' before you confirmed it. Ask GSU if you still need it.',
      request.id);
    perform app.notify_admins('toolRequestCancelled',
      left('Lapsed: checkout of ' || request.tool_name, 120),
      left(coalesce(person, 'The technician') || ' did not confirm collecting ' || request.tool_name
        || ' (' || request.tool_code || ') by ' || app.local_time(request.expires_at)
        || '. The request lapsed and the tool is back on the shelf.', 1000),
      'tool_requests', request.id);
  end loop;

  for request in
    select * from public.tool_requests r
    where r.status = 'pending' and r.kind = 'checkOut' and r.reminded_at is null
      and r.checkout_at + interval '1 hour' <= now()
    for update skip locked
  loop
    select u.full_name into person from public.users u where u.id = request.personnel_id;
    update public.tool_requests r set reminded_at = now() where r.id = request.id;
    perform app.notify_admins('toolCheckoutPending',
      left('Not collected yet: ' || request.tool_name, 120),
      left(coalesce(person, 'The technician') || ' has not confirmed collecting ' || request.tool_name
        || ' (' || request.tool_code || '), due for collection on ' || app.local_time(request.checkout_at)
        || '. It stays reserved until ' || app.local_time(request.expires_at) || '.', 1000),
      'tool_requests', request.id);
  end loop;

  for request in
    select * from public.tool_requests r
    where r.status = 'pending' and r.kind = 'checkIn' and r.reminded_at is null
      and r.due_at > now() and r.due_at <= now() + interval '1 hour'
    for update skip locked
  loop
    update public.tool_requests r set reminded_at = now() where r.id = request.id;
    perform app.notify_tool(request.personnel_id, 'toolReturnDue',
      'Return ' || request.tool_name || ' soon',
      request.tool_name || ' (' || request.tool_code || ') is due back at GSU by '
        || app.local_time(request.due_at) || '. Scan its QR code when you hand it back.',
      request.id);
  end loop;

  for request in
    select * from public.tool_requests r
    where r.status = 'pending' and r.kind = 'checkIn' and r.overdue_notified_at is null
      and r.due_at <= now()
    for update skip locked
  loop
    select u.full_name into person from public.users u where u.id = request.personnel_id;
    update public.tool_requests r
    set overdue_notified_at = now(), reminded_at = coalesce(r.reminded_at, now())
    where r.id = request.id;
    perform app.notify_tool(request.personnel_id, 'toolOverdue',
      'Overdue: ' || request.tool_name,
      request.tool_name || ' (' || request.tool_code || ') was due back at GSU by '
        || app.local_time(request.due_at) || '. Return it, and scan its QR code to confirm.',
      request.id);
    perform app.notify_admins('toolOverdue',
      left('Overdue: ' || request.tool_name, 120),
      left(coalesce(person, 'The technician') || ' has not returned ' || request.tool_name
        || ' (' || request.tool_code || '), due back by ' || app.local_time(request.due_at) || '.', 1000),
      'tool_requests', request.id);
  end loop;
end;
$$;

-- ------------------------------------------------------------ borrowing by scan

-- A technician takes a tool off the shelf for themselves, confirmed with
-- the code scanned from it. A tool reserved for someone is not theirs to
-- take. Returns the loan.
create or replace function app.borrow_tool_by_scan(
  _tool_id text,
  _scanned_code text,
  _work_order_id text default null
)
returns public.tool_loans
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  tool public.tools;
  loan public.tool_loans;
  reserved_for text;
  for_work text := coalesce(' for ' || app.display_id(_work_order_id, 'WO'), '');
begin
  perform app.require_session();
  if not (select app.is_personnel()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;

  select * into tool from public.tools t where t.id = _tool_id for update;
  if not found then
    perform app.refuse('PT404', 'No tool ' || coalesce(_tool_id, ''));
  end if;
  if tool.deleted_at is not null then
    perform app.refuse('PT404', tool.name || ' has been deleted.');
  end if;
  perform app.require_scanned_tool(tool.id, _scanned_code);
  if tool.status = 'reserved' then
    select r.personnel_id into reserved_for from public.tool_requests r
    where r.tool_id = tool.id and r.status = 'pending';
    if reserved_for = caller then
      perform app.refuse('PT409', 'GSU has checked ' || tool.name || ' out to you. Confirm that '
        || 'request instead.');
    end if;
    perform app.refuse('PT409', tool.name || ' is reserved for '
      || coalesce((select u.full_name from public.users u where u.id = reserved_for), 'another technician')
      || '.');
  end if;
  if tool.status <> 'available' then
    perform app.refuse('PT409', tool.name || ' cannot be borrowed: it is '
      || lower(app.tool_status_label(tool.status)) || '.');
  end if;

  insert into public.tool_loans (tool_id, tool_name, borrowed_by, work_order_id, condition_on_borrow)
  values (tool.id, tool.name, caller, _work_order_id, tool.condition)
  returning * into loan;
  update public.tools t
  set status = 'borrowed', current_holder_id = caller, current_loan_id = loan.id, updated_at = now()
  where t.id = tool.id;

  perform app.audit('created', 'tool_loans', loan.id,
    'Borrowed ' || tool.name || for_work || ', confirmed by scanning it',
    jsonb_build_object('toolId', tool.id, 'condition', tool.condition)
      || case when _work_order_id is not null then jsonb_build_object('workOrderId', _work_order_id) else '{}' end);
  return loan;
end;
$$;

-- The old ways, which moved a tool without the tool being scanned: an
-- administrator's Check Out and Check In, and a technician's borrow or
-- return from a list. Kept by name so an app not yet updated is told
-- what to do rather than given an error about a missing function.
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
begin
  perform app.require_session();
  if (select app.is_admin()) then
    perform app.refuse('PT409', 'Check Out now asks the technician to collect the tool; it is '
      || 'theirs once they scan it. Reload the console.');
  end if;
  perform app.refuse('PT409', 'Borrowing now asks you to scan the tool. Update GSUhub.');
  return null;
end;
$$;

create or replace function app.return_tool(_loan_id text, _condition text, _notes text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.require_session();
  if (select app.is_admin()) then
    perform app.refuse('PT409', 'Check In now asks the technician to return the tool; it is back '
      || 'once they scan it. Reload the console.');
  end if;
  perform app.refuse('PT409', 'Returning now asks you to scan the tool. Update GSUhub.');
end;
$$;

-- ------------------------------------------------------------ status and deletion

-- To repair, back from repair, or retired. Never a tool that is out or
-- reserved: those move through their requests.
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
  if _status in ('borrowed', 'reserved') then
    perform app.refuse('PT409', 'Check a tool out to lend it.');
  end if;
  if stored.status = 'borrowed' then
    perform app.refuse('PT409', stored.name || ' is out with a technician; check it in first.');
  end if;
  if stored.status = 'reserved' then
    perform app.refuse('PT409', stored.name || ' is waiting to be collected; cancel that checkout first.');
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

-- A tool, unless it is out on loan or waiting to be collected.
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
  if tool.status = 'reserved'
     or exists (select 1 from public.tool_requests r where r.tool_id = _id and r.status = 'pending') then
    perform app.refuse('PT409', tool.name || ' has a request waiting; cancel it first.');
  end if;

  update public.tools t set deleted_at = now(), updated_at = now() where t.id = _id;
  perform app.audit('deleted', 'tools', _id,
    'Deleted ' || tool.name || ' (' || tool.tool_code || ') from the tools');
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.request_tool_checkout(
  tool_id text, personnel_id text, checkout_at timestamptz, due_at timestamptz,
  purpose text, message text default null, work_order_id text default null
)
returns text language sql security invoker set search_path = ''
as $$ select app.request_tool_checkout(tool_id, personnel_id, checkout_at, due_at, purpose, message, work_order_id); $$;

create or replace function public.confirm_tool_checkout(request_id text, scanned_code text)
returns public.tool_loans language sql security invoker set search_path = ''
as $$ select app.confirm_tool_checkout(request_id, scanned_code); $$;

create or replace function public.request_tool_return(loan_id text, due_at timestamptz, message text default null)
returns text language sql security invoker set search_path = ''
as $$ select app.request_tool_return(loan_id, due_at, message); $$;

create or replace function public.confirm_tool_return(
  loan_id text, scanned_code text, condition text, notes text default null
)
returns void language sql security invoker set search_path = ''
as $$ select app.confirm_tool_return(loan_id, scanned_code, condition, notes); $$;

create or replace function public.cancel_tool_request(request_id text)
returns void language sql security invoker set search_path = ''
as $$ select app.cancel_tool_request(request_id); $$;

create or replace function public.borrow_tool_by_scan(
  tool_id text, scanned_code text, work_order_id text default null
)
returns public.tool_loans language sql security invoker set search_path = ''
as $$ select app.borrow_tool_by_scan(tool_id, scanned_code, work_order_id); $$;

revoke execute on function
  public.request_tool_checkout(text, text, timestamptz, timestamptz, text, text, text),
  public.confirm_tool_checkout(text, text),
  public.request_tool_return(text, timestamptz, text),
  public.confirm_tool_return(text, text, text, text),
  public.cancel_tool_request(text),
  public.borrow_tool_by_scan(text, text, text)
from public, anon;
grant execute on function
  public.request_tool_checkout(text, text, timestamptz, timestamptz, text, text, text),
  public.confirm_tool_checkout(text, text),
  public.request_tool_return(text, timestamptz, text),
  public.confirm_tool_return(text, text, text, text),
  public.cancel_tool_request(text),
  public.borrow_tool_by_scan(text, text, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
-- The sweep is the scheduler's, not a signed-in person's.
revoke execute on function app.sweep_tool_requests() from authenticated;

-- ------------------------------------------------------------ the schedule

-- Every five minutes, where the database has pg_cron (the hosted project
-- and the local stack). The test database has not, and skips this; the
-- tests run the sweep themselves.
do $do$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    grant usage on schema cron to postgres;
    grant all privileges on all tables in schema cron to postgres;
    perform cron.schedule('gsuhub-tool-requests', '*/5 * * * *', 'select app.sweep_tool_requests()');
  end if;
end
$do$;
