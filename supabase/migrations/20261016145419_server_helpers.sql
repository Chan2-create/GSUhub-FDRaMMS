-- What every server function shares (Objective 1, M3): the words the
-- server writes, the lifecycle rules it enforces, and the three records a
-- change leaves behind — an audit entry, a timeline entry, a notification.
--
-- The labels and transition tables mirror the Dart enums in lib/core/enums
-- (ReportStatus, WorkOrderStatus, PriorityLevel, UserRole) and
-- lib/core/constants/damage_categories.dart. The notice wording mirrors
-- ReportNotice and PersonnelNotice in lib/features/notifications. Change
-- one, change the other: the app shows these strings as the server writes
-- them.
--
-- Refusals raise SQLSTATE PTxxx, which the API returns as HTTP status xxx
-- and the app maps by code (lib/core/errors/supabase_error_mapper.dart):
--   PT403  not allowed          → PermissionFailure
--   PT404  no such record       → NotFoundFailure
--   PT409  the data says no     → ValidationFailure, message shown as is
--   PT422  the request is wrong → ValidationFailure, message shown as is

-- ------------------------------------------------------------ refusals

-- Volatile, not immutable: an immutable call with constant arguments may
-- be evaluated while the statement is planned, raising for a branch never
-- taken.
create or replace function app.refuse(code text, message text)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception using errcode = code, message = message;
end;
$$;

create or replace function app.require_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select app.is_admin()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
end;
$$;

create or replace function app.require_active()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select app.is_active()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
end;
$$;

-- ------------------------------------------------------------ labels

create or replace function app.report_status_label(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'submitted' then 'PENDING'
    when 'underReview' then 'UNDER REVIEW'
    when 'approved' then 'APPROVED'
    when 'assigned' then 'ASSIGNED'
    when 'inProgress' then 'IN PROGRESS'
    when 'forReview' then 'FOR REVIEW'
    when 'completed' then 'COMPLETED'
    when 'closed' then 'CLOSED'
    when 'merged' then 'MERGED'
    when 'rejected' then 'REJECTED'
    when 'archived' then 'ARCHIVED'
    else status
  end;
$$;

create or replace function app.report_timeline_label(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'submitted' then 'Report received'
    when 'underReview' then 'Under review'
    when 'approved' then 'Approved'
    when 'assigned' then 'Personnel assigned'
    when 'inProgress' then 'Work started'
    when 'forReview' then 'Work done, being checked'
    when 'completed' then 'Completed'
    when 'closed' then 'Closed'
    when 'merged' then 'Merged with an existing report'
    when 'rejected' then 'Not accepted'
    when 'archived' then 'Archived'
    else status
  end;
$$;

create or replace function app.work_order_status_title(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'pending' then 'Pending'
    when 'inProgress' then 'In Progress'
    when 'forReview' then 'For Review'
    when 'completed' then 'Completed'
    else status
  end;
$$;

create or replace function app.category_label(category text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case category
    when 'electrical' then 'Electrical'
    when 'plumbing' then 'Plumbing'
    when 'structural' then 'Structural'
    when 'carpentry' then 'Carpentry'
    when 'airConditioning' then 'Air Conditioning'
    when 'cleaningAndSanitation' then 'Cleaning and Sanitation'
    when 'generalMaintenance' then 'General Maintenance'
    else category
  end;
$$;

create or replace function app.priority_rank(priority text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case priority
    when 'low' then 0 when 'medium' then 1 when 'high' then 2 when 'critical' then 3
  end;
$$;

create or replace function app.role_label(role text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'requestor' then 'End User'
    when 'maintenancePersonnel' then 'Maintenance'
    when 'admin' then 'Administrator'
    else role
  end;
$$;

-- DisplayId: '#DR-ABC123' for a generated id, '#SEED-REPORT-0001' for a
-- seeded one that already reads well.
create or replace function app.display_id(id text, prefix text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when position('-' in id) > 0 then '#' || upper(id)
    else '#' || prefix || '-' || upper(left(id, 6))
  end;
$$;

-- ------------------------------------------------------------ lifecycles

create or replace function app.report_can_move(from_status text, to_status text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (from_status, to_status) in (
    ('submitted', 'underReview'), ('submitted', 'merged'),
    ('underReview', 'approved'), ('underReview', 'merged'),
    ('underReview', 'rejected'), ('underReview', 'archived'),
    ('approved', 'assigned'),
    ('assigned', 'inProgress'),
    ('inProgress', 'forReview'),
    ('forReview', 'completed'), ('forReview', 'inProgress'),
    ('completed', 'closed')
  );
$$;

create or replace function app.report_is_open(status text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select status in ('submitted', 'underReview', 'approved', 'assigned', 'inProgress', 'forReview');
$$;

create or replace function app.work_order_can_move(from_status text, to_status text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (from_status, to_status) in (
    ('pending', 'inProgress'),
    ('inProgress', 'forReview'),
    ('forReview', 'completed'), ('forReview', 'inProgress')
  );
$$;

-- A work order's reports move with it; the two lifecycles share their
-- later stages.
create or replace function app.report_status_for(work_order_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case work_order_status
    when 'pending' then 'assigned'
    when 'inProgress' then 'inProgress'
    when 'forReview' then 'forReview'
    when 'completed' then 'completed'
  end;
$$;

-- ------------------------------------------------------------ the records a change leaves

-- An audit entry for the caller. Their name comes from their account, not
-- from the request.
create or replace function app.audit(
  _action text,
  _entity_type text,
  _entity_id text,
  _description text,
  _changes jsonb default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (actor_id, actor_name, action, entity_type, entity_id, description, changes)
  select
    (select app.uid()),
    coalesce((select u.full_name from public.users u where u.id = (select app.uid())), (select app.uid())),
    _action, _entity_type, _entity_id, _description, _changes;
$$;

create or replace function app.notify(
  _recipient_id text,
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
  values (_recipient_id, _type, _title, _body, _entity_type, _entity_id);
$$;

-- ReportNotice.forMove: what a requestor is told when their report moves,
-- or a null type when they are not told.
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
        || ' was approved and will be assigned to maintenance personnel.';
    when 'assigned' then
      type := 'workOrderAssigned';
      title := 'Personnel assigned';
      body := case
        when _personnel_name is null
          then 'Maintenance personnel were assigned to your report ' || report || '.'
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

-- Everything a report's move writes beside the report itself: its
-- timeline entry and, for the moves the requestor hears about, their
-- notification (status_history_writes.dart). [_personnel_id] names who was
-- assigned; [_note] is a rejection's reason; [_merged_into] the report a
-- duplicate was folded into.
create or replace function app.record_report_move(
  _report_id text,
  _to text,
  _from text default null,
  _note text default null,
  _personnel_id text default null,
  _merged_into text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  reporter text;
  report_title text;
  personnel_name text;
  personnel_specialization text;
  notice record;
begin
  select r.reporter_id, r.title into reporter, report_title
  from public.damage_reports r
  where r.id = _report_id;

  if _personnel_id is not null then
    select u.full_name, u.specialization into personnel_name, personnel_specialization
    from public.users u
    where u.id = _personnel_id;
  end if;

  insert into public.report_status_history (report_id, status, changed_by, note, personnel_name, personnel_specialization)
  values (_report_id, _to, (select app.uid()), _note, personnel_name, personnel_specialization);

  select * into notice
  from app.report_notice(_to, report_title, _from, personnel_name, _note, _merged_into);
  if notice.type is not null then
    perform app.notify(reporter, notice.type, notice.title, notice.body, 'damage_reports', _report_id);
  end if;
end;
$$;

-- A work order's move to another status, with every report it carries
-- moving beside it (work_order_moves.dart). The caller has checked who may
-- make it. Checked against the stored statuses, all before any write:
-- moving the work order without its reports, or the other way round,
-- would leave them disagreeing about where the job is.
create or replace function app.move_work_order(_work_order_id text, _to text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  target text := app.report_status_for(_to);
  linked record;
begin
  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  if work_order.status = _to then
    return;
  end if;
  if not app.work_order_can_move(work_order.status, _to) then
    perform app.refuse('PT409', 'A work order cannot move from '
      || app.work_order_status_title(work_order.status) || ' to '
      || app.work_order_status_title(_to) || '.');
  end if;

  for linked in
    select r.id, r.status from public.damage_reports r
    where r.id = any (work_order.report_ids)
    order by r.id
    for update
  loop
    if linked.status <> target and not app.report_can_move(linked.status, target) then
      perform app.refuse('PT409', 'Report ' || linked.id || ' is '
        || app.report_status_label(linked.status) || ' and cannot move to '
        || app.report_status_label(target) || ' with this work order.');
    end if;
  end loop;

  update public.work_orders w
  set status = _to,
      updated_at = now(),
      started_at = case when _to = 'inProgress' and w.started_at is null then now() else w.started_at end,
      completed_at = case when _to = 'completed' then now() else w.completed_at end
  where w.id = _work_order_id;

  for linked in
    select r.id, r.status from public.damage_reports r
    where r.id = any (work_order.report_ids) and r.status <> target
    order by r.id
  loop
    update public.damage_reports set status = target, updated_at = now() where id = linked.id;
    perform app.record_report_move(linked.id, target, linked.status);
  end loop;

  -- Completed is terminal, so the job stops counting against whoever did
  -- it. Never below zero.
  if _to = 'completed' then
    update public.users u
    set active_task_count = greatest(u.active_task_count - 1, 0), updated_at = now()
    where u.id = any (work_order.assigned_personnel_ids);
  end if;

  perform app.audit('statusChanged', 'work_orders', _work_order_id,
    'Status changed from ' || app.work_order_status_title(work_order.status)
      || ' to ' || app.work_order_status_title(_to),
    jsonb_build_object('from', work_order.status, 'to', _to));
end;
$$;

-- What already carries a printed code, as "a material", "a tool", "a room"
-- or "equipment", or null. [_except_id] is the record being edited, which
-- may keep its own code. One scanner reads them all (§3.4).
create or replace function app.qr_code_owner(_code text, _except_id text default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select owner from (
    select 1 as rank, 'a material' as owner from public.inventory_items i
      where i.qr_code = _code and i.id is distinct from _except_id
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

-- ------------------------------------------------------------ privileges
-- The app schema is not exposed through the API: these run only when a
-- public function calls them, so authenticated needs EXECUTE for that and
-- nothing more. Nobody signed out runs any of them.

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
