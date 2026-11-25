-- Scheduling (2026-11-26, the second brief): holidays kept by the
-- administrator; no Saturday, Sunday or holiday as a scheduling date, on
-- any function that takes one; a work order rescheduled with its reason;
-- the reporter's damage type in a review's history; Utility in the words
-- the database writes.

begin;
select tests.create_fixtures();
select plan(33);

-- Dates relative to today, so the file passes whenever it runs: the next
-- weekday a week out, the Saturday after it, and a later weekday made a
-- holiday below.
create temporary table days as
select
  (select d::timestamptz from generate_series(current_date + 7, current_date + 14, interval '1 day') d
     where extract(isodow from d) < 6 order by d limit 1) as weekday,
  (select d::timestamptz from generate_series(current_date + 7, current_date + 14, interval '1 day') d
     where extract(isodow from d) = 6 order by d limit 1) as saturday,
  (select d::date from generate_series(current_date + 20, current_date + 27, interval '1 day') d
     where extract(isodow from d) < 6 order by d limit 1) as holiday;
grant select on days to authenticated;

-- ------------------------------------------------------------ holidays

select is(
  tests.attempt('u-req', format($$select public.add_holiday(%L, 'Bonifacio Day')$$,
    (select holiday from days))),
  'PT403',
  'a requestor does not keep the holidays'
);
select is(
  tests.attempt('u-admin', format($$select public.add_holiday(%L, '  Bonifacio   Day ')$$,
    (select holiday from days))),
  'ok',
  'an administrator adds a holiday'
);
select is(
  (select name from public.holidays where day = (select holiday from days)),
  'Bonifacio Day',
  '…its name tidied'
);
select is(
  tests.error_of('u-admin', format($$select public.add_holiday(%L, 'Another')$$,
    (select holiday from days))),
  app.day_label((select holiday from days)) || ' is already a holiday (Bonifacio Day).',
  'one holiday a day'
);
select is(
  tests.error_of('u-admin', format($$select public.add_holiday(%L, '  ')$$,
    (select holiday from days))),
  'Name the holiday.',
  'a holiday has a name'
);
select is(
  tests.visible('u-req', 'holidays', 'name') || ' / ' || tests.visible('u-tech', 'holidays', 'name')
    || ' / ' || tests.visible(null, 'holidays', 'name'),
  'Bonifacio Day / Bonifacio Day / ERROR 42501',
  'every account reads them, for its date pickers; nobody signed out does'
);
select is(
  (select description from public.audit_logs where entity_type = 'holidays'),
  'Added the holiday Bonifacio Day on ' || app.day_label((select holiday from days)),
  'adding one is audited'
);

-- ------------------------------------------------------------ the working-day rule

select is(
  app.is_working_day((select weekday from days)::date)::text || ' '
    || app.is_working_day((select saturday from days)::date)::text || ' '
    || app.is_working_day((select holiday from days))::text,
  'true false false',
  'a weekday works; a Saturday and a holiday do not'
);
select is(
  app.local_day('2026-12-01T16:00:00Z'::timestamptz)::text,
  '2026-12-02',
  'a date is read as the Philippine calendar day it was picked on'
);

update public.damage_reports set status = 'approved', category = 'electrical',
  official_priority = 'medium' where id = 'r-3';

select is(
  tests.error_of('u-admin', format($$select public.assign_work_order('r-3', 'u-tech', %L)$$,
    (select saturday from days))),
  app.day_label((select saturday from days)::date) || ' is a Saturday. Choose a weekday that is not a holiday.',
  'no target date on a Saturday'
);
select is(
  tests.error_of('u-admin', format($$select public.assign_work_order('r-3', 'u-tech', %L)$$,
    (select holiday from days)::timestamptz)),
  app.day_label((select holiday from days)) || ' is a holiday (Bonifacio Day). Choose a weekday that is not a holiday.',
  'nor on a holiday'
);
select is(
  tests.error_of('u-admin', format($$select public.reschedule_report('r-3', 'Waiting for parts', %L)$$,
    (select saturday from days) + interval '1 day')),
  app.day_label((select saturday from days)::date + 1) || ' is a Sunday. Choose a weekday that is not a holiday.',
  'scheduling a report refuses a Sunday too'
);
select is(
  tests.attempt('u-admin', format($$select public.reschedule_report('r-3', 'Waiting for parts', %L)$$,
    (select weekday from days))),
  'ok',
  'and takes a weekday'
);
select is(
  (select title || ': ' || body from public.notifications
     where recipient_id = 'u-req' and related_entity_id = 'r-3' and title = 'Report scheduled'),
  'Report scheduled: The work on your report "Broken chair" is scheduled for '
    || app.day_label((select weekday from days)::date) || ': Waiting for parts',
  'the first date is a schedule, in the requestor''s words too'
);
select is(
  tests.error_of('u-admin', format($$select public.add_task('w-1', 'Replace the ballast', null, %L)$$,
    (select saturday from days))),
  app.day_label((select saturday from days)::date) || ' is a Saturday. Choose a weekday that is not a holiday.',
  'a task is not due on a Saturday'
);
select is(
  tests.attempt('u-admin', format($$select public.add_task('w-1', 'Replace the ballast', null, %L)$$,
    (select weekday from days))),
  'ok',
  '…but on a weekday'
);
select is(
  tests.attempt('u-admin', $$select public.add_task('w-1', 'Check the switch')$$),
  'ok',
  'a task with no due date is unaffected'
);

-- ------------------------------------------------------------ rescheduling a work order

select is(
  tests.attempt('u-tech', format($$select public.reschedule_work_order('w-1', %L, 'Parts are late')$$,
    (select weekday from days))),
  'PT403',
  'a technician does not reschedule work orders'
);
select is(
  tests.error_of('u-admin', format($$select public.reschedule_work_order('w-1', %L, '  ')$$,
    (select weekday from days))),
  'Give the reason for rescheduling.',
  'rescheduling needs a reason'
);
select is(
  tests.error_of('u-admin', $$select public.reschedule_work_order('w-1', null, 'Parts are late')$$),
  'Choose the new date.',
  '…and a date'
);
select is(
  tests.error_of('u-admin', format($$select public.reschedule_work_order('w-1', %L, 'Parts are late')$$,
    (select holiday from days)::timestamptz)),
  app.day_label((select holiday from days)) || ' is a holiday (Bonifacio Day). Choose a weekday that is not a holiday.',
  '…a working day'
);
select is(
  tests.attempt('u-admin', format($$select public.reschedule_work_order('w-1', %L, 'Parts are late')$$,
    (select weekday from days))),
  'ok',
  'an administrator reschedules open work'
);
select is(
  (select scheduled_for = (select weekday from days) from public.work_orders where id = 'w-1'),
  true,
  '…its target date moves'
);
select is(
  (select array[status, note, (rescheduled_to = (select weekday from days))::text]
     from public.report_status_history where report_id = 'r-1' and note = 'Parts are late'),
  array['inProgress', 'Parts are late', 'true'],
  '…its report keeps its status, the reason and the date on its timeline'
);
select is(
  (select body from public.notifications where recipient_id = 'u-req' and related_entity_id = 'r-1'
     and title = 'Work rescheduled'),
  'The work on your report "Flickering lights" is rescheduled to '
    || app.day_label((select weekday from days)::date) || ': Parts are late',
  '…the requestor is told the date and the reason'
);
select is(
  (select string_agg(recipient_id, ',' order by recipient_id) from public.notifications
     where related_entity_id = 'w-1' and title = 'Work rescheduled'),
  'u-tech,u-tech-off',
  '…and so is everyone holding the work'
);
select is(
  (select description from public.audit_logs where entity_id = 'w-1' and description like 'Rescheduled%'),
  'Rescheduled to ' || app.day_label((select weekday from days)::date) || ': Parts are late',
  '…on the work order''s history'
);
update public.work_orders set status = 'completed' where id = 'w-2';
select is(
  tests.error_of('u-admin', format($$select public.reschedule_work_order('w-2', %L, 'Late')$$,
    (select weekday from days))),
  'This work order is Completed. Only work that is pending or in progress can be rescheduled.',
  'finished work is not rescheduled'
);

-- ------------------------------------------------------------ the reporter's damage type

select is(
  tests.attempt('u-req2', $$select public.submit_report('r-typed', 'Sparking outlet',
    'The outlet sparks when used.', 'high', 'electrical', 'electrical', 'f-1', 'Engineering Building',
    'Room 101')$$),
  'ok',
  'a reporter files a report choosing Electrical'
);
select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-typed', 'electrical', false, 2, 2, 2, 2,
      2.0, 'medium', 'medium')$$),
  'ok',
  'an administrator confirms the type the reporter chose'
);
select is(
  (select description from public.audit_logs where entity_id = 'r-typed'
     and description like 'Classified%'),
  'Classified as Electrical, the reporter''s choice; official priority MEDIUM as recommended (score 2.00)',
  'a review that keeps the reporter''s type says so'
);

-- ------------------------------------------------------------ the holiday removed

select is(
  tests.attempt('u-admin', format($$select public.remove_holiday(%L)$$, (select holiday from days))),
  'ok',
  'an administrator removes a holiday'
);
select is(
  app.is_working_day((select holiday from days)),
  true,
  '…and it is a working day again'
);

select * from finish();
rollback;
