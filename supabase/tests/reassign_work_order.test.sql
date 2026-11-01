-- Reassigning a work order (Objective 7.A; manuscript §3.4: "Modify report
-- priorities and assignments when necessary").

begin;
select tests.create_fixtures();
select plan(20);

update public.users set active_task_count = 0 where id = 'u-tech';
update public.users set active_task_count = 1 where id = 'u-tech2';
insert into public.tasks (id, work_order_id, title, assigned_to, status, completed_at) values
  ('t-done', 'w-2', 'Shut the valve', 'u-tech2', 'completed', now());

-- ------------------------------------------------------------ pending work

select is(
  tests.attempt('u-admin', $$select public.reassign_work_order('w-2', 'u-tech')$$),
  'ok',
  'an administrator hands pending work to another technician'
);
select is(
  (select assigned_personnel_ids from public.work_orders where id = 'w-2'),
  array['u-tech'],
  '…who alone holds it now'
);
select is(
  (select string_agg(id || ':' || active_task_count, ',' order by id) from public.users where id in ('u-tech', 'u-tech2')),
  'u-tech:1,u-tech2:0',
  '…and the open-work counts move with it'
);
select is(
  (select string_agg(id || ':' || assigned_to, ',' order by id) from public.tasks where work_order_id = 'w-2'),
  't-2:u-tech,t-done:u-tech2',
  '…its unfinished tasks follow it; a finished one keeps who did it'
);
select is(
  (select array[status, note, personnel_name, personnel_specialization] from public.report_status_history
     where report_id = 'r-2' and note like 'Reassigned%'),
  array['assigned', 'Reassigned to Marcus Wright.', 'Marcus Wright', 'electrical'],
  '…its report''s history names the new technician, so the requestor''s page does'
);
select is(
  (select title || ' / ' || body from public.notifications where recipient_id = 'u-req2' and related_entity_id = 'r-2'
     and title = 'New technician assigned'),
  'New technician assigned / Your report "Leaking pipe" is now with Marcus Wright.',
  '…the requestor is told'
);
select is(
  (select title || ' / ' || body from public.notifications where recipient_id = 'u-tech' and related_entity_id = 'w-2'),
  'New work order / You have been assigned "Leaking pipe".',
  '…the new technician is told, as for any assignment'
);
select is(
  (select title || ' / ' || body from public.notifications where recipient_id = 'u-tech2' and related_entity_id = 'w-2'),
  'Work reassigned / #W-2 ("Leaking pipe") was reassigned to Marcus Wright. It is off your list.',
  '…and so is the one it was taken from'
);
select is(
  (select array[action, description] from public.audit_logs where entity_id = 'w-2' and actor_id = 'u-admin'),
  array['assigned', 'Reassigned to Marcus Wright (was Juan Luna)'],
  '…and it is audited'
);

-- ------------------------------------------------------- work in progress

update public.users set active_task_count = 1 where id = 'u-tech';
select is(
  tests.attempt('u-admin', $$select public.reassign_work_order('w-1', 'u-tech2')$$),
  'ok',
  'work already in progress can be reassigned too'
);
select is(
  (select string_agg(id || ':' || active_task_count, ',' order by id) from public.users where id in ('u-tech', 'u-tech-off', 'u-tech2')),
  'u-tech:0,u-tech-off:0,u-tech2:1',
  '…every former holder is relieved of it, never below zero'
);
select is(
  (select array[status, note] from public.report_status_history where report_id = 'r-1' and note like 'Reassigned%'),
  array['inProgress', 'Reassigned to Juan Luna.'],
  '…and the history keeps the report''s own status'
);
select is(
  (select status from public.work_orders where id = 'w-1'),
  'inProgress',
  '…the work itself does not start over'
);

-- -------------------------------------------------------------- refusals

select is(
  tests.error_of('u-admin', $$select public.reassign_work_order('w-2', 'u-tech')$$),
  'Marcus Wright already has this work order.',
  'not to the technician who already holds it'
);
select is(
  tests.error_of('u-admin', $$select public.reassign_work_order('w-2', 'u-tech-off')$$),
  'Carlo Bato''s account is inactive and cannot take work.',
  'not to an account that is off'
);
select is(
  tests.error_of('u-admin', $$select public.reassign_work_order('w-2', 'u-req')$$),
  'Maria Santos is not maintenance personnel.',
  'not to someone who is not maintenance personnel'
);
update public.work_orders set status = 'forReview' where id = 'w-1';
select is(
  tests.error_of('u-admin', $$select public.reassign_work_order('w-1', 'u-tech')$$),
  'This work order is For Review. Only work that is pending or in progress can be reassigned.',
  'not work already sent for review'
);
select is(
  tests.error_of('u-admin', $$select public.reassign_work_order('w-x', 'u-tech')$$),
  'No work order w-x',
  'not a work order that does not exist'
);
select is(
  tests.attempt('u-tech', $$select public.reassign_work_order('w-2', 'u-tech2')$$),
  'PT403',
  'a technician cannot hand work on'
);
select is(
  tests.attempt('u-req', $$select public.reassign_work_order('w-2', 'u-tech2')$$),
  'PT403',
  'nor can a requestor'
);

select * from finish();
rollback;
