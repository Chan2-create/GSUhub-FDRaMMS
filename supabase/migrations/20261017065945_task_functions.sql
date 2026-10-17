-- Tasks (Objective 1, M4): TaskRepositoryImpl's transactions and the tasks
-- rules in firebase/firestore.rules. Starts with the helpers the rest of
-- M4 shares.

-- ------------------------------------------------------------ shared by M4

-- A refusal always says something. A message built from a missing value
-- ('No tool loan ' || null) is null, and RAISE rejects a null message with
-- an error of its own that the app could not word.
create or replace function app.refuse(code text, message text)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception using
    errcode = coalesce(code, 'PT422'),
    message = coalesce(message, 'That could not be done. Check the details and try again.');
end;
$$;

-- The Dart enums' labels (lib/core/enums): change one, change the other.
create or replace function app.task_status_label(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'pending' then 'To do'
    when 'inProgress' then 'In progress'
    when 'completed' then 'Done'
    else status
  end;
$$;

create or replace function app.tool_status_label(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'available' then 'Available'
    when 'borrowed' then 'Borrowed'
    when 'inRepair' then 'In repair'
    when 'retired' then 'Retired'
    else status
  end;
$$;

create or replace function app.condition_label(condition text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case condition
    when 'excellent' then 'Excellent'
    when 'good' then 'Good'
    when 'fair' then 'Fair'
    when 'poor' then 'Poor'
    else condition
  end;
$$;

create or replace function app.request_status_label(status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case status
    when 'pending' then 'Pending'
    when 'approved' then 'Approved'
    when 'declined' then 'Declined'
    else status
  end;
$$;

-- QuantityFormat.amount: 2, not 2.0; 1.5 as it is.
create or replace function app.format_amount(quantity double precision)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when quantity = trunc(quantity) then trunc(quantity)::bigint::text else quantity::text end;
$$;

-- The caller is an active technician assigned to [work_order].
create or replace function app.is_assigned(work_order public.work_orders)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select app.is_personnel()) and (select app.uid()) = any (work_order.assigned_personnel_ids);
$$;

-- ------------------------------------------------------------ tasks

-- An administrator adds a task to open work (5.A), assigned to the work
-- order's technician, who is told.
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

  -- PersonnelNotice.taskAssigned
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

-- A task removed by an administrator. One that is done stays on the
-- record.
create or replace function app.delete_task(_task_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  task public.tasks;
begin
  perform app.require_admin();
  select * into task from public.tasks t where t.id = _task_id for update;
  if not found then
    perform app.refuse('PT404', 'No task ' || _task_id);
  end if;
  if task.status = 'completed' then
    perform app.refuse('PT409', 'A task that is done stays on the record.');
  end if;

  delete from public.tasks t where t.id = _task_id;
  perform app.audit('deleted', 'tasks', _task_id,
    'Task "' || task.title || '" removed from ' || app.display_id(task.work_order_id, 'WO'),
    jsonb_build_object('workOrderId', task.work_order_id));
end;
$$;

-- The task's technician, or an administrator, works through it. Tasks
-- change only while the work is open; the first one touched starts the
-- work order, its reports and the requestor's timeline with it.
create or replace function app.task_for_change(_task_id text)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  task public.tasks;
  work_order public.work_orders;
begin
  select * into task from public.tasks t where t.id = _task_id for update;
  if not found then
    perform app.refuse('PT404', 'No task ' || _task_id);
  end if;
  if not (select app.is_admin())
     and not ((select app.is_personnel()) and task.assigned_to = (select app.uid())) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;
  select * into work_order from public.work_orders w where w.id = task.work_order_id;
  if not found then
    perform app.refuse('PT404', 'No work order ' || task.work_order_id);
  end if;
  if work_order.status not in ('pending', 'inProgress') then
    perform app.refuse('PT409', 'This work order is ' || app.work_order_status_title(work_order.status)
      || ', so its tasks can no longer change.');
  end if;
  return task;
end;
$$;

create or replace function app.set_task_status(_task_id text, _status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  task public.tasks := app.task_for_change(_task_id);
begin
  if task.status = _status then
    return;
  end if;
  if _status <> 'pending'
     and (select w.status from public.work_orders w where w.id = task.work_order_id) = 'pending' then
    perform app.move_work_order(task.work_order_id, 'inProgress');
  end if;

  update public.tasks t
  set status = _status,
      completed_at = case when _status = 'completed' then now() end,
      updated_at = now()
  where t.id = _task_id;

  perform app.audit('statusChanged', 'tasks', _task_id,
    'Task "' || task.title || '" changed from ' || app.task_status_label(task.status)
      || ' to ' || app.task_status_label(_status),
    jsonb_build_object('from', task.status, 'to', _status, 'workOrderId', task.work_order_id));
end;
$$;

-- Proof of work (Figure 24). Proof on a task not yet begun means it is
-- under way.
create or replace function app.add_proof_photos(_task_id text, _photo_urls text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  task public.tasks;
  begins boolean;
begin
  if cardinality(coalesce(_photo_urls, '{}')) = 0 then
    perform app.refuse('PT422', 'Add a photo first.');
  end if;
  task := app.task_for_change(_task_id);
  begins := task.status = 'pending';
  if begins and (select w.status from public.work_orders w where w.id = task.work_order_id) = 'pending' then
    perform app.move_work_order(task.work_order_id, 'inProgress');
  end if;

  update public.tasks t
  set proof_photo_urls = t.proof_photo_urls
        || array(
             select x.u from unnest(_photo_urls) with ordinality x (u, n)
             where not x.u = any (t.proof_photo_urls)
             group by x.u order by min(x.n)
           ),
      status = case when begins then 'inProgress' else t.status end,
      updated_at = now()
  where t.id = _task_id;
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.add_task(
  work_order_id text, title text, description text default null, due_date timestamptz default null
)
returns text language sql security invoker set search_path = ''
as $$ select app.add_task(work_order_id, title, description, due_date); $$;

create or replace function public.delete_task(task_id text)
returns void language sql security invoker set search_path = ''
as $$ select app.delete_task(task_id); $$;

create or replace function public.set_task_status(task_id text, status text)
returns void language sql security invoker set search_path = ''
as $$ select app.set_task_status(task_id, status); $$;

create or replace function public.add_proof_photos(task_id text, photo_urls text[])
returns void language sql security invoker set search_path = ''
as $$ select app.add_proof_photos(task_id, photo_urls); $$;

revoke execute on function
  public.add_task(text, text, text, timestamptz),
  public.delete_task(text),
  public.set_task_status(text, text),
  public.add_proof_photos(text, text[])
from public, anon;
grant execute on function
  public.add_task(text, text, text, timestamptz),
  public.delete_task(text),
  public.set_task_status(text, text),
  public.add_proof_photos(text, text[])
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
