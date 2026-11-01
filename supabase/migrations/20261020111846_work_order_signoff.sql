-- Work leaves "In Progress" only through its accomplishment report
-- (Objective 7.B: a bug found testing on live, 2026-10-20).
--
-- set_work_order_status let an administrator make any legal move, so the
-- console's Kanban board could take a work order to For Review with no
-- accomplishment report, or to Completed with the report never reviewed.
-- That skipped 5.B's sign-off: completed work with no completion notes or
-- photos checked, and an accomplishment report left unreviewed for good.
-- Now each move belongs to the step that makes it:
--
--   Pending -> In Progress       starting: here, by the technician assigned
--                                or an administrator
--   In Progress -> For Review    submit_accomplishment (the technician)
--   For Review -> Completed      review_accomplishment, approving
--   For Review -> In Progress    review_accomplishment, sending it back
--
-- and this function refuses the last three, saying where they are made.

create or replace function app.set_work_order_status(_work_order_id text, _to text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.work_orders;
  exists_ boolean;
begin
  select * into stored from public.work_orders w where w.id = _work_order_id;
  exists_ := found;

  if not (select app.is_admin()) then
    if not (select app.is_personnel())
       or not exists_
       or not ((select app.uid()) = any (stored.assigned_personnel_ids))
       or not (stored.status in ('pending', 'inProgress') and _to = 'inProgress') then
      perform app.refuse('PT403', 'You do not have permission to perform this action.');
    end if;
  end if;

  if exists_ and stored.status <> _to then
    if _to = 'forReview' then
      perform app.refuse('PT409', 'Work goes to For Review when its technician submits the '
        || 'accomplishment report.');
    elsif _to = 'completed' then
      perform app.refuse('PT409', 'Sign off the accomplishment report to complete this work order.');
    elsif stored.status = 'forReview' and _to = 'inProgress' then
      perform app.refuse('PT409', 'Send the work back from its accomplishment report, with a note '
        || 'for the technician.');
    end if;
  end if;

  perform app.move_work_order(_work_order_id, _to);
end;
$$;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
