-- Tools (Objective 1, M4): the register, repair and retirement, borrowing
-- and returning.

begin;
select tests.create_fixtures();
select plan(24);

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

select is(
  tests.query_as('u-tech2', $$select (public.borrow_tool('tl-3', 'u-tech2', 'w-2')).borrowed_by$$),
  'u-tech2',
  'a technician borrows a tool for their work, and gets the loan'
);
select is(
  (select array[t.status, t.current_holder_id, (t.current_loan_id = l.id)::text, l.condition_on_borrow, a.description]
     from public.tools t join public.tool_loans l on l.tool_id = t.id join public.audit_logs a on a.entity_id = l.id
     where t.id = 'tl-3'),
  array['borrowed', 'u-tech2', 'true', 'good', 'Borrowed Step Ladder for #W-2'],
  '…the tool and its loan agree, and the loan is audited'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool('tl-3', 'u-tech')$$),
  'Step Ladder cannot be borrowed: it is borrowed.',
  'a tool out on loan is not lent again'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool('tl-5', 'u-tech')$$),
  'Old Saw cannot be borrowed: it is retired.',
  'nor a retired one'
);
select is(
  tests.attempt('u-tech', $$select public.borrow_tool('tl-4', 'u-tech2')$$),
  'PT403',
  'a technician borrows for themselves only'
);
select is(
  tests.query_as('u-admin', $$select (public.borrow_tool('tl-4', 'u-tech')).borrowed_by$$),
  'u-tech',
  'an administrator checks a tool out to a technician'
);
select is(
  (select a.description from public.audit_logs a join public.tool_loans l on l.id = a.entity_id where l.tool_id = 'tl-4'),
  'Checked out Pipe Cutter to Marcus Wright',
  '…which says who it went to'
);
select is(
  tests.attempt('u-admin', $$select public.borrow_tool('tl-1', 'u-req')$$),
  'PT403',
  'but never to someone who is not maintenance personnel'
);

-- ---------------------------------------------------------------- returning

select is(
  tests.attempt('u-tech', format($$select public.return_tool(%L, 'good')$$,
    (select id from public.tool_loans where tool_id = 'tl-3'))),
  'PT403',
  'a technician cannot return someone else''s loan'
);
select is(
  tests.attempt('u-tech2', format($$select public.return_tool(%L, 'poor', 'A rung is cracked')$$,
    (select id from public.tool_loans where tool_id = 'tl-3'))),
  'ok',
  'the borrower returns the tool'
);
select is(
  (select array[t.status, t.condition, coalesce(t.current_holder_id, '-'), l.condition_on_return, l.notes, a.description]
     from public.tools t join public.tool_loans l on l.tool_id = t.id
     join public.audit_logs a on a.entity_id = l.id and a.action = 'updated'
     where t.id = 'tl-3'),
  array['inRepair', 'poor', '-', 'poor', 'A rung is cracked', 'Returned Step Ladder in poor condition'],
  '…back in poor condition it goes to repair, not to the next technician'
);
select is(
  tests.attempt('u-admin', $$select public.return_tool(null, 'good')$$),
  'PT404',
  'a loan that is not there is not found, said plainly'
);
select is(
  tests.error_of('u-admin', format($$select public.return_tool(%L, 'good')$$,
    (select id from public.tool_loans where tool_id = 'tl-3'))),
  'Step Ladder has already been returned.',
  'a loan is closed once'
);

select * from finish();
rollback;
