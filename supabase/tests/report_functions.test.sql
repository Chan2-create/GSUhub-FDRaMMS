-- Damage reports (Objective 1, M3): filing, assessment, review moves,
-- merging duplicates, keeping two apart.

begin;
select tests.create_fixtures();
select plan(44);

-- ---------------------------------------------------------------- filing

select is(
  tests.attempt('u-req2', $$select public.submit_report('r-new', '  Broken window ', 'Glass cracked.', 'high',
    'structural', 'structural', 'f-1', 'Engineering Building', 'Room 101', null, 7.1, 126.5,
    array['https://photos.test/1.jpg'])$$),
  'ok',
  'a requestor files a report'
);
select is(
  (select array[reporter_id, reporter_name, title, status, category, classified_automatically::text, latitude::text]
     from public.damage_reports where id = 'r-new'),
  array['u-req2', 'Ana Gomez', 'Broken window', 'submitted', 'structural', 'true', '7.1'],
  '…under their own name from their account, the classifier''s category marked automatic'
);
select is(
  (select array[status, changed_by] from public.report_status_history where report_id = 'r-new'),
  array['submitted', 'u-req2'],
  '…its timeline starts'
);
select is(
  (select array[recipient_id, type, title, body] from public.notifications where related_entity_id = 'r-new'),
  array['u-req2', 'reportAcknowledged', 'Report received',
    'The General Services Unit received your report "Broken window". You will be notified as it moves along.'],
  '…they are told it was received'
);
select is(
  (select array[description, changes ->> 'photos', changes ->> 'geoTagged'] from public.audit_logs where entity_id = 'r-new'),
  array['Submitted "Broken window"', '1', 'true'],
  '…and it is audited'
);
select is(
  tests.attempt('u-req2', $$select public.submit_report('r-new', 'Broken window', 'Glass cracked.', 'high')$$),
  'ok',
  'filing again under the same id is a retry…'
);
select is(
  (select count(*)::int from public.report_status_history where report_id = 'r-new'),
  1,
  '…and changes nothing'
);
select is(
  tests.attempt('u-req', $$select public.submit_report('r-new', 'Mine', 'Mine.', 'low')$$),
  'PT409',
  'nobody files over someone else''s report'
);
select is(
  tests.attempt('u-tech', $$select public.submit_report('r-t', 'T', 'T.', 'low')$$),
  'PT403',
  'a technician does not file damage reports'
);
select is(
  tests.attempt('u-pending', $$select public.submit_report('r-p', 'P', 'P.', 'low')$$),
  'PT403',
  'nor does a requestor awaiting approval'
);
select is(
  tests.attempt('u-req', $$select public.submit_report('r-blank', '   ', 'Something.', 'low')$$),
  'PT422',
  'a report needs a title'
);

-- ---------------------------------------------------------------- assessment

select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-3', 'carpentry', false, 3, 2, 2, 2, 2.4, 'medium', 'high')$$),
  'ok',
  'an administrator assesses a report'
);
select is(
  (select array[category, classified_automatically::text, official_priority, recommended_priority, reviewed_by]
     from public.damage_reports where id = 'r-3'),
  array['carpentry', 'false', 'high', 'medium', 'u-admin'],
  '…setting its type, ratings and priorities'
);
select is(
  (select description from public.audit_logs where entity_id = 'r-3'),
  'Classified as Carpentry; official priority HIGH, raised from the recommended MEDIUM (score 2.40)',
  '…and the audit says whether the priority departs from the recommendation'
);
select is(
  tests.error_of('u-admin', $$select public.record_assessment('r-1', 'electrical', false, 3, 2, 2, 2, 2.4, 'medium', 'high')$$),
  'This report is IN PROGRESS. Its damage type and priority are set before a work order is raised, and cannot change now.',
  'not once a work order has been raised'
);
select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-3', 'carpentry', false, 5, 2, 2, 2, 2.4, 'medium', 'high')$$),
  'PT422',
  'ratings are 1 to 4'
);
select is(
  tests.attempt('u-req', $$select public.record_assessment('r-3', 'carpentry', false, 1, 1, 1, 1, 1, 'low', 'critical')$$),
  'PT403',
  'a requestor cannot assess, their own report included'
);

-- ---------------------------------------------------------------- review moves

select is(
  tests.attempt('u-admin', $$select public.transition_report('r-3', 'underReview')$$),
  'ok',
  'an administrator takes a report under review'
);
select is(
  (select count(*)::int from public.notifications where related_entity_id = 'r-3'),
  0,
  '…the requestor is not told of that step'
);
select is(
  (select description from public.audit_logs where entity_id = 'r-3' and action = 'statusChanged'),
  'Status changed from PENDING to UNDER REVIEW',
  '…but it is audited'
);
select is(
  tests.attempt('u-admin', $$select public.transition_report('r-3', 'approved')$$),
  'ok',
  'and approves it'
);
select is(
  (select array[n.title, n.recipient_id, r.reviewed_by]
     from public.notifications n, public.damage_reports r
     where n.related_entity_id = 'r-3' and r.id = 'r-3'),
  array['Report approved', 'u-req', 'u-admin'],
  '…the requestor is told'
);
select is(
  tests.error_of('u-admin', $$select public.transition_report('r-3', 'assigned')$$),
  'A report moves to ASSIGNED with its work order, not on its own.',
  'later stages go with the work order'
);
select is(
  tests.error_of('u-admin', $$select public.transition_report('r-new', 'rejected', '  ')$$),
  'Give a reason for rejecting this report.',
  'a rejection needs a reason'
);
select is(
  tests.error_of('u-admin', $$select public.transition_report('r-1', 'approved')$$),
  'A report cannot move from IN PROGRESS to APPROVED.',
  'a move the lifecycle does not allow is refused'
);
select is(
  tests.attempt('u-admin', $$select public.transition_report('r-new', 'underReview')$$)
    || tests.attempt('u-admin', $$select public.transition_report('r-new', 'rejected', ' Not GSU''s responsibility. ')$$),
  'okok',
  'an administrator rejects a report with a reason'
);
select is(
  (select array[r.rejection_reason, n.body]
     from public.damage_reports r, public.notifications n
     where r.id = 'r-new' and n.related_entity_id = 'r-new' and n.title = 'Report not accepted'),
  array['Not GSU''s responsibility.', 'Your report "Broken window" was not accepted: Not GSU''s responsibility.'],
  '…which the requestor is told'
);
select is(
  tests.attempt('u-req', $$select public.transition_report('r-3', 'underReview')$$),
  'PT403',
  'a requestor cannot move reports'
);

-- ---------------------------------------------------------------- duplicates

insert into public.damage_reports (id, reporter_id, reporter_name, title, description, requestor_priority, status) values
  ('r-a', 'u-req2', 'Ana Gomez', 'Loose chair', 'Same chair.', 'low', 'submitted'),
  ('r-b', 'u-req', 'Maria Santos', 'Wobbly chair', 'Same chair again.', 'low', 'underReview'),
  ('r-c', 'u-req', 'Maria Santos', 'Chair', 'Again.', 'low', 'submitted');

select is(
  tests.attempt('u-admin', $$select public.merge_duplicates('r-3', array['r-a', 'r-b', 'r-a'])$$),
  'ok',
  'an administrator merges duplicates into the report they repeat'
);
select is(
  (select string_agg(id || ':' || status || ':' || duplicate_of, ',' order by id) from public.damage_reports where id in ('r-a', 'r-b')),
  'r-a:merged:r-3,r-b:merged:r-3',
  '…each marked merged, pointing at it'
);
select is(
  (select body from public.notifications where related_entity_id = 'r-a'),
  'Your report "Loose chair" was merged with report #R-3, which reported the same damage.',
  '…each requestor is told which report carries on'
);
select is(
  (select description from public.audit_logs where entity_id = 'r-a'),
  'Merged into #R-3 as a duplicate',
  '…and each merge is audited'
);
select is(
  tests.error_of('u-admin', $$select public.merge_duplicates('r-3', array['r-3'])$$),
  'A report cannot be merged into itself.',
  'not into itself'
);
select is(
  tests.error_of('u-admin', $$select public.merge_duplicates('r-3', array[]::text[])$$),
  'Choose the reports to merge.',
  'not nothing'
);
select is(
  tests.error_of('u-admin', $$select public.merge_duplicates('r-3', array['r-1'])$$),
  'Report #R-1 is IN PROGRESS. Only a report still awaiting review can be merged.',
  'not a report with work under way'
);
select is(
  tests.attempt('u-admin', $$select public.merge_duplicates('r-3', array['r-c', 'r-1'])$$),
  'PT409',
  'one report that cannot be merged refuses the whole merge…'
);
select is(
  (select status from public.damage_reports where id = 'r-c'),
  'submitted',
  '…so none of it happens'
);
select is(
  tests.error_of('u-admin', $$select public.merge_duplicates('r-a', array['r-c'])$$),
  'Report #R-A is itself merged, so no report can be merged into it.',
  'nothing is merged into a merged report'
);
select is(
  tests.attempt('u-req', $$select public.merge_duplicates('r-3', array['r-c'])$$),
  'PT403',
  'a requestor cannot merge reports'
);

select is(
  tests.attempt('u-admin', $$select public.keep_separate('r-3', 'r-c')$$),
  'ok',
  'an administrator keeps two reports apart'
);
select is(
  tests.attempt('u-admin', $$select public.keep_separate('r-c', 'r-3')$$),
  'ok',
  'saying so twice, either way round, is fine…'
);
select is(
  (select string_agg(id || ':' || array_to_string(dismissed_duplicate_ids, '|'), ',' order by id)
     from public.damage_reports where id in ('r-3', 'r-c')),
  'r-3:r-c,r-c:r-3',
  '…the pair is noted once on both'
);
select is(
  tests.attempt('u-admin', $$select public.keep_separate('r-3', 'r-3')$$),
  'PT422',
  'a report is not compared with itself'
);
select is(
  tests.attempt('u-admin', $$select public.keep_separate('r-3', 'r-nowhere')$$),
  'PT404',
  'nor with one that does not exist'
);

select * from finish();
rollback;
