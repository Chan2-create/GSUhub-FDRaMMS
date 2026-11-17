-- What the requestor chose stays; what the administrator decided is
-- recorded beside it (2026-11-16): the review's audit trail, the guard on
-- the requestor's own selections, and two reviews not overwriting each
-- other unnoticed.

begin;
select tests.create_fixtures();
select plan(29);

-- ------------------------------------------------- what the requestor files

select is(
  tests.attempt('u-req2', $$select public.submit_report('r-f', 'Sparking outlet', 'The outlet sparks when used.',
    'high', 'electrical', 'electrical', 'f-1', 'Engineering Building', 'Room 101')$$),
  'ok',
  'a requestor files a report with the damage type and the urgency they chose'
);
select is(
  (select array[requestor_category, requestor_priority, coalesce(official_priority, 'none'),
                coalesce(recommended_priority, 'none'), status]
     from public.damage_reports where id = 'r-f'),
  array['electrical', 'high', 'none', 'none', 'submitted'],
  '…kept as their own, with no official priority until an administrator reviews it'
);

-- ------------------------------------------------- the administrator's review

select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-f', 'plumbing', false, 4, 4, 3, 3, 3.7,
    'critical', 'critical', '  A burst pipe behind the outlet, not the wiring.  ')$$),
  'ok',
  'an administrator changes both the damage type and the priority, and says why'
);
select is(
  (select array[category, official_priority, recommended_priority, reviewed_by]
     from public.damage_reports where id = 'r-f'),
  array['plumbing', 'critical', 'critical', 'u-admin'],
  '…the official damage type and priority are theirs'
);
select is(
  (select array[requestor_category, requestor_priority] from public.damage_reports where id = 'r-f'),
  array['electrical', 'high'],
  '…and what the requestor chose is still what the requestor chose'
);
select is(
  (select array[actor_id, actor_name, description] from public.audit_logs
     where entity_id = 'r-f' and action = 'updated'),
  array['u-admin', 'Ramon Dela Cruz',
    'Classified as Plumbing; official priority CRITICAL as recommended (score 3.70). '
    || 'Reason: A burst pipe behind the outlet, not the wiring.'],
  'the audit entry names the administrator and carries the reason'
);
select is(
  (select array[
      changes -> 'requestor' ->> 'category', changes -> 'requestor' ->> 'priority',
      changes -> 'category' ->> 'from', changes -> 'category' ->> 'to',
      coalesce(changes -> 'officialPriority' ->> 'from', 'none'), changes -> 'officialPriority' ->> 'to',
      changes ->> 'firstReview', changes ->> 'reason']
     from public.audit_logs where entity_id = 'r-f' and action = 'updated'),
  array['electrical', 'high', 'electrical', 'plumbing', 'none', 'critical', 'true',
    'A burst pipe behind the outlet, not the wiring.'],
  '…with what the requestor chose, and what each value was and became'
);
select ok(
  (select "timestamp" is not null from public.audit_logs where entity_id = 'r-f' and action = 'updated'),
  '…and when'
);

select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-f', 'plumbing', false, 4, 4, 3, 3, 3.7,
    'critical', 'high', 'Water shut off at the main; no longer urgent.')$$),
  'ok',
  'a later change to the official priority is a review of its own'
);
select is(
  (select array[changes -> 'officialPriority' ->> 'from', changes -> 'officialPriority' ->> 'to',
                changes ->> 'firstReview', changes -> 'requestor' ->> 'priority']
     from public.audit_logs where entity_id = 'r-f' and action = 'updated'
     order by (changes ->> 'firstReview') limit 1),
  array['critical', 'high', 'false', 'high'],
  '…recorded from the earlier official value, the requestor''s still beside it'
);
select is(
  (select count(*)::int from public.audit_logs where entity_id = 'r-f' and action = 'updated'),
  2,
  'both decisions stay in the trail'
);

select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-f', 'plumbing', false, 4, 4, 3, 3, 3.7,
    'critical', 'high')$$),
  'ok',
  'saving the same review again is accepted…'
);
select is(
  (select count(*)::int from public.audit_logs where entity_id = 'r-f' and action = 'updated'),
  2,
  '…and writes nothing: a save sent twice is one decision'
);
select is(
  tests.attempt('u-admin', format($$select public.record_assessment('r-f', 'plumbing', false, 4, 4, 3, 3, 3.7,
    'critical', 'high', %L)$$, repeat('x', 501))),
  'PT422',
  'a reason is at most 500 characters'
);

-- ------------------------------------------------- what was filed stays

select throws_ok(
  $$update public.damage_reports set requestor_priority = 'low' where id = 'r-f'$$,
  'PT409',
  'What the requestor chose when filing a report is kept as filed. The administrator''s review is recorded beside it.',
  'the requestor''s urgency cannot be changed, by anyone or anything'
);
select throws_ok(
  $$update public.damage_reports set requestor_category = null where id = 'r-f'$$,
  'PT409',
  null,
  'nor the damage type they chose'
);
select lives_ok(
  $$update public.damage_reports set requestor_priority = requestor_priority, title = 'Sparking outlet (east wall)'
     where id = 'r-f'$$,
  'the rest of the report is not held by it'
);
select is(
  tests.attempt('u-admin', $$select public.transition_report('r-f', 'underReview')$$),
  'ok',
  'and the report moves on as before'
);

-- ------------------------------------------------- two people, one report

-- Each test runs in one transaction, where now() stands still: someone
-- else's change is given a later time by hand.
create temporary table seen as
  select updated_at from public.damage_reports where id = 'r-3';

select is(
  tests.attempt('u-admin', format($$select public.record_assessment('r-3', 'carpentry', false, 3, 2, 2, 2, 2.4,
    'medium', 'high', null, %L::timestamptz)$$, (select updated_at from seen))),
  'ok',
  'a review of the report as the console last read it is saved'
);

update public.damage_reports
  set severity_rating = 4, updated_at = updated_at + interval '10 seconds'
  where id = 'r-3';

select is(
  tests.error_of('u-admin', format($$select public.record_assessment('r-3', 'electrical', false, 1, 1, 1, 1, 1,
    'low', 'low', null, %L::timestamptz)$$, (select updated_at from seen))),
  'This report was changed after you opened it here. The latest details are shown now: check them, then save again.',
  'a review of a report that has changed since is refused, not saved over the change'
);
select is(
  (select array[category, official_priority, severity_rating::text] from public.damage_reports where id = 'r-3'),
  array['carpentry', 'high', '4'],
  '…and the change it would have replaced is intact'
);

insert into public.audit_logs (actor_id, actor_name, action, entity_type, entity_id, description, "timestamp")
  values ('u-tech', 'Marcus Wright', 'updated', 'damage_reports', 'r-3', 'Changed meanwhile',
    (select updated_at + interval '10 seconds' from seen));
select is(
  tests.error_of('u-admin', format($$select public.record_assessment('r-3', 'electrical', false, 1, 1, 1, 1, 1,
    'low', 'low', null, %L::timestamptz)$$, (select updated_at from seen))),
  'Marcus Wright changed this report after you opened it here. The latest details are shown now: check them, then save again.',
  'the refusal names who changed it, when the trail says'
);
insert into public.audit_logs (actor_id, actor_name, action, entity_type, entity_id, description, "timestamp")
  values ('u-admin', 'Ramon Dela Cruz', 'updated', 'damage_reports', 'r-3', 'Changed in another window',
    (select updated_at + interval '20 seconds' from seen));
select is(
  tests.error_of('u-admin', format($$select public.record_assessment('r-3', 'electrical', false, 1, 1, 1, 1, 1,
    'low', 'low', null, %L::timestamptz)$$, (select updated_at from seen))),
  'You changed this report somewhere else after you opened it here. The latest details are shown now: check them, then save again.',
  '…or that it was the same person, elsewhere'
);
select is(
  tests.attempt('u-admin', format($$select public.record_assessment('r-3', 'carpentry', false, 4, 2, 2, 2, 2.4,
    'medium', 'high', null, %L::timestamptz)$$, (select updated_at from seen))),
  'ok',
  'sending again what is already saved is not a conflict: an answer lost on the way is not a second decision'
);
select is(
  tests.attempt('u-admin', format($$select public.record_assessment('r-3', 'electrical', false, 1, 1, 1, 1, 1,
    'low', 'low', null, %L::timestamptz)$$,
    (select updated_at from public.damage_reports where id = 'r-3'))),
  'ok',
  'with the latest version read, the review is saved'
);
select is(
  tests.attempt('u-admin', $$select public.record_assessment('r-3', 'carpentry', false, 2, 2, 2, 2, 2,
    'medium', 'medium')$$),
  'ok',
  'a console from before this check, which names no version, still saves'
);
select is(
  tests.attempt('u-req', format($$select public.record_assessment('r-3', 'carpentry', false, 1, 1, 1, 1, 1,
    'low', 'critical', 'Mine is urgent.', %L::timestamptz)$$, (select updated_at from seen))),
  'PT403',
  'and none of it lets a requestor set the official priority of their own report'
);

-- ------------------------------------------------- who may call what

select ok(
  has_function_privilege('authenticated', 'app.record_assessment(text, text, boolean, integer, integer, integer, integer, double precision, text, text, text, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'app.record_assessment(text, text, boolean, integer, integer, integer, integer, double precision, text, text, text, timestamptz)', 'execute'),
  'the review is for signed-in callers, who are then checked for being administrators'
);
select ok(
  not has_function_privilege('authenticated', 'app.sweep_tool_requests()', 'execute'),
  'and this migration opened nothing else: the scheduler''s sweep is still not a signed-in person''s'
);

select * from finish();
rollback;
