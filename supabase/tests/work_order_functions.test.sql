-- Work orders (Objective 1, M3): raising one from a report, moving it,
-- the note to the technician.

begin;
select tests.create_fixtures();
select plan(37);

insert into public.damage_reports (id, reporter_id, reporter_name, title, description, requestor_priority, status,
  category, official_priority, facility_id, facility_name, location_description) values
  ('r-ok', 'u-req', 'Maria Santos', 'Dead socket', 'No power in the socket.', 'medium', 'approved',
    'electrical', 'high', 'f-1', 'Engineering Building', 'Room 101, by the door'),
  ('r-unrated', 'u-req', 'Maria Santos', 'Odd noise', 'Something hums.', 'low', 'approved',
    null, null, 'f-1', 'Engineering Building', null),
  ('r-unconfirmed', 'u-req', 'Maria Santos', 'Odd smell', 'Something smells.', 'low', 'approved',
    'plumbing', null, 'f-1', 'Engineering Building', null),
  ('r-long', 'u-req2', 'Ana Gomez', repeat('L', 200), 'A report with the longest title there is.', 'low', 'approved',
    'carpentry', 'low', null, null, null);

-- ---------------------------------------------------------------- assigning

select isnt(
  tests.query_as('u-admin', $$select public.assign_work_order('r-ok', 'u-tech2', '2026-10-20 08:00+00')$$),
  null,
  'an administrator assigns an approved report, and gets the work order''s id'
);
select is(
  (select array[w.status, w.title, w.priority, w.category, array_to_string(w.assigned_personnel_ids, ','),
                array_to_string(w.report_ids, ','), w.created_by, w.facility_name]
     from public.work_orders w join public.damage_reports r on r.work_order_id = w.id where r.id = 'r-ok'),
  array['pending', 'Dead socket', 'high', 'electrical', 'u-tech2', 'r-ok', 'u-admin', 'Engineering Building'],
  '…a pending work order carrying the report''s official priority and category'
);
select is(
  (select status from public.damage_reports where id = 'r-ok'),
  'assigned',
  '…the report is assigned'
);
select is(
  (select active_task_count from public.users where id = 'u-tech2'),
  1,
  '…the technician''s open work goes up by one'
);
select is(
  (select array[t.title, t.description, t.assigned_to, t.status, (t.due_date at time zone 'UTC')::text || '+00']
     from public.tasks t join public.damage_reports r on r.work_order_id = t.work_order_id where r.id = 'r-ok'),
  array['Dead socket', 'Room 101, by the door', 'u-tech2', 'pending', '2026-10-20 08:00:00+00'],
  '…the job itself is its first task, due on the target date'
);
select is(
  (select array[type, title, body, related_entity_type] from public.notifications
     where recipient_id = 'u-tech2'),
  array['workOrderAssigned', 'New work order', 'You have been assigned "Dead socket" at Engineering Building.', 'work_orders'],
  '…the technician is told'
);
select is(
  (select array[n.title, n.body, h.personnel_name, h.personnel_specialization]
     from public.notifications n, public.report_status_history h
     where n.related_entity_id = 'r-ok' and h.report_id = 'r-ok' and h.status = 'assigned'),
  array['Personnel assigned', 'Juan Luna was assigned to your report "Dead socket".', 'Juan Luna', 'plumbing'],
  '…the requestor is told who, and the timeline names them'
);
select is(
  (select string_agg(entity_type || ':' || action || ':' || description, ' | ' order by entity_type)
     from public.audit_logs where entity_id = 'r-ok'
        or entity_id = (select work_order_id from public.damage_reports where id = 'r-ok')),
  'damage_reports:assigned:Assigned to Juan Luna | work_orders:created:Work order created from report r-ok',
  '…and both changes are audited'
);
select is(
  (select changes ->> 'scheduledFor' from public.audit_logs
     where action = 'created' and entity_id = (select work_order_id from public.damage_reports where id = 'r-ok')),
  '2026-10-20T08:00:00.000Z',
  '…with the target date as the app writes dates'
);
select isnt(
  tests.query_as('u-admin', $$select public.assign_work_order('r-long', 'u-tech')$$),
  null,
  'a report with a 200-character title can be assigned: its task takes the same title'
);

select is(
  tests.error_of('u-admin', $$select public.assign_work_order('r-ok', 'u-tech')$$),
  'Only approved reports can be assigned. This one is ASSIGNED.',
  'a report is assigned once'
);
select is(
  tests.error_of('u-admin', $$select public.assign_work_order('r-unrated', 'u-tech')$$),
  'This report has no damage category yet, so no work order can be raised for it. It must be classified first.',
  'not before it is classified'
);
select is(
  tests.error_of('u-admin', $$select public.assign_work_order('r-unconfirmed', 'u-tech')$$),
  'This report''s official priority has not been confirmed yet. Confirm it on the report page before assigning the work.',
  'nor before its official priority is confirmed'
);
update public.damage_reports set status = 'approved', category = 'plumbing', official_priority = 'low' where id = 'r-unrated';
select is(
  tests.error_of('u-admin', $$select public.assign_work_order('r-unrated', 'u-req2')$$),
  'Ana Gomez is not maintenance personnel.',
  'only to maintenance personnel'
);
select is(
  tests.error_of('u-admin', $$select public.assign_work_order('r-unrated', 'u-tech-off')$$),
  'Carlo Bato''s account is inactive and cannot take work.',
  'only to an active account'
);
select is(
  tests.attempt('u-admin', $$select public.assign_work_order('r-nowhere', 'u-tech')$$),
  'PT404',
  'not a report that does not exist'
);
select is(
  tests.attempt('u-tech', $$select public.assign_work_order('r-unrated', 'u-tech')$$),
  'PT403',
  'a technician cannot assign work, even to themselves'
);

-- ---------------------------------------------------------------- moving

select is(
  tests.attempt('u-tech2', $$select public.set_work_order_status((select work_order_id from public.damage_reports where id = 'r-ok'), 'inProgress')$$),
  'ok',
  'the technician assigned starts the work'
);
select is(
  (select array[w.status, (w.started_at is not null)::text, r.status]
     from public.work_orders w join public.damage_reports r on r.work_order_id = w.id where r.id = 'r-ok'),
  array['inProgress', 'true', 'inProgress'],
  '…the work order and its report move together, and the start is stamped'
);
select is(
  (select body from public.notifications where related_entity_id = 'r-ok' and title = 'Work started'),
  'Work has started on your report "Dead socket".',
  '…the requestor is told'
);
select is(
  tests.attempt('u-tech', $$select public.set_work_order_status('w-2', 'inProgress')$$),
  'PT403',
  'a technician cannot start someone else''s work'
);
select is(
  tests.attempt('u-tech2', $$select public.set_work_order_status((select work_order_id from public.damage_reports where id = 'r-ok'), 'forReview')$$),
  'PT403',
  'nor submit it this way: that goes with the accomplishment report'
);
select is(
  tests.attempt('u-tech-off', $$select public.set_work_order_status('w-1', 'inProgress')$$),
  'PT403',
  'a deactivated technician moves nothing, even work assigned to them'
);
select is(
  tests.attempt('u-req', $$select public.set_work_order_status('w-2', 'inProgress')$$),
  'PT403',
  'a requestor moves no work orders'
);

select is(
  tests.error_of('u-admin', $$select public.set_work_order_status('w-2', 'completed')$$),
  'A work order cannot move from Pending to Completed.',
  'an administrator cannot skip the lifecycle'
);
update public.users set active_task_count = 1 where id = 'u-tech';
select is(
  tests.attempt('u-admin', $$select public.set_work_order_status('w-1', 'forReview')$$)
    || tests.attempt('u-admin', $$select public.set_work_order_status('w-1', 'completed')$$),
  'okok',
  'an administrator signs work off'
);
select is(
  (select array[w.status, (w.completed_at is not null)::text, r.status]
     from public.work_orders w join public.damage_reports r on r.id = 'r-1' where w.id = 'w-1'),
  array['completed', 'true', 'completed'],
  '…the report is completed with it'
);
select is(
  (select string_agg(id || ':' || active_task_count, ',' order by id) from public.users where id in ('u-tech', 'u-tech-off')),
  'u-tech:0,u-tech-off:0',
  '…and the job stops counting against whoever held it, never below zero'
);
select is(
  (select body from public.notifications where related_entity_id = 'r-1' and title = 'Work completed'),
  'The work on your report "Flickering lights" is complete. Open it to rate the service.',
  '…and the requestor is asked to rate it'
);
select is(
  (select description from public.audit_logs where entity_id = 'w-1' order by "timestamp" desc, description limit 1),
  'Status changed from For Review to Completed',
  'each move is audited'
);

-- A report that cannot follow its work order stops the move.
update public.damage_reports set status = 'rejected' where id = 'r-2';
select is(
  tests.error_of('u-admin', $$select public.set_work_order_status('w-2', 'inProgress')$$),
  'Report r-2 is REJECTED and cannot move to IN PROGRESS with this work order.',
  'a work order whose report disagrees with it does not move…'
);
select is(
  (select status from public.work_orders where id = 'w-2'),
  'pending',
  '…at all'
);

-- ---------------------------------------------------------------- the note

select is(
  tests.attempt('u-admin', $$select public.update_admin_notes('w-2', repeat('n', 90))$$),
  'ok',
  'an administrator leaves the technician a note'
);
select is(
  (select description from public.audit_logs where entity_id = 'w-2'),
  'Note to the technician: "' || repeat('n', 80) || '…"',
  '…the audit quotes the start of it'
);
select is(
  tests.attempt('u-admin', $$select public.update_admin_notes('w-2', '  ')$$),
  'ok',
  'and removes it'
);
select is(
  (select array[coalesce(w.admin_notes, '-'), a.description]
     from public.work_orders w, public.audit_logs a
     where w.id = 'w-2' and a.entity_id = 'w-2' and a.description like '%removed'),
  array['-', 'Note to the technician removed'],
  '…which is audited too'
);
select is(
  tests.attempt('u-tech2', $$select public.update_admin_notes('w-2', 'Note to self')$$),
  'PT403',
  'a technician cannot write the administrator''s note'
);

select * from finish();
rollback;
