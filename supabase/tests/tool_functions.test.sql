-- Tools (Objective 1, M4): the register, repair and retirement, borrowing
-- and returning.

begin;
select tests.create_fixtures();
select plan(28);

select isnt(
  tests.query_as('u-admin', $$select public.create_tool(' TL-0100 ', 'Cordless Drill', 'good', 'TOOL-TL-0100', 'Power tools', null)$$),
  null,
  'an administrator registers a tool'
);
select is(
  (select array[t.status, t.condition, a.description]
     from public.tools t, public.audit_logs a where t.tool_code = 'TL-0100' and a.entity_id = t.id),
  array['available', 'good', 'Added Cordless Drill (TL-0100) to the tools'],
  '…available, and audited'
);
select is(
  tests.error_of('u-admin', $$select public.create_tool('TL-0001', 'Another', 'good', 'TOOL-NEW')$$),
  'Another tool already has the ID TL-0001.',
  'a tool ID is one tool''s'
);
select is(
  tests.error_of('u-admin', $$select public.create_tool('TL-0200', 'Another', 'good', 'INV-I-1')$$),
  'The code INV-I-1 is already on a material.',
  'and so is a code'
);
select is(
  tests.attempt('u-tech', $$select public.create_tool('TL-0300', 'Mine', 'good', 'TOOL-MINE')$$),
  'PT403',
  'a technician does not register tools'
);

select is(
  tests.attempt('u-admin', $$select public.update_tool('tl-1', 'TL-0001', 'Multimeter', 'poor', 'TOOL-TL-0001')$$),
  'ok',
  'an administrator edits a tool that is out on loan…'
);
select is(
  (select condition from public.tools where id = 'tl-1'),
  'good',
  '…which keeps the condition it left in'
);

-- ---------------------------------------------------------------- repair and retirement

select is(
  tests.attempt('u-admin', $$select public.set_tool_status((select id from public.tools where tool_code = 'TL-0100'), 'inRepair')$$)
    || tests.attempt('u-admin', $$select public.set_tool_status((select id from public.tools where tool_code = 'TL-0100'), 'available')$$),
  'okok',
  'a tool goes to repair and comes back'
);
select is(
  (select string_agg(a.description, ' | ' order by a.description)
     from public.audit_logs a join public.tools t on t.id = a.entity_id
     where t.tool_code = 'TL-0100' and a.action = 'statusChanged'),
  'Brought Cordless Drill back from repair | Sent Cordless Drill to repair',
  '…each move audited'
);
select is(
  tests.error_of('u-admin', $$select public.set_tool_status('tl-1', 'inRepair')$$),
  'Multimeter is out with a technician; check it in first.',
  'a tool out on loan is checked in first'
);
select is(
  tests.error_of('u-admin', $$select public.set_tool_status((select id from public.tools where tool_code = 'TL-0100'), 'borrowed')$$),
  'Check a tool out to lend it.',
  'lending is a loan, not a status'
);

-- ---------------------------------------------------------------- borrowing

insert into public.tools (id, tool_code, name, status, condition, qr_code) values
  ('tl-3', 'TL-0003', 'Step Ladder', 'available', 'good', 'TOOL-TL-0003'),
  ('tl-4', 'TL-0004', 'Pipe Cutter', 'available', 'fair', 'TOOL-TL-0004'),
  ('tl-5', 'TL-0005', 'Old Saw', 'retired', 'poor', 'TOOL-TL-0005');

-- Since 2026-11-16 every hand-over is confirmed with the code scanned from
-- the tool (tool_requests.test.sql has the console's requests).

select is(
  tests.query_as('u-tech2', $$select (public.borrow_tool_by_scan('tl-3', 'TOOL-TL-0003', 'w-2')).borrowed_by$$),
  'u-tech2',
  'a technician borrows a tool for their work by scanning it, and gets the loan'
);
select is(
  (select array[t.status, t.current_holder_id, (t.current_loan_id = l.id)::text, l.condition_on_borrow, a.description]
     from public.tools t join public.tool_loans l on l.tool_id = t.id join public.audit_logs a on a.entity_id = l.id
     where t.id = 'tl-3'),
  array['borrowed', 'u-tech2', 'true', 'good', 'Borrowed Step Ladder for #W-2, confirmed by scanning it'],
  '…the tool and its loan agree, and the loan is audited'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool_by_scan('tl-3', 'TOOL-TL-0003')$$),
  'Step Ladder cannot be borrowed: it is borrowed.',
  'a tool out on loan is not lent again'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool_by_scan('tl-5', 'TOOL-TL-0005')$$),
  'Old Saw cannot be borrowed: it is retired.',
  'nor a retired one'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool_by_scan('tl-4', 'tool-tl-0003')$$),
  'That is Step Ladder (TL-0003), not Pipe Cutter (TL-0004). Scan the QR code on Pipe Cutter.',
  'the code scanned must be the tool''s own, and the refusal names what was scanned'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool_by_scan('tl-4', 'SOMETHING-ELSE')$$),
  'That code is not on Pipe Cutter (TL-0004). Scan the QR code on Pipe Cutter.',
  '…or that it is no tool at all'
);
select is(
  tests.attempt('u-admin', $$select public.borrow_tool_by_scan('tl-4', 'TOOL-TL-0004')$$),
  'PT403',
  'an administrator does not borrow tools'
);
select is(
  tests.error_of('u-admin', $$select public.borrow_tool('tl-4', 'u-tech')$$),
  'Check Out now asks the technician to collect the tool; it is theirs once they scan it. Reload the console.',
  'the old Check Out no longer lends on the spot, and says so'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool('tl-4', 'u-tech')$$)
    || ' / ' || (select status from public.tools where id = 'tl-4'),
  'Borrowing now asks you to scan the tool. Update GSUhub. / available',
  '…nor the old borrowing, and the tool stays on the shelf'
);

-- ---------------------------------------------------------------- returning

select is(
  tests.attempt('u-tech', format($$select public.confirm_tool_return(%L, 'TOOL-TL-0003', 'good')$$,
    (select id from public.tool_loans where tool_id = 'tl-3'))),
  'PT403',
  'a technician cannot return someone else''s loan'
);
select is(
  tests.error_of('u-tech', $$select public.confirm_tool_return('lo-1', 'TOOL-TL-0002', 'good')$$),
  'That is Pipe Wrench (TL-0002), not Multimeter (TL-0001). Scan the QR code on Multimeter.',
  'the borrower scans the very tool they hand back'
);
select is(
  tests.attempt('u-tech2', format($$select public.confirm_tool_return(%L, 'TOOL-TL-0003', 'poor', 'A rung is cracked')$$,
    (select id from public.tool_loans where tool_id = 'tl-3'))),
  'ok',
  'the borrower returns the tool by scanning it'
);
select is(
  (select array[t.status, t.condition, coalesce(t.current_holder_id, '-'), l.condition_on_return, l.notes, a.description]
     from public.tools t join public.tool_loans l on l.tool_id = t.id
     join public.audit_logs a on a.entity_id = l.id and a.action = 'updated'
     where t.id = 'tl-3'),
  array['inRepair', 'poor', '-', 'poor', 'A rung is cracked',
    'Returned Step Ladder in poor condition, confirmed by scanning it'],
  '…back in poor condition it goes to repair, not to the next technician'
);
select is(
  (select n.title || ' / ' || n.related_entity_type from public.notifications n
   where n.recipient_id = 'u-admin' and n.type = 'toolReturned'),
  'Juan Luna returned Step Ladder / tool_loans',
  '…and the administrators are told'
);
select is(
  tests.attempt('u-tech2', $$select public.confirm_tool_return(null, 'TOOL-TL-0003', 'good')$$),
  'PT404',
  'a loan that is not there is not found, said plainly'
);
select is(
  tests.error_of('u-tech2', format($$select public.confirm_tool_return(%L, 'TOOL-TL-0003', 'good')$$,
    (select id from public.tool_loans where tool_id = 'tl-3'))),
  'Step Ladder has already been returned.',
  'a loan is closed once'
);
select is(
  tests.error_of('u-tech', $$select public.return_tool('lo-1', 'good')$$)
    || ' / ' || tests.error_of('u-admin', $$select public.return_tool('lo-1', 'good')$$)
    || ' / ' || (select status from public.tools where id = 'tl-1'),
  'Returning now asks you to scan the tool. Update GSUhub. / Check In now asks the technician to '
    || 'return the tool; it is back once they scan it. Reload the console. / borrowed',
  'the old returns no longer close a loan, and say so'
);

select * from finish();
rollback;
