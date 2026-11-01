-- A task started by its first proof photo is audited (Objective 7.B).
--
-- Adding a proof photo to a task still To do starts it (5.B), but only
-- set_task_status wrote the audit entry for a task's move, so a task
-- started this way showed "Done to To do" and then "In progress to Done"
-- in the trail, with the start missing (seen on live, 2026-10-20).
-- add_proof_photos now records the start as set_task_status would.

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

  if begins then
    perform app.audit('statusChanged', 'tasks', _task_id,
      'Task "' || task.title || '" changed from ' || app.task_status_label('pending')
        || ' to ' || app.task_status_label('inProgress'),
      jsonb_build_object('from', 'pending', 'to', 'inProgress', 'workOrderId', task.work_order_id));
  end if;
end;
$$;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
