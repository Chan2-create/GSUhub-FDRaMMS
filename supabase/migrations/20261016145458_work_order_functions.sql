-- Work orders (Objective 1, M3): raising one from an approved report,
-- moving it, the note to the technician. WorkOrderRepositoryImpl's
-- transactions and the work_orders rules in firebase/firestore.rules.

-- A task is named after its work order's report, and a report title may be
-- 200 characters; the first schema allowed a task 120, which would have
-- refused assigning a report with a long title.
alter table public.tasks drop constraint tasks_title_check;
alter table public.tasks add constraint tasks_title_check
  check (char_length(title) between 1 and 200);

-- Raises a work order for an approved, classified report and assigns it
-- (2.B): the work order, its first task, the report's move to assigned,
-- the technician's notice and open-work count, two audit entries. Returns
-- the work order's id.
create or replace function app.assign_work_order(
  _report_id text,
  _personnel_id text,
  _scheduled_for timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  report public.damage_reports;
  person public.users;
  new_work_order_id text := app.new_id();
begin
  perform app.require_admin();

  select * into report from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  select * into person from public.users u where u.id = _personnel_id for update;
  if not found then
    perform app.refuse('PT404', 'No user ' || _personnel_id);
  end if;

  if report.status <> 'approved' then
    perform app.refuse('PT409', 'Only approved reports can be assigned. This one is '
      || app.report_status_label(report.status) || '.');
  end if;
  if report.work_order_id is not null then
    perform app.refuse('PT409', 'This report already has a work order.');
  end if;
  if report.category is null then
    perform app.refuse('PT409', 'This report has no damage category yet, so no work order can be '
      || 'raised for it. It must be classified first.');
  end if;
  if report.official_priority is null then
    perform app.refuse('PT409', 'This report''s official priority has not been confirmed yet. '
      || 'Confirm it on the report page before assigning the work.');
  end if;
  if person.role <> 'maintenancePersonnel' then
    perform app.refuse('PT409', person.full_name || ' is not maintenance personnel.');
  end if;
  if person.account_status <> 'active' then
    perform app.refuse('PT409', person.full_name || '''s account is inactive and cannot take work.');
  end if;

  insert into public.work_orders (
    id, report_ids, title, description, category, priority, status,
    assigned_personnel_ids, facility_id, facility_name, scheduled_for, created_by
  ) values (
    new_work_order_id, array[_report_id], report.title, report.description, report.category,
    report.official_priority, 'pending', array[_personnel_id], report.facility_id,
    report.facility_name, _scheduled_for, (select app.uid())
  );

  update public.damage_reports r
  set status = 'assigned', work_order_id = new_work_order_id, updated_at = now()
  where r.id = _report_id;

  update public.users u
  set active_task_count = u.active_task_count + 1, updated_at = now()
  where u.id = _personnel_id;

  -- Every work order starts with one task, the job itself, so the
  -- technician's list is never empty of work they hold (5.A). Due on the
  -- target date, or the day it is assigned.
  insert into public.tasks (work_order_id, title, description, assigned_to, status, due_date)
  values (new_work_order_id, report.title, coalesce(report.location_description, report.facility_name),
    _personnel_id, 'pending', coalesce(_scheduled_for, now()));

  -- PersonnelNotice.workOrderAssigned
  perform app.notify(_personnel_id, 'workOrderAssigned', 'New work order',
    'You have been assigned "' || report.title || '"'
      || coalesce(' at ' || report.facility_name, '') || '.',
    'work_orders', new_work_order_id);

  perform app.record_report_move(_report_id, 'assigned', report.status, null, _personnel_id);

  perform app.audit('assigned', 'damage_reports', _report_id, 'Assigned to ' || person.full_name,
    jsonb_build_object('from', 'approved', 'to', 'assigned', 'workOrderId', new_work_order_id,
      'personnelId', _personnel_id));
  perform app.audit('created', 'work_orders', new_work_order_id,
    'Work order created from report ' || _report_id,
    jsonb_build_object('reportId', _report_id, 'personnelId', _personnel_id)
      || case when _scheduled_for is not null
           then jsonb_build_object('scheduledFor',
             to_char(_scheduled_for at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
           else '{}' end);

  return new_work_order_id;
end;
$$;

-- A work order's move (2.B, 5.B). An administrator makes any legal move.
-- A technician assigned to it only starts it: submitting work for review
-- goes with the accomplishment report, and sign-off is the
-- administrator's.
create or replace function app.set_work_order_status(_work_order_id text, _to text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.work_orders;
begin
  if not (select app.is_admin()) then
    select * into stored from public.work_orders w where w.id = _work_order_id;
    if not (select app.is_personnel())
       or not found
       or not ((select app.uid()) = any (stored.assigned_personnel_ids))
       or not (stored.status in ('pending', 'inProgress') and _to = 'inProgress') then
      perform app.refuse('PT403', 'You do not have permission to perform this action.');
    end if;
  end if;
  perform app.move_work_order(_work_order_id, _to);
end;
$$;

create or replace function app.update_admin_notes(_work_order_id text, _notes text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  note text := app.blank_to_null(_notes);
begin
  perform app.require_admin();
  perform 1 from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;

  update public.work_orders w set admin_notes = note, updated_at = now() where w.id = _work_order_id;

  perform app.audit('updated', 'work_orders', _work_order_id,
    case
      when note is null then 'Note to the technician removed'
      when char_length(note) > 80 then 'Note to the technician: "' || left(note, 80) || '…"'
      else 'Note to the technician: "' || note || '"'
    end,
    jsonb_build_object('adminNotes', note));
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.assign_work_order(
  report_id text, personnel_id text, scheduled_for timestamptz default null
)
returns text language sql security invoker set search_path = ''
as $$ select app.assign_work_order(report_id, personnel_id, scheduled_for); $$;

create or replace function public.set_work_order_status(work_order_id text, to_status text)
returns void language sql security invoker set search_path = ''
as $$ select app.set_work_order_status(work_order_id, to_status); $$;

create or replace function public.update_admin_notes(work_order_id text, notes text)
returns void language sql security invoker set search_path = ''
as $$ select app.update_admin_notes(work_order_id, notes); $$;

revoke execute on function
  public.assign_work_order(text, text, timestamptz),
  public.set_work_order_status(text, text),
  public.update_admin_notes(text, text)
from public, anon;
grant execute on function
  public.assign_work_order(text, text, timestamptz),
  public.set_work_order_status(text, text),
  public.update_admin_notes(text, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
