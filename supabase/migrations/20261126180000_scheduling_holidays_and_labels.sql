-- Follow-up to the adviser's consultation (2026-11-26, second brief):
--
--   1. holidays: the dates no work is scheduled on, kept by the
--      administrator in Settings (Philippine holidays move every year, so
--      nothing is fixed here). A scheduling date must be a weekday that
--      is not one of them: app.require_working_day, used by every function
--      that takes one (assign_work_order, reschedule_report, add_task, and
--      the new reschedule_work_order).
--   2. On the report page the first date is a schedule, not a
--      rescheduling: reschedule_report keeps its name and says
--      "scheduled".
--   3. reschedule_work_order and reassign_work_order, from the work
--      order's page, each with a required reason, kept on the work order's
--      and the report's history; the requestor and the personnel concerned
--      (old and new, for a reassignment) are told.
--   4. A review says whether it kept or changed the reporter's damage
--      type, in the report's history.
--   5. The roles' labels: Utility, not Maintenance, in the words the
--      database writes.
--
-- No earlier migration is edited: the functions are replaced here.

-- ================================================================ 1. holidays

create table public.holidays (
  day date primary key,
  name text not null check (char_length(name) between 1 and 120),
  created_at timestamptz not null default now()
);

alter table public.holidays enable row level security;
revoke all on table public.holidays from public, anon, authenticated;
grant select on table public.holidays to authenticated;
grant all on table public.holidays to service_role;

-- Every active account reads them: the console's date pickers.
create policy holidays_select on public.holidays
  for select to authenticated
  using ((select app.is_active()));

alter publication supabase_realtime add table public.holidays;

-- The calendar day [_moment] falls on in the Philippines (UTC+8, no
-- daylight saving): what the person picking a date meant by it.
create or replace function app.local_day(_moment timestamptz)
returns date
language sql
immutable
set search_path = ''
as $$
  select ((_moment at time zone 'UTC') + interval '8 hours')::date;
$$;

-- "Dec 1, 2026", as the app writes a date.
create or replace function app.day_label(_day date)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(_day, 'FMMon FMDD, YYYY');
$$;

create or replace function app.is_working_day(_day date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select extract(isodow from _day) < 6
    and not exists (select 1 from public.holidays h where h.day = _day);
$$;

-- Refuses a scheduling date on a Saturday, a Sunday or a holiday. A null
-- date (none chosen) passes.
create or replace function app.require_working_day(_moment timestamptz)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  picked date := app.local_day(_moment);
  holiday text;
begin
  if _moment is null then
    return;
  end if;
  if extract(isodow from picked) >= 6 then
    perform app.refuse('PT422', app.day_label(picked) || ' is a '
      || case when extract(isodow from picked) = 6 then 'Saturday' else 'Sunday' end
      || '. Choose a weekday that is not a holiday.');
  end if;
  select h.name into holiday from public.holidays h where h.day = picked;
  if holiday is not null then
    perform app.refuse('PT422', app.day_label(picked) || ' is a holiday (' || holiday
      || '). Choose a weekday that is not a holiday.');
  end if;
end;
$$;

create or replace function app.add_holiday(_day date, _name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_name text := regexp_replace(btrim(coalesce(_name, '')), '\s+', ' ', 'g');
  existing text;
begin
  perform app.require_admin();
  if _day is null then
    perform app.refuse('PT422', 'Choose the date of the holiday.');
  end if;
  if clean_name = '' then
    perform app.refuse('PT422', 'Name the holiday.');
  end if;
  if char_length(clean_name) > 120 then
    perform app.refuse('PT422', 'Keep the name to 120 characters or fewer.');
  end if;
  select h.name into existing from public.holidays h where h.day = _day;
  if existing is not null then
    perform app.refuse('PT409', app.day_label(_day) || ' is already a holiday (' || existing || ').');
  end if;
  insert into public.holidays (day, name) values (_day, clean_name);
  perform app.audit('created', 'holidays', _day::text,
    'Added the holiday ' || clean_name || ' on ' || app.day_label(_day));
end;
$$;

create or replace function app.remove_holiday(_day date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing text;
begin
  perform app.require_admin();
  select h.name into existing from public.holidays h where h.day = _day;
  if existing is null then
    return;
  end if;
  delete from public.holidays h where h.day = _day;
  perform app.audit('deleted', 'holidays', _day::text,
    'Removed the holiday ' || existing || ' on ' || app.day_label(_day));
end;
$$;

-- ================================================================ 2. schedule, on the report page

-- As 20261126101500's, and: the date is a working day; it is a schedule
-- ("scheduled for"), the report's first date, not a rescheduling.
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
    perform app.refuse('PT422', 'Choose the date the work is scheduled for.');
  end if;
  if _rescheduled_to < now() - interval '1 day' then
    perform app.refuse('PT422', 'Choose today or a later date.');
  end if;
  perform app.require_working_day(_rescheduled_to);

  select * into stored from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if stored.status <> 'approved' or stored.work_order_id is not null then
    perform app.refuse('PT409', 'Only an approved report that is not assigned yet can be '
      || 'scheduled here. This one is ' || app.report_status_label(stored.status)
      || case when stored.work_order_id is not null
           then '; reschedule it from its work order.' else '.' end);
  end if;

  update public.damage_reports r
  set rescheduled_to = _rescheduled_to,
      reschedule_reason = reason,
      updated_at = now()
  where r.id = _report_id;

  insert into public.report_status_history (report_id, status, changed_by, note, rescheduled_to)
  values (_report_id, stored.status, (select app.uid()), reason, _rescheduled_to);

  shown_date := app.day_label(app.local_day(_rescheduled_to));
  perform app.notify(stored.reporter_id, 'statusUpdate', 'Report scheduled',
    left('The work on your report "' || stored.title || '" is scheduled for '
      || shown_date || ': ' || reason, 1000),
    'damage_reports', _report_id);
  perform app.audit('updated', 'damage_reports', _report_id,
    'Scheduled for ' || shown_date || ': ' || reason,
    jsonb_build_object('rescheduledTo', jsonb_build_object(
        'from', stored.rescheduled_to, 'to', _rescheduled_to),
      'reason', reason));
end;
$$;

-- ================================================================ 3. from the work order: reschedule, reassign

-- A new target date for open work, with the reason. The report keeps its
-- status; the date and the reason go on its timeline, to its requestor,
-- and to whoever holds the work.
create or replace function app.reschedule_work_order(
  _work_order_id text,
  _scheduled_for timestamptz,
  _reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  reason text := btrim(coalesce(_reason, ''));
  shown_date text;
  linked record;
  holder text;
begin
  perform app.require_admin();
  if reason = '' then
    perform app.refuse('PT422', 'Give the reason for rescheduling.');
  end if;
  if char_length(reason) > 500 then
    perform app.refuse('PT422', 'Keep the reason to 500 characters or fewer.');
  end if;
  if _scheduled_for is null then
    perform app.refuse('PT422', 'Choose the new date.');
  end if;
  if _scheduled_for < now() - interval '1 day' then
    perform app.refuse('PT422', 'Choose today or a later date.');
  end if;
  perform app.require_working_day(_scheduled_for);

  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  if work_order.status not in ('pending', 'inProgress') or work_order.archived_at is not null then
    perform app.refuse('PT409', 'This work order is ' || app.work_order_status_title(work_order.status)
      || '. Only work that is pending or in progress can be rescheduled.');
  end if;

  update public.work_orders w
  set scheduled_for = _scheduled_for, updated_at = now()
  where w.id = _work_order_id;

  shown_date := app.day_label(app.local_day(_scheduled_for));
  for linked in
    select r.id, r.status, r.reporter_id, r.title from public.damage_reports r
    where r.id = any (work_order.report_ids)
    order by r.id
  loop
    insert into public.report_status_history (report_id, status, changed_by, note, rescheduled_to)
    values (linked.id, linked.status, (select app.uid()), reason, _scheduled_for);
    perform app.notify(linked.reporter_id, 'statusUpdate', 'Work rescheduled',
      left('The work on your report "' || linked.title || '" is rescheduled to '
        || shown_date || ': ' || reason, 1000),
      'damage_reports', linked.id);
  end loop;

  foreach holder in array work_order.assigned_personnel_ids loop
    perform app.notify(holder, 'statusUpdate', 'Work rescheduled',
      left(app.display_id(_work_order_id, 'WO') || ' ("' || work_order.title
        || '") is rescheduled to ' || shown_date || ': ' || reason, 1000),
      'work_orders', _work_order_id);
  end loop;

  perform app.audit('updated', 'work_orders', _work_order_id,
    'Rescheduled to ' || shown_date || ': ' || reason,
    jsonb_build_object('scheduledFor', jsonb_build_object(
        'from', work_order.scheduled_for, 'to', _scheduled_for),
      'reason', reason));
end;
$$;

-- As 20261020111843's, and: a reason is required, kept on the work
-- order's and the report's history and given to everyone told.
drop function public.reassign_work_order(text, text);
drop function app.reassign_work_order(text, text);

create or replace function app.reassign_work_order(
  _work_order_id text,
  _personnel_id text,
  _reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  person public.users;
  reason text := btrim(coalesce(_reason, ''));
  previous text[];
  former text;
  linked record;
  former_names text;
begin
  perform app.require_admin();
  if reason = '' then
    perform app.refuse('PT422', 'Give the reason for reassigning.');
  end if;
  if char_length(reason) > 500 then
    perform app.refuse('PT422', 'Keep the reason to 500 characters or fewer.');
  end if;

  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  select * into person from public.users u where u.id = _personnel_id for update;
  if not found then
    perform app.refuse('PT404', 'No user ' || _personnel_id);
  end if;

  if work_order.status not in ('pending', 'inProgress') then
    perform app.refuse('PT409', 'This work order is ' || app.work_order_status_title(work_order.status)
      || '. Only work that is pending or in progress can be reassigned.');
  end if;
  if person.role <> 'maintenancePersonnel' then
    perform app.refuse('PT409', person.full_name || ' is not utility personnel.');
  end if;
  if person.account_status <> 'active' then
    perform app.refuse('PT409', person.full_name || '''s account is inactive and cannot take work.');
  end if;

  previous := work_order.assigned_personnel_ids;
  if previous = array[_personnel_id] then
    perform app.refuse('PT409', person.full_name || ' already has this work order.');
  end if;

  select string_agg(u.full_name, ', ' order by u.full_name) into former_names
  from public.users u
  where u.id = any (previous);

  update public.users u
  set active_task_count = greatest(u.active_task_count - 1, 0), updated_at = now()
  where u.id = any (previous) and u.id <> _personnel_id;
  if not (_personnel_id = any (previous)) then
    update public.users u
    set active_task_count = u.active_task_count + 1, updated_at = now()
    where u.id = _personnel_id;
  end if;

  update public.work_orders w
  set assigned_personnel_ids = array[_personnel_id], updated_at = now()
  where w.id = _work_order_id;

  update public.tasks t
  set assigned_to = _personnel_id, updated_at = now()
  where t.work_order_id = _work_order_id
    and t.status <> 'completed'
    and t.assigned_to <> _personnel_id;

  for linked in
    select r.id, r.status, r.reporter_id, r.title from public.damage_reports r
    where r.id = any (work_order.report_ids)
    order by r.id
  loop
    -- The reason is the note; who now has the work is the entry's
    -- personnel, as an assignment names them.
    insert into public.report_status_history
      (report_id, status, changed_by, note, personnel_name, personnel_specialization)
    values (linked.id, linked.status, (select app.uid()), reason,
      person.full_name, person.specialization);
    perform app.notify(linked.reporter_id, 'statusUpdate', 'New technician assigned',
      left('Your report "' || linked.title || '" is now with ' || person.full_name
        || ': ' || reason, 1000),
      'damage_reports', linked.id);
  end loop;

  perform app.notify(_personnel_id, 'workOrderAssigned', 'New work order',
    left('You have been assigned "' || work_order.title || '"'
      || coalesce(' at ' || work_order.facility_name, '') || '. Reason: ' || reason, 1000),
    'work_orders', _work_order_id);
  foreach former in array previous loop
    if former <> _personnel_id then
      perform app.notify(former, 'statusUpdate', 'Work reassigned',
        left(app.display_id(_work_order_id, 'WO') || ' ("' || work_order.title
          || '") was reassigned to ' || person.full_name || '. It is off your list. Reason: '
          || reason, 1000),
        'work_orders', _work_order_id);
    end if;
  end loop;

  perform app.audit('assigned', 'work_orders', _work_order_id,
    'Reassigned to ' || person.full_name || coalesce(' (was ' || former_names || ')', '')
      || ': ' || reason,
    jsonb_build_object('from', to_jsonb(previous), 'to', jsonb_build_array(_personnel_id),
      'reason', reason));
end;
$$;

-- As 20261016145458's, and: a target date is a working day; Utility in
-- its refusal.
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
  perform app.require_working_day(_scheduled_for);

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
    perform app.refuse('PT409', person.full_name || ' is not utility personnel.');
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

  insert into public.tasks (work_order_id, title, description, assigned_to, status, due_date)
  values (new_work_order_id, report.title, coalesce(report.location_description, report.facility_name),
    _personnel_id, 'pending', coalesce(_scheduled_for, now()));

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

-- As 20261017065945's, and: a due date is a working day.
create or replace function app.add_task(
  _work_order_id text,
  _title text,
  _description text default null,
  _due_date timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  clean_title text := btrim(coalesce(_title, ''));
  details text := app.blank_to_null(_description);
  assignee text;
  new_task_id text := app.new_id();
begin
  perform app.require_admin();
  if clean_title = '' then
    perform app.refuse('PT422', 'Give the task a title.');
  end if;
  if char_length(clean_title) > 120 then
    perform app.refuse('PT422', 'Keep the title to 120 characters.');
  end if;
  if char_length(details) > 500 then
    perform app.refuse('PT422', 'Keep the description to 500 characters.');
  end if;
  perform app.require_working_day(_due_date);

  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  if work_order.status not in ('pending', 'inProgress') then
    perform app.refuse('PT409', 'This work order is ' || app.work_order_status_title(work_order.status)
      || ', so no task can be added to it.');
  end if;
  if cardinality(work_order.assigned_personnel_ids) = 0 then
    perform app.refuse('PT409', 'Nobody is assigned to this work order yet.');
  end if;
  assignee := work_order.assigned_personnel_ids[1];

  insert into public.tasks (id, work_order_id, title, description, assigned_to, status, due_date)
  values (new_task_id, _work_order_id, clean_title, details, assignee, 'pending', _due_date);

  perform app.notify(assignee, 'taskAssigned', 'New task',
    '"' || clean_title || '" was added to "' || work_order.title || '".',
    'work_orders', _work_order_id);
  perform app.audit('created', 'tasks', new_task_id,
    'Task "' || clean_title || '" added to ' || app.display_id(_work_order_id, 'WO'),
    jsonb_build_object('workOrderId', _work_order_id, 'assignedTo', assignee)
      || case when _due_date is not null
           then jsonb_build_object('dueDate',
             to_char(_due_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
           else '{}' end);
  return new_task_id;
end;
$$;

-- ================================================================ 4. the reporter's damage type, in the history

-- As 20261116115436's, and: the entry says whether the damage type kept
-- the reporter's choice or changed it ("reporterCategoryKept").
create or replace function app.record_assessment(
  _report_id text,
  _category text,
  _classified_automatically boolean,
  _severity_rating integer,
  _safety_risk_rating integer,
  _frequency_rating integer,
  _location_importance_rating integer,
  _priority_score double precision,
  _recommended_priority text,
  _official_priority text,
  _reason text default null,
  _expected_updated_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.damage_reports;
  score text := to_char(_priority_score, 'FM990.00');
  reason text := nullif(btrim(coalesce(_reason, '')), '');
  priority text;
  damage_type text;
  changer_id text;
  changer_name text;
begin
  perform app.require_admin();
  if least(_severity_rating, _safety_risk_rating, _frequency_rating, _location_importance_rating) < 1
     or greatest(_severity_rating, _safety_risk_rating, _frequency_rating, _location_importance_rating) > 4 then
    perform app.refuse('PT422', 'Each rating must be from 1 to 4.');
  end if;
  if _priority_score < 1 or _priority_score > 4 then
    perform app.refuse('PT422', 'The priority score must be between 1.00 and 4.00.');
  end if;
  if char_length(reason) > 500 then
    perform app.refuse('PT422', 'Keep the reason to 500 characters.');
  end if;

  select * into stored from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if stored.duplicate_of is not null then
    perform app.refuse('PT409', 'This report was merged into another. Assess that report instead.');
  end if;
  if stored.work_order_id is not null or stored.status not in ('submitted', 'underReview', 'approved') then
    perform app.refuse('PT409', 'This report is ' || app.report_status_label(stored.status)
      || '. Its damage type and priority are set before a work order is raised, and cannot change now.');
  end if;

  if stored.official_priority is not distinct from _official_priority
     and stored.category is not distinct from _category
     and stored.classified_automatically is not distinct from _classified_automatically
     and stored.severity_rating is not distinct from _severity_rating
     and stored.safety_risk_rating is not distinct from _safety_risk_rating
     and stored.frequency_rating is not distinct from _frequency_rating
     and stored.location_importance_rating is not distinct from _location_importance_rating
     and stored.recommended_priority is not distinct from _recommended_priority
     and stored.priority_score is not distinct from _priority_score
     and reason is null then
    return;
  end if;

  if _expected_updated_at is not null
     and stored.updated_at > _expected_updated_at + interval '1 millisecond' then
    select a.actor_id, a.actor_name into changer_id, changer_name
      from public.audit_logs a
      where a.entity_type = 'damage_reports' and a.entity_id = _report_id
        and a."timestamp" > _expected_updated_at + interval '1 millisecond'
      order by a."timestamp" desc
      limit 1;
    perform app.refuse('PT409',
      case
        when changer_id is null then 'This report was changed'
        when changer_id = (select app.uid()) then 'You changed this report somewhere else'
        else changer_name || ' changed this report'
      end || ' after you opened it here. The latest details are shown now: check them, then save again.');
  end if;

  update public.damage_reports r
  set category = _category,
      classified_automatically = _classified_automatically,
      severity_rating = _severity_rating,
      safety_risk_rating = _safety_risk_rating,
      frequency_rating = _frequency_rating,
      location_importance_rating = _location_importance_rating,
      priority_score = _priority_score,
      recommended_priority = _recommended_priority,
      official_priority = _official_priority,
      reviewed_by = (select app.uid()),
      reviewed_at = now(),
      updated_at = now()
  where r.id = _report_id;

  priority := case
    when _official_priority = _recommended_priority then
      'official priority ' || upper(_official_priority) || ' as recommended (score ' || score || ')'
    else
      'official priority ' || upper(_official_priority) || ', '
        || case when app.priority_rank(_official_priority) > app.priority_rank(_recommended_priority)
             then 'raised' else 'lowered' end
        || ' from the recommended ' || upper(_recommended_priority) || ' (score ' || score || ')'
  end;

  -- The damage type against what the reporter chose on the phone.
  damage_type := case
    when stored.requestor_category is null then
      'Classified as ' || app.category_label(_category) || ' (the reporter chose no type)'
    when stored.requestor_category = _category then
      'Classified as ' || app.category_label(_category) || ', the reporter''s choice'
    else
      'Classified as ' || app.category_label(_category) || ', changed from the reporter''s '
        || app.category_label(stored.requestor_category)
  end;

  perform app.audit('updated', 'damage_reports', _report_id,
    damage_type || '; ' || priority || coalesce('. Reason: ' || reason, ''),
    jsonb_build_object(
      'requestor', jsonb_build_object(
        'category', stored.requestor_category,
        'priority', stored.requestor_priority
      ),
      'category', jsonb_build_object('from', stored.category, 'to', _category),
      'reporterCategoryKept', stored.requestor_category is not distinct from _category,
      'classifiedAutomatically', _classified_automatically,
      'ratings', jsonb_build_object(
        'severity', _severity_rating,
        'safetyRisk', _safety_risk_rating,
        'frequency', _frequency_rating,
        'locationImportance', _location_importance_rating
      ),
      'priorityScore', _priority_score,
      'recommendedPriority', _recommended_priority,
      'officialPriority', jsonb_build_object('from', stored.official_priority, 'to', _official_priority),
      'firstReview', stored.official_priority is null
    ) || case when reason is null then '{}'::jsonb else jsonb_build_object('reason', reason) end);
end;
$$;

-- ================================================================ 5. Utility, in the requestor's notices

-- As 20261016145419's, with "utility personnel".
create or replace function app.report_notice(
  _to text,
  _report_title text,
  _from text default null,
  _personnel_name text default null,
  _reason text default null,
  _merged_into text default null,
  out type text,
  out title text,
  out body text
)
language plpgsql
immutable
set search_path = ''
as $$
declare
  report text := '"' || _report_title || '"';
  reason text := btrim(coalesce(_reason, ''));
begin
  if char_length(reason) > 280 then
    reason := rtrim(left(reason, 280), ' ' || chr(9) || chr(10) || chr(13)) || '…';
  end if;
  case _to
    when 'submitted' then
      type := 'reportAcknowledged';
      title := 'Report received';
      body := 'The General Services Unit received your report ' || report
        || '. You will be notified as it moves along.';
    when 'approved' then
      type := 'statusUpdate';
      title := 'Report approved';
      body := 'Your report ' || report
        || ' was approved and will be assigned to utility personnel.';
    when 'assigned' then
      type := 'workOrderAssigned';
      title := 'Personnel assigned';
      body := case
        when _personnel_name is null
          then 'Utility personnel were assigned to your report ' || report || '.'
        else _personnel_name || ' was assigned to your report ' || report || '.'
      end;
    when 'inProgress' then
      type := 'statusUpdate';
      if _from = 'forReview' then
        title := 'Work resumed';
        body := 'Work on your report ' || report || ' has resumed.';
      else
        title := 'Work started';
        body := 'Work has started on your report ' || report || '.';
      end if;
    when 'completed' then
      type := 'maintenanceCompleted';
      title := 'Work completed';
      body := 'The work on your report ' || report
        || ' is complete. Open it to rate the service.';
    when 'rejected' then
      type := 'statusUpdate';
      title := 'Report not accepted';
      body := case
        when reason = '' then 'Your report ' || report || ' was not accepted.'
        else 'Your report ' || report || ' was not accepted: ' || reason
      end;
    when 'merged' then
      type := 'statusUpdate';
      title := 'Report merged';
      body := case
        when _merged_into is null
          then 'Your report ' || report || ' was merged with an earlier report of the same damage.'
        else 'Your report ' || report || ' was merged with report '
          || app.display_id(_merged_into, 'DR') || ', which reported the same damage.'
      end;
    else
      type := null;
  end case;
end;
$$;

-- ================================================================ the API

create or replace function public.add_holiday(day date, name text)
returns void language sql security invoker set search_path = ''
as $$ select app.add_holiday(day, name); $$;

create or replace function public.remove_holiday(day date)
returns void language sql security invoker set search_path = ''
as $$ select app.remove_holiday(day); $$;

create or replace function public.reschedule_work_order(
  work_order_id text, scheduled_for timestamptz, reason text
)
returns void language sql security invoker set search_path = ''
as $$ select app.reschedule_work_order(work_order_id, scheduled_for, reason); $$;

create or replace function public.reassign_work_order(
  work_order_id text, personnel_id text, reason text default null
)
returns void language sql security invoker set search_path = ''
as $$ select app.reassign_work_order(work_order_id, personnel_id, reason); $$;

revoke execute on function
  public.add_holiday(date, text),
  public.remove_holiday(date),
  public.reschedule_work_order(text, timestamptz, text),
  public.reassign_work_order(text, text, text)
from public, anon;
grant execute on function
  public.add_holiday(date, text),
  public.remove_holiday(date),
  public.reschedule_work_order(text, timestamptz, text),
  public.reassign_work_order(text, text, text)
to authenticated, service_role;

-- The new implementations, to signed-in callers only (each checks who is
-- asking). Not a blanket grant over the schema: that would reopen the
-- scheduler-only sweeps earlier migrations closed.
revoke execute on all functions in schema app from public, anon;
grant execute on function
  app.local_day(timestamptz),
  app.day_label(date),
  app.is_working_day(date),
  app.require_working_day(timestamptz),
  app.add_holiday(date, text),
  app.remove_holiday(date),
  app.reschedule_work_order(text, timestamptz, text),
  app.reassign_work_order(text, text, text)
to authenticated, service_role;
