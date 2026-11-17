-- Tool requests (2026-11-16): an administrator asks a technician to
-- collect a tool, or to return one; nothing moves until the technician
-- scans the tool and confirms. Covers the brief's eight scenarios: a
-- checkout confirmed, a return confirmed, the wrong tool scanned, another
-- technician confirming, a checkout left unconfirmed, a return overdue, a
-- request cancelled, and the history kept.

begin;
select tests.create_fixtures();
select plan(43);

insert into public.tools (id, tool_code, name, status, condition, qr_code) values
  ('tl-6', 'TL-0006', 'Hammer Drill', 'available', 'good', 'TOOL-TL-0006'),
  ('tl-7', 'TL-0007', 'Torque Wrench', 'available', 'fair', 'TOOL-TL-0007');

create temp table ids (name text primary key, id text);

-- ---------------------------------------------------------------- Check Out

select is(
  tests.attempt('u-tech', $$select public.request_tool_checkout('tl-6', 'u-tech', now(), null, 'Mine')$$),
  'PT403',
  'only an administrator starts a checkout'
);

insert into ids values ('co', tests.query_as('u-admin', $$select public.request_tool_checkout(
  'tl-6', 'u-tech', now() + interval '1 hour', now() + interval '2 days',
  'Ceiling fan repair', 'Bring the charger back too.', 'w-1')$$));

select is(
  (select array[t.status, r.kind, r.status, r.personnel_id, r.requested_by, r.work_order_id,
                (r.expires_at = r.checkout_at + interval '24 hours')::text]
     from public.tool_requests r join public.tools t on t.id = r.tool_id
     where r.id = (select id from ids where name = 'co')),
  array['reserved', 'checkOut', 'pending', 'u-tech', 'u-admin', 'w-1', 'true'],
  'Check Out reserves the tool and waits for the technician, lapsing a day after the agreed time'
);
select is(
  (select count(*)::int from public.tool_loans where tool_id = 'tl-6'),
  0,
  '…it lends nothing yet'
);
select is(
  (select a.description from public.audit_logs a where a.entity_id = (select id from ids where name = 'co')),
  'Asked Marcus Wright to collect Hammer Drill (TL-0006)',
  '…and is audited'
);
select ok(
  (select n.title = 'Collect Hammer Drill (TL-0006)'
          and position('Purpose: Ceiling fan repair.' in n.body) > 0
          and position('Bring the charger back too.' in n.body) > 0
          and position('scan its QR code' in n.body) > 0
          and n.related_entity_type = 'tool_requests'
     from public.notifications n
     where n.recipient_id = 'u-tech' and n.type = 'toolCheckoutRequested'),
  'the technician is told what to collect, when, why, and to scan it'
);
select is(
  tests.error_of('u-admin', $$select public.request_tool_checkout('tl-6', 'u-tech2', now(), null, 'Twice')$$),
  'Hammer Drill cannot be checked out: it is reserved.',
  'a reserved tool is not asked of anyone else'
);
select is(
  tests.error_of('u-tech2', $$select public.borrow_tool_by_scan('tl-6', 'TOOL-TL-0006')$$),
  'Hammer Drill is reserved for Marcus Wright.',
  '…nor taken off the shelf by another technician'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool_by_scan('tl-6', 'TOOL-TL-0006')$$),
  'GSU has checked Hammer Drill out to you. Confirm that request instead.',
  '…and the technician it is for confirms the request rather than borrowing it'
);

select is(
  tests.attempt('u-tech2', format($$select public.confirm_tool_checkout(%L, 'TOOL-TL-0006')$$,
    (select id from ids where name = 'co'))),
  'PT403',
  'another technician cannot confirm it, even with the tool in hand'
);
select is(
  tests.error_of('u-tech', format($$select public.confirm_tool_checkout(%L, 'TOOL-TL-0001')$$,
    (select id from ids where name = 'co'))),
  'That is Multimeter (TL-0001), not Hammer Drill (TL-0006). Scan the QR code on Hammer Drill.',
  'scanning the wrong tool confirms nothing'
);
select is(
  (select r.status || ' / ' || t.status from public.tool_requests r join public.tools t on t.id = r.tool_id
   where r.id = (select id from ids where name = 'co')),
  'pending / reserved',
  'until it is confirmed, it stays Pending Confirmation'
);
select is(
  tests.visible('u-tech2', 'tool_requests') || ' | ' || (tests.visible('u-tech', 'tool_requests') = (select id from ids where name = 'co'))::text,
  ' | true',
  'a technician sees only the requests made of them'
);

select is(
  tests.query_as('u-tech', format($$select (public.confirm_tool_checkout(%L, ' tool-tl-0006 ')).borrowed_by$$,
    (select id from ids where name = 'co'))),
  'u-tech',
  'scanning the right tool confirms receipt, and opens the loan'
);
select is(
  (select array[t.status, t.current_holder_id, (t.current_loan_id = r.loan_id)::text, r.status,
                (r.confirmed_at is not null)::text, l.work_order_id, (l.expected_return_at = r.due_at)::text]
     from public.tool_requests r join public.tools t on t.id = r.tool_id join public.tool_loans l on l.id = r.loan_id
     where r.id = (select id from ids where name = 'co')),
  array['borrowed', 'u-tech', 'true', 'confirmed', 'true', 'w-1', 'true'],
  '…the tool is Borrowed, by them, for the work order, due back when the request said'
);
select is(
  (select string_agg(n.title, ' | ') from public.notifications n
   where n.recipient_id = 'u-admin' and n.type = 'toolCheckoutConfirmed'),
  'Marcus Wright received Hammer Drill',
  '…and the administrators are told'
);
select is(
  tests.error_of('u-tech', format($$select public.confirm_tool_checkout(%L, 'TOOL-TL-0006')$$,
    (select id from ids where name = 'co'))),
  'You have already confirmed receiving Hammer Drill.',
  'a checkout is confirmed once'
);

select is(
  tests.error_of('u-admin', $$select public.request_tool_checkout('tl-7', 'u-req', now(), null, 'Test')$$)
    || ' / ' || tests.error_of('u-admin', $$select public.request_tool_checkout('tl-7', 'u-tech-off', now(), null, 'Test')$$),
  'Pick an active technician to check the tool out to. / Pick an active technician to check the tool out to.',
  'a tool is checked out to an active technician only'
);
select is(
  tests.error_of('u-admin', $$select public.request_tool_checkout('tl-7', 'u-tech', now(), null, '  ')$$),
  'Say what the tool is for.',
  '…for a stated purpose'
);
select is(
  tests.error_of('u-admin', $$select public.request_tool_checkout('tl-7', 'u-tech', now() + interval '2 hours', now() + interval '1 hour', 'Test')$$),
  'The expected return must be after the checkout.',
  '…and back after it goes out'
);

-- ---------------------------------------------------------------- cancelling

insert into ids values ('cancel', tests.query_as('u-admin', $$select public.request_tool_checkout(
  'tl-7', 'u-tech2', now(), null, 'Pump repair')$$));
select is(
  tests.attempt('u-tech2', format($$select public.cancel_tool_request(%L)$$, (select id from ids where name = 'cancel'))),
  'PT403',
  'a technician cannot cancel a request'
);
select is(
  tests.attempt('u-admin', format($$select public.cancel_tool_request(%L)$$, (select id from ids where name = 'cancel'))),
  'ok',
  'an administrator cancels a checkout still waiting'
);
select is(
  (select array[r.status, r.closed_by, t.status] from public.tool_requests r join public.tools t on t.id = r.tool_id
   where r.id = (select id from ids where name = 'cancel')),
  array['cancelled', 'u-admin', 'available'],
  '…the reservation is released'
);
select is(
  (select n.title from public.notifications n where n.recipient_id = 'u-tech2' and n.type = 'toolRequestCancelled'),
  'Cancelled: checkout of Torque Wrench',
  '…and the technician is told'
);
select is(
  tests.error_of('u-admin', format($$select public.cancel_tool_request(%L)$$, (select id from ids where name = 'cancel')))
    || ' / ' || tests.error_of('u-tech2', format($$select public.confirm_tool_checkout(%L, 'TOOL-TL-0007')$$,
      (select id from ids where name = 'cancel'))),
  'This request is already cancelled. / GSU cancelled this checkout of Torque Wrench.',
  'a cancelled request is neither cancelled again nor confirmed'
);

-- ---------------------------------------------------------------- Check In

select is(
  tests.attempt('u-tech', format($$select public.request_tool_return(%L, now() + interval '1 day')$$,
    (select loan_id from public.tool_requests where id = (select id from ids where name = 'co')))),
  'PT403',
  'only an administrator asks for a tool back'
);
insert into ids values ('ret', tests.query_as('u-admin', format($$select public.request_tool_return(
  %L, now() + interval '1 day', 'Please bring it to the GSU office.')$$,
  (select loan_id from public.tool_requests where id = (select id from ids where name = 'co')))));
select is(
  (select array[t.status, r.kind, r.status, r.personnel_id, (l.returned_at is null)::text]
     from public.tool_requests r join public.tools t on t.id = r.tool_id join public.tool_loans l on l.id = r.loan_id
     where r.id = (select id from ids where name = 'ret')),
  array['borrowed', 'checkIn', 'pending', 'u-tech', 'true'],
  'Check In asks for the tool back and waits: the tool is still out, Awaiting Return'
);
select ok(
  (select n.title = 'Return Hammer Drill (TL-0006)'
          and position('Please bring it to the GSU office.' in n.body) > 0
          and position('scan its QR code' in n.body) > 0
     from public.notifications n where n.recipient_id = 'u-tech' and n.type = 'toolReturnRequested'),
  'the technician is told what to return, by when, the message, and to scan it'
);
select is(
  tests.error_of('u-admin', format($$select public.request_tool_return(%L, now() + interval '2 days')$$,
    (select loan_id from public.tool_requests where id = (select id from ids where name = 'co'))))
    || ' / ' || tests.error_of('u-admin', $$select public.request_tool_return('lo-1', now() - interval '1 minute')$$),
  'A return of Hammer Drill is already requested. / Pick a return date and time that has not passed.',
  'one return request at a time, for a time still to come'
);
select is(
  tests.attempt('u-tech', format($$select public.confirm_tool_return(%L, 'TOOL-TL-0006', 'good')$$,
    (select loan_id from public.tool_requests where id = (select id from ids where name = 'co')))),
  'ok',
  'the technician scans the tool and confirms the return'
);
select is(
  (select array[t.status, coalesce(t.current_holder_id, '-'), r.status, (r.confirmed_at is not null)::text,
                (l.returned_at is not null)::text]
     from public.tool_requests r join public.tools t on t.id = r.tool_id join public.tool_loans l on l.id = r.loan_id
     where r.id = (select id from ids where name = 'ret')),
  array['available', '-', 'confirmed', 'true', 'true'],
  '…the tool is Available, the request Returned, the loan closed'
);
select ok(
  (select n.title = 'Marcus Wright returned Hammer Drill' and n.related_entity_type = 'tool_requests'
          and position('good condition' in n.body) > 0
     from public.notifications n where n.recipient_id = 'u-admin' and n.type = 'toolReturned'),
  '…and the administrators are told'
);

-- ---------------------------------------------------------------- the sweep: due, overdue

insert into ids values ('due', tests.query_as('u-admin', $$select public.request_tool_return(
  'lo-2', now() + interval '30 minutes')$$));
select app.sweep_tool_requests();
select app.sweep_tool_requests();
select is(
  (select count(*)::int from public.notifications n where n.recipient_id = 'u-tech2' and n.type = 'toolReturnDue'),
  1,
  'a return due within the hour reminds the technician, once'
);
update public.tool_requests set due_at = now() - interval '1 minute' where id = (select id from ids where name = 'due');
select app.sweep_tool_requests();
select app.sweep_tool_requests();
select is(
  (select string_agg(n.recipient_id || ':' || n.title, ' | ' order by n.recipient_id)
   from public.notifications n where n.type = 'toolOverdue'
     and n.recipient_id in ('u-admin', 'u-tech', 'u-tech2')),
  'u-admin:Overdue: Pipe Wrench | u-tech2:Overdue: Pipe Wrench',
  'a return past its time is Overdue: the administrators and the technician are told, once'
);
select is(
  (select status from public.tool_requests where id = (select id from ids where name = 'due')),
  'pending',
  '…and it still waits for the tool'
);
select is(
  tests.error_of('u-tech2', $$select public.confirm_tool_return('lo-2', 'TOOL-TL-0002', 'fair')$$),
  null,
  'a late return is confirmed like any other'
);
select ok(
  (select position('after it was due' in n.body) > 0 from public.notifications n
   where n.recipient_id = 'u-admin' and n.type = 'toolReturned' and n.title like 'Juan Luna%'),
  '…and the administrators read that it was late'
);

-- ---------------------------------------------------------------- the sweep: lapsed, still waiting

insert into ids values ('lapse', tests.query_as('u-admin', $$select public.request_tool_checkout(
  'tl-7', 'u-tech', now(), null, 'Pump repair')$$));
update public.tool_requests set expires_at = now() - interval '1 minute' where id = (select id from ids where name = 'lapse');
select is(
  tests.error_of('u-tech', format($$select public.confirm_tool_checkout(%L, 'TOOL-TL-0007')$$,
    (select id from ids where name = 'lapse'))),
  'This checkout of Torque Wrench has lapsed. Ask GSU to send it again.',
  'a checkout past its time is not confirmed, even before the sweep'
);
select app.sweep_tool_requests();
select is(
  (select array[r.status, t.status, a.actor_name, a.description]
     from public.tool_requests r join public.tools t on t.id = r.tool_id
     join public.audit_logs a on a.entity_id = r.id and a.action = 'statusChanged'
     where r.id = (select id from ids where name = 'lapse')),
  array['expired', 'available', 'GSUhub', 'The checkout of Torque Wrench (TL-0007) lapsed uncollected'],
  'the sweep lapses it, frees the tool, and audits it as GSUhub'
);
select is(
  (select string_agg(n.recipient_id || ':' || n.title, ' | ' order by n.recipient_id)
   from public.notifications n where n.type = 'toolRequestCancelled' and n.title like 'Lapsed:%'
     and n.recipient_id in ('u-admin', 'u-tech', 'u-tech2')),
  'u-admin:Lapsed: checkout of Torque Wrench | u-tech:Lapsed: checkout of Torque Wrench',
  '…telling the technician and the administrators'
);

insert into ids values ('late', tests.query_as('u-admin', $$select public.request_tool_checkout(
  'tl-7', 'u-tech', now() - interval '2 hours', now() + interval '1 day', 'Pump repair')$$));
select app.sweep_tool_requests();
select app.sweep_tool_requests();
select is(
  (select count(*)::int from public.notifications n where n.recipient_id = 'u-admin' and n.type = 'toolCheckoutPending'),
  1,
  'a checkout still waiting an hour past its time is flagged to the administrators, once'
);

-- ---------------------------------------------------------------- guards, history, the schedule

select is(
  tests.error_of('u-admin', $$select public.set_tool_status('tl-7', 'inRepair')$$)
    || ' / ' || tests.error_of('u-admin', $$select public.delete_tool('tl-7')$$),
  'Torque Wrench is waiting to be collected; cancel that checkout first. / Torque Wrench has a request waiting; cancel it first.',
  'a reserved tool is neither sent to repair nor deleted'
);
select is(
  tests.attempt('u-admin', format($$select public.cancel_tool_request(%L)$$, (select id from ids where name = 'late')))
    || tests.attempt('u-admin', $$select public.delete_tool('tl-7')$$)
    || ' / ' || tests.query_as('u-admin', $$select count(*)::text from public.tool_requests where tool_id = 'tl-7'$$),
  'okok / 3',
  'a deleted tool keeps its requests, for the history'
);
select is(
  tests.attempt('u-admin', $$select app.sweep_tool_requests()$$),
  '42501',
  'the sweep is the scheduler''s, not a signed-in person''s'
);

select * from finish();
rollback;
