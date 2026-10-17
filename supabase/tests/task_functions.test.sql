-- Tasks (Objective 1, M4).

begin;
select tests.create_fixtures();
select plan(25);

insert into public.work_orders (id, report_ids, title, description, category, priority, status, assigned_personnel_ids, created_by) values
  ('w-done', array['r-4'], 'Old job', 'Done.', 'electrical', 'low', 'completed', array['u-tech'], 'u-admin');
insert into public.tasks (id, work_order_id, title, assigned_to, status) values
  ('t-done', 'w-done', 'Finished task', 'u-tech', 'completed'),
  ('t-off', 'w-1', 'Their task', 'u-tech-off', 'pending');

-- ---------------------------------------------------------------- adding

select isnt(
  tests.query_as('u-admin', $$select public.add_task('w-2', '  Check the valves ', 'Under the sink', '2026-10-20 08:00+00')$$),
  null,
  'an administrator adds a task, and gets its id'
);
select is(
  (select array[title, description, assigned_to, status] from public.tasks where title = 'Check the valves'),
  array['Check the valves', 'Under the sink', 'u-tech2', 'pending'],
  '…assigned to the work order''s technician'
);
select is(
  (select array[type, title, body] from public.notifications where recipient_id = 'u-tech2'),
  array['taskAssigned', 'New task', '"Check the valves" was added to "Leaking pipe".'],
  '…who is told'
);
select is(
  (select array[description, changes ->> 'dueDate'] from public.audit_logs where entity_type = 'tasks' and action = 'created'),
  array['Task "Check the valves" added to #W-2', '2026-10-20T08:00:00.000Z'],
  '…and it is audited'
);
select is(
  tests.error_of('u-admin', $$select public.add_task('w-done', 'Late task')$$),
  'This work order is Completed, so no task can be added to it.',
  'not to finished work'
);
select is(
  tests.attempt('u-admin', $$select public.add_task('w-2', '   ')$$),
  'PT422',
  'a task needs a title'
);
select is(
  tests.attempt('u-admin', $$select public.add_task('w-2', repeat('t', 121))$$),
  'PT422',
  'of 120 characters at most'
);
select is(
  tests.attempt('u-tech2', $$select public.add_task('w-2', 'My own task')$$),
  'PT403',
  'a technician does not add tasks'
);

-- ---------------------------------------------------------------- working through them

select is(
  tests.attempt('u-tech2', $$select public.set_task_status('t-2', 'inProgress')$$),
  'ok',
  'the technician starts their task'
);
select is(
  (select array[t.status, w.status, r.status]
     from public.tasks t, public.work_orders w, public.damage_reports r
     where t.id = 't-2' and w.id = 'w-2' and r.id = 'r-2'),
  array['inProgress', 'inProgress', 'inProgress'],
  '…which starts the work order and its report with it'
);
select is(
  (select description from public.audit_logs where entity_id = 't-2'),
  'Task "Fix the joint" changed from To do to In progress',
  '…and is audited'
);
select is(
  tests.attempt('u-tech2', $$select public.set_task_status('t-1', 'completed')$$),
  'PT403',
  'a technician cannot work someone else''s task'
);
select is(
  tests.attempt('u-tech-off', $$select public.set_task_status('t-off', 'completed')$$),
  'PT403',
  'nor can a deactivated technician work their own'
);
select is(
  tests.attempt('u-tech', $$select public.set_task_status('t-1', 'completed')$$),
  'ok',
  'a task is marked done'
);
select ok(
  (select completed_at is not null from public.tasks where id = 't-1'),
  '…and stamped'
);
select is(
  tests.error_of('u-tech', $$select public.set_task_status('t-done', 'inProgress')$$),
  'This work order is Completed, so its tasks can no longer change.',
  'tasks of finished work do not change'
);

-- ---------------------------------------------------------------- proof

insert into public.tasks (id, work_order_id, title, assigned_to, status) values
  ('t-proof', 'w-1', 'Photograph the panel', 'u-tech', 'pending');
select is(
  tests.attempt('u-tech', $$select public.add_proof_photos('t-proof', array['p/a.jpg', 'p/b.jpg', 'p/a.jpg'])$$),
  'ok',
  'the technician adds proof photos'
);
select is(
  (select array[array_to_string(proof_photo_urls, ','), status] from public.tasks where id = 't-proof'),
  array['p/a.jpg,p/b.jpg', 'inProgress'],
  '…each once, and the task is under way'
);
select is(
  tests.attempt('u-tech', $$select public.add_proof_photos('t-proof', array['p/b.jpg', 'p/c.jpg'])$$),
  'ok',
  'more are added to them'
);
select is(
  (select array_to_string(proof_photo_urls, ',') from public.tasks where id = 't-proof'),
  'p/a.jpg,p/b.jpg,p/c.jpg',
  '…without repeating any'
);
select is(
  tests.attempt('u-tech', $$select public.add_proof_photos('t-proof', array[]::text[])$$),
  'PT422',
  'proof needs a photo'
);

-- ---------------------------------------------------------------- removing

select is(
  tests.error_of('u-admin', $$select public.delete_task('t-1')$$),
  'A task that is done stays on the record.',
  'a task that is done is not removed'
);
select is(
  tests.attempt('u-admin', $$select public.delete_task((select id from public.tasks where title = 'Check the valves'))$$),
  'ok',
  'an administrator removes a task'
);
select is(
  (select array[(select count(*)::text from public.tasks where title = 'Check the valves'), description]
     from public.audit_logs where entity_type = 'tasks' and action = 'deleted'),
  array['0', 'Task "Check the valves" removed from #W-2'],
  '…which is gone, and the removal audited'
);
select is(
  tests.attempt('u-tech', $$select public.delete_task('t-proof')$$),
  'PT403',
  'a technician does not remove tasks'
);

select * from finish();
rollback;
