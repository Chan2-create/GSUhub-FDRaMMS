-- Rating the service, reading notifications, saving settings
-- (Objective 1, M3).

begin;
select tests.create_fixtures();
select plan(23);

insert into public.work_orders (id, report_ids, title, description, category, priority, status, assigned_personnel_ids, created_by) values
  ('w-done', array['r-done'], 'Broken lock', 'Door 2', 'carpentry', 'medium', 'completed', array['u-tech'], 'u-admin');
insert into public.damage_reports (id, reporter_id, reporter_name, title, description, requestor_priority, status, work_order_id) values
  ('r-done', 'u-req', 'Maria Santos', 'Broken lock', 'The lock is stuck.', 'medium', 'completed', 'w-done');

-- ---------------------------------------------------------------- rating

select is(
  tests.attempt('u-req', $$select public.rate_service('r-done', 4, 5, 3, '  Quick and tidy. ')$$),
  'ok',
  'the person who filed a report rates the completed work'
);
select is(
  (select array[f.work_order_id, f.submitted_by, f.response_time_rating::text, f.service_quality_rating::text,
                f.overall_satisfaction_rating::text, f.comments, r.status]
     from public.feedback f join public.damage_reports r on r.id = f.report_id where f.id = 'r-done'),
  array['w-done', 'u-req', '4', '5', '3', 'Quick and tidy.', 'closed'],
  '…three separate ratings, and the rating closes the report'
);
select is(
  (select array[(select status from public.report_status_history where report_id = 'r-done'),
                (select count(*)::text from public.notifications where related_entity_id = 'r-done'),
                (select description from public.audit_logs where entity_id = 'r-done')]),
  array['closed', '0', 'Rated the service and closed the report'],
  '…on the timeline and in the audit, with no notice to themselves'
);
select is(
  tests.attempt('u-req', $$select public.rate_service('r-done', 1, 1, 1)$$),
  'ok',
  'rating again after it landed is a retry…'
);
select is(
  (select service_quality_rating from public.feedback where id = 'r-done'),
  5,
  '…which changes nothing'
);
select is(
  tests.error_of('u-req2', $$select public.rate_service('r-done', 1, 1, 1)$$),
  'Only the person who filed this report can rate the service.',
  'nobody rates someone else''s report'
);
select is(
  tests.error_of('u-req', $$select public.rate_service('r-1', 4, 4, 4)$$),
  'This service has already been rated.',
  'a report already rated is not rated twice'
);
select is(
  tests.error_of('u-req', $$select public.rate_service('r-3', 4, 4, 4)$$),
  'Only completed work can be rated. This report is report received.',
  'only completed work is rated'
);
update public.damage_reports set status = 'completed' where id = 'r-3';
update public.work_orders set report_ids = array['r-3'] where id = 'w-2';
update public.damage_reports set work_order_id = 'w-2' where id = 'r-3';
select is(
  tests.attempt('u-req', $$select public.rate_service('r-3', 6, 4, 4)$$),
  'PT422',
  'ratings are 1 to 5'
);
select is(
  tests.attempt('u-tech', $$select public.rate_service('r-3', 4, 4, 4)$$),
  'PT403',
  'a technician cannot rate work, their own least of all'
);
select is(
  tests.attempt('u-inactive', $$select public.rate_service('r-4', 4, 4, 4)$$),
  'PT403',
  'a deactivated account cannot rate'
);

-- ---------------------------------------------------------------- notifications

select is(
  tests.attempt('u-req', $$select public.mark_notification_read('n-1')$$),
  'ok',
  'a recipient marks their notification read'
);
select is(
  (select array[is_read::text, (read_at is not null)::text] from public.notifications where id = 'n-1'),
  array['true', 'true'],
  '…stamped with the time'
);
select is(
  tests.attempt('u-req2', $$select public.mark_notification_read('n-2')$$),
  'PT404',
  'nobody else''s'
);
select is(
  tests.attempt('u-inactive', $$select public.mark_notification_read('n-3')$$),
  'PT403',
  'a deactivated account marks nothing'
);
insert into public.notifications (id, recipient_id, type, title, body) values
  ('n-4', 'u-tech', 'taskAssigned', 'New task', 'Another one.');
select is(
  tests.attempt('u-tech', $$select public.mark_all_notifications_read()$$),
  'ok',
  'a technician clears their alerts'
);
select is(
  (select string_agg(id || ':' || is_read, ',' order by id) from public.notifications where id in ('n-2', 'n-3', 'n-4')),
  'n-2:true,n-3:false,n-4:true',
  '…all of theirs, and nobody else''s'
);

-- ---------------------------------------------------------------- settings

select is(
  tests.attempt('u-admin', $$select public.update_config('classification_rules',
    '{"keywordsByCategory":{"plumbing":["leak","pipe"]},"caseSensitive":false,"updatedAt":"x","updatedBy":"someone"}')$$),
  'ok',
  'an administrator saves the keyword dictionary'
);
select is(
  (select array[data -> 'keywordsByCategory' -> 'plumbing' ->> 1, coalesce(data ->> 'updatedBy', '-'), updated_by]
     from public.app_config where id = 'classification_rules'),
  array['pipe', '-', 'u-admin'],
  '…stored as sent, under the administrator who saved it, whatever the request claimed'
);
select is(
  tests.attempt('u-admin', $$select public.update_config('prioritization', '{"activeScheme":"decimal"}')$$),
  'ok',
  'a settings document that was never saved is created'
);
select is(
  tests.attempt('u-admin', $$select public.update_config('something_else', '{}')$$),
  '23514',
  'only the three settings documents exist'
);
select is(
  tests.attempt('u-admin', $$select public.update_config('prioritization', '[1, 2]')$$),
  'PT422',
  'settings are a document, not a list'
);
select is(
  tests.attempt('u-tech', $$select public.update_config('classification_rules', '{}')$$),
  'PT403',
  'only an administrator changes settings'
);

select * from finish();
rollback;
