-- Reassigning a work order (Objective 7.A).
--
-- Manuscript §3.4, Administrator: "Modify report priorities and
-- assignments when necessary". A work order could be assigned once and
-- never moved, so a technician going on leave left their open work with
-- nobody (set_account_status already tells the administrator to "finish
-- or reassign" it). An administrator now hands open work, not yet sent
-- for review, to another active technician:
--
--   * the work order names the new technician alone;
--   * its unfinished tasks follow the work; finished ones keep who did
--     them;
--   * the open-work counts move with it (never below zero);
--   * each linked report's history records the change, with the new
--     technician, so the requestor's page names the right person; the
--     requestor, the new technician and the previous one are told;
--   * one audit entry.

create or replace function app.reassign_work_order(_work_order_id text, _personnel_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  work_order public.work_orders;
  person public.users;
  previous text[];
  former text;
  linked record;
  former_names text;
begin
  perform app.require_admin();

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
    perform app.refuse('PT409', person.full_name || ' is not maintenance personnel.');
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
    insert into public.report_status_history
      (report_id, status, changed_by, note, personnel_name, personnel_specialization)
    values (linked.id, linked.status, (select app.uid()),
      'Reassigned to ' || person.full_name || '.', person.full_name, person.specialization);
    perform app.notify(linked.reporter_id, 'statusUpdate', 'New technician assigned',
      'Your report "' || linked.title || '" is now with ' || person.full_name || '.',
      'damage_reports', linked.id);
  end loop;

  -- PersonnelNotice.workOrderAssigned, as for a new assignment.
  perform app.notify(_personnel_id, 'workOrderAssigned', 'New work order',
    'You have been assigned "' || work_order.title || '"'
      || coalesce(' at ' || work_order.facility_name, '') || '.',
    'work_orders', _work_order_id);
  foreach former in array previous loop
    if former <> _personnel_id then
      perform app.notify(former, 'statusUpdate', 'Work reassigned',
        app.display_id(_work_order_id, 'WO') || ' ("' || work_order.title || '") was reassigned to '
          || person.full_name || '. It is off your list.',
        'work_orders', _work_order_id);
    end if;
  end loop;

  perform app.audit('assigned', 'work_orders', _work_order_id,
    'Reassigned to ' || person.full_name || coalesce(' (was ' || former_names || ')', ''),
    jsonb_build_object('from', to_jsonb(previous), 'to', jsonb_build_array(_personnel_id)));
end;
$$;

create or replace function public.reassign_work_order(work_order_id text, personnel_id text)
returns void language sql security invoker set search_path = ''
as $$ select app.reassign_work_order(work_order_id, personnel_id); $$;

revoke execute on function public.reassign_work_order(text, text) from public, anon;
grant execute on function public.reassign_work_order(text, text) to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
