-- Deleting and archiving from the console's lists (2026-11-08): only an
-- administrator, never what something open depends on, always audited,
-- and nothing deleted takes part in anything new.

begin;
select tests.create_fixtures();
select plan(37);

-- ------------------------------------------------------------ tools

select is(
  tests.attempt('u-tech', $$select public.delete_tool('tl-1')$$),
  'PT403',
  'a technician does not delete tools'
);
select is(
  tests.error_of('u-admin', $$select public.delete_tool('tl-1')$$),
  'Multimeter is on loan to Marcus Wright. Check it in first.',
  'a tool out on loan is kept'
);
update public.tool_loans set returned_at = now(), condition_on_return = 'good' where id = 'lo-1';
update public.tools set status = 'available', current_holder_id = null, current_loan_id = null where id = 'tl-1';
select is(
  tests.attempt('u-admin', $$select public.delete_tool('tl-1')$$),
  'ok',
  'back on the shelf, an administrator deletes it'
);
select is(
  (select array[(t.deleted_at is not null)::text,
                (select count(*)::text from public.tool_loans l where l.tool_id = 'tl-1'),
                (select description from public.audit_logs where entity_type = 'tools' and entity_id = 'tl-1')]
     from public.tools t where t.id = 'tl-1'),
  array['true', '1', 'Deleted Multimeter (TL-0001) from the tools'],
  '…it is marked deleted, its loan history stays, and it is audited'
);
select is(
  tests.attempt('u-admin', $$select public.delete_tool('tl-1')$$)
    || (select count(*)::text from public.audit_logs where entity_id = 'tl-1'),
  'ok1',
  'deleting it again does nothing'
);
select is(
  tests.error_of('u-tech', $$select public.borrow_tool('tl-1', 'u-tech')$$),
  'Multimeter has been deleted.',
  'a deleted tool cannot be borrowed'
);
select is(
  tests.attempt('u-admin', $$select public.set_tool_status('tl-1', 'inRepair')$$),
  'PT404',
  'nor sent to repair'
);
select is(
  tests.attempt('u-admin', $$select public.create_tool('TL-0001', 'Multimeter (new)', 'good', 'TOOL-TL-0001')$$),
  'ok',
  'its tool ID and code are free for another tool'
);

-- ------------------------------------------------------------ rooms, equipment

select is(
  tests.error_of('u-admin', $$select public.delete_facility('f-1')$$),
  'Engineering Building, Room 101 has 3 open reports. Finish, reject or merge them first.',
  'a room with open reports is kept'
);
update public.damage_reports set status = 'rejected' where facility_id = 'f-1' and status <> 'completed';
select is(
  tests.error_of('u-admin', $$select public.delete_facility('f-1')$$),
  'Engineering Building, Room 101 still has 1 piece of equipment. Delete it or move it to another room first.',
  'and one with equipment in it'
);
select is(
  tests.attempt('u-tech', $$select public.delete_asset('a-1')$$),
  'PT403',
  'a technician does not delete equipment'
);
select is(
  tests.attempt('u-admin', $$select public.delete_asset('a-1')$$),
  'ok',
  'an administrator deletes the equipment'
);
select is(
  tests.attempt('u-admin', $$select public.delete_facility('f-1')$$),
  'ok',
  'then the room'
);
select is(
  (select array[(f.deleted_at is not null)::text,
                (select count(*)::text from public.damage_reports r where r.facility_id = 'f-1'),
                (select description from public.audit_logs where entity_type = 'facilities' and entity_id = 'f-1'),
                (select description from public.audit_logs where entity_type = 'assets' and entity_id = 'a-1')]
     from public.facilities f where f.id = 'f-1'),
  array['true', '4', 'Deleted Engineering Building, Room 101', 'Deleted Ceiling Fan'],
  '…both marked deleted and audited; the reports about the room still name it'
);
select is(
  tests.error_of('u-req', $$select public.submit_report('r-new', 'Broken window', 'Glass cracked.', 'high',
    facility_id => 'f-1', facility_name => 'Engineering Building')$$),
  'That room has been deleted.',
  'no new report against a deleted room'
);
select is(
  tests.error_of('u-admin', $$select public.create_asset('a-new', 'Projector', 'f-1', 'good', null, null, 'AST-NEW')$$),
  'That room has been deleted.',
  'no equipment added to it'
);
select is(
  tests.attempt('u-admin', $$select public.set_facility_active('f-1', false)$$),
  'PT404',
  'and it changes no more'
);
select is(
  (select app.qr_code_owner('FAC-F-1')) is null and (select app.qr_code_owner('AST-A-1')) is null,
  true,
  'their codes are free'
);
select is(
  tests.attempt('u-admin', $$select public.delete_facility('f-2')$$),
  'ok',
  'a room nothing depends on is deleted straight away'
);

-- ------------------------------------------------------------ accounts

select is(
  tests.attempt('u-tech', $$select public.delete_account('u-pending')$$),
  'PT403',
  'a technician does not delete accounts'
);
select is(
  tests.error_of('u-admin', $$select public.delete_account('u-admin')$$),
  'You cannot delete your own account. Ask another administrator.',
  'an administrator cannot delete their own'
);
select is(
  tests.error_of('u-admin', $$select public.delete_account('u-tech')$$),
  'Marcus Wright is assigned to 1 open work order. Reassign it first.',
  'a technician with open work is kept'
);
update public.work_orders set status = 'completed' where id = 'w-2';
select is(
  tests.error_of('u-admin', $$select public.delete_account('u-tech2')$$),
  'Juan Luna still has Pipe Wrench on loan. Check it in first.',
  'and one with a tool out'
);
select is(
  tests.error_of('u-admin', $$select public.delete_account('u-req')$$),
  'Maria Santos has records in GSUhub (reports, work or history), so the account stays to keep them. Deactivate it instead.',
  'an account with records is kept, to be deactivated'
);
select is(
  (select count(*)::int from public.users where id = 'u-req')
    + (select count(*)::int from public.notifications where recipient_id = 'u-req'),
  2,
  '…and nothing of it was removed'
);
select is(
  tests.attempt('u-admin', $$select public.delete_account('u-pending')$$),
  'ok',
  'a sign-up with no records is deleted'
);
select is(
  (select count(*)::int from public.users where id = 'u-pending'),
  0,
  '…its profile is gone'
);
select is(
  (select description from public.audit_logs where entity_type = 'users' and entity_id = 'u-pending'),
  'Deleted the account of Liza Tan (pending@test.ph)',
  '…and it is audited'
);

-- ------------------------------------------------------------ archiving

select is(
  tests.attempt('u-tech', $$select public.set_report_archived('r-4', true)$$),
  'PT403',
  'a technician does not archive'
);
select is(
  tests.error_of('u-admin', $$select public.set_report_archived('r-4', true)$$),
  '#R-4 is completed. Only a closed, merged or rejected report can be archived.',
  'a report not yet closed stays in the lists'
);
update public.damage_reports set status = 'closed' where id = 'r-4';
select is(
  tests.attempt('u-admin', $$select public.set_report_archived('r-4', true)$$),
  'ok',
  'a closed report is archived'
);
select is(
  (select array[(archived_at is not null)::text, status,
                (select description from public.audit_logs where entity_id = 'r-4' order by "timestamp" desc limit 1)]
     from public.damage_reports where id = 'r-4'),
  array['true', 'closed', 'Archived report #R-4'],
  '…its status is untouched, and it is audited'
);
select is(
  tests.attempt('u-admin', $$select public.set_report_archived('r-4', false)$$),
  'ok',
  'and it can be restored'
);
select is(
  (select array[(archived_at is null)::text,
                (select description from public.audit_logs where entity_id = 'r-4'
                   and description like 'Restored%')]
     from public.damage_reports where id = 'r-4'),
  array['true', 'Restored report #R-4 from the archive'],
  '…back in the lists, and audited'
);
select is(
  tests.attempt('u-admin', $$select public.set_work_order_archived('w-1', true)$$),
  'PT409',
  'a work order still in progress stays on the board'
);
select is(
  tests.attempt('u-admin', $$select public.set_work_order_archived('w-2', true)$$),
  'ok',
  'a completed one is archived'
);
select is(
  (select array[(archived_at is not null)::text, status,
                (select description from public.audit_logs where entity_id = 'w-2' order by "timestamp" desc limit 1)]
     from public.work_orders where id = 'w-2'),
  array['true', 'completed', 'Archived work order #W-2'],
  '…with its status untouched, and audited'
);

select * from finish();
rollback;
