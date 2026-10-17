-- Accomplishment reports (Objective 1, M4): filing one deducts the
-- materials it used, together or not at all; reviewing it signs the work
-- off or sends it back.

begin;
select tests.create_fixtures();
select plan(25);

-- i-1 holds 20 units; w-1 is in progress, assigned to u-tech, with 2 units
-- recorded as used.

select is(
  tests.attempt('u-tech', $$select public.submit_accomplishment('ac-new', 'w-1', '  Replaced the ballast. ',
    array['accomplishment_reports/u-tech/ac-new/after.jpg'],
    '[{"inventoryItemId":"i-1","itemName":"LED Bulbs","quantityUsed":2,"unitOfMeasurement":"units"}]')$$),
  'ok',
  'the technician files the accomplishment report'
);
select is(
  (select array[completion_notes, inventory_deducted::text, jsonb_array_length(materials_used)::text]
     from public.accomplishment_reports where id = 'ac-new'),
  array['Replaced the ballast.', 'true', '1'],
  '…with its notes, photos and materials'
);
select is(
  (select quantity_available from public.inventory_items where id = 'i-1'),
  18::double precision,
  '…and the materials come off the stock'
);
select is(
  (select array[type, quantity::text, quantity_before::text, quantity_after::text, performed_by_name, work_order_id]
     from public.inventory_transactions where accomplishment_report_id = 'ac-new'),
  array['consumption', '2', '20', '18', 'Marcus Wright', 'w-1'],
  '…through a ledger entry that says why'
);
select is(
  (select array[w.status, r.status, (select count(*)::text from public.work_order_materials_used where work_order_id = 'w-1')]
     from public.work_orders w, public.damage_reports r where w.id = 'w-1' and r.id = 'r-1'),
  array['forReview', 'forReview', '0'],
  '…the work goes for review, and the recorded line has done its job'
);
select is(
  (select description from public.audit_logs where entity_id = 'ac-new'),
  'Accomplishment report filed for #W-1',
  '…and the filing is audited'
);
select is(
  tests.attempt('u-tech', $$select public.submit_accomplishment('ac-new', 'w-1', 'Again.', array['x.jpg'],
    '[{"inventoryItemId":"i-1","itemName":"LED Bulbs","quantityUsed":2,"unitOfMeasurement":"units"}]')$$),
  'ok',
  'filing again under the same id is a retry…'
);
select is(
  (select quantity_available from public.inventory_items where id = 'i-1'),
  18::double precision,
  '…which deducts nothing twice'
);

-- Refusals.
insert into public.work_orders (id, report_ids, title, description, category, priority, status, assigned_personnel_ids, created_by) values
  ('w-3', array['r-3'], 'Broken chair', 'A leg.', 'carpentry', 'low', 'inProgress', array['u-tech'], 'u-admin');
update public.damage_reports set status = 'inProgress', work_order_id = 'w-3' where id = 'r-3';
select is(
  tests.error_of('u-tech', $$select public.submit_accomplishment('ac-big', 'w-3', 'Used a lot.', array['x.jpg'],
    '[{"inventoryItemId":"i-1","itemName":"LED Bulbs","quantityUsed":100,"unitOfMeasurement":"units"}]')$$),
  'Not enough LED Bulbs in stock: 18 units left, 100 recorded as used.',
  'not more than is in stock'
);
select is(
  (select array[w.status, (select count(*)::text from public.accomplishment_reports where id = 'ac-big')]
     from public.work_orders w where w.id = 'w-3'),
  array['inProgress', '0'],
  '…and then nothing at all happens'
);
select is(
  tests.error_of('u-tech', $$select public.submit_accomplishment('ac-gone', 'w-3', 'Used it.', array['x.jpg'],
    '[{"inventoryItemId":"i-gone","itemName":"Old Tape","quantityUsed":1,"unitOfMeasurement":"rolls"}]')$$),
  'Old Tape is no longer in the inventory. Remove it from the materials used.',
  'not a material that has left the inventory'
);
select is(
  tests.error_of('u-tech2', $$select public.submit_accomplishment('ac-p', 'w-2', 'Done.', array['x.jpg'])$$),
  'Start the work before marking it complete.',
  'not work that has not started'
);
select is(
  tests.error_of('u-tech', $$select public.submit_accomplishment('ac-o', 'w-2', 'Done.', array['x.jpg'])$$),
  'This work order is not assigned to you.',
  'not someone else''s work'
);
select is(
  tests.attempt('u-tech', $$select public.submit_accomplishment('ac-n', 'w-3', 'Done.', array[]::text[])$$),
  'PT422',
  'not without a photo of the finished work'
);
select is(
  tests.attempt('u-req', $$select public.submit_accomplishment('ac-r', 'w-3', 'Done.', array['x.jpg'])$$),
  'PT403',
  'a requestor files no accomplishment reports'
);

-- ---------------------------------------------------------------- review

select is(
  tests.attempt('u-admin', $$select public.review_accomplishment('ac-new', true)$$),
  'ok',
  'an administrator signs the work off'
);
select is(
  (select array[w.status, r.status, a.reviewed_by]
     from public.work_orders w, public.damage_reports r, public.accomplishment_reports a
     where w.id = 'w-1' and r.id = 'r-1' and a.id = 'ac-new'),
  array['completed', 'completed', 'u-admin'],
  '…the work order and its report are completed'
);
select is(
  (select string_agg(recipient_id || ':' || title, ',' order by recipient_id collate "C")
     from public.notifications where related_entity_id = 'w-1' and title = 'Work signed off'),
  'u-tech:Work signed off,u-tech-off:Work signed off',
  '…every technician on it is told'
);
select is(
  (select description from public.audit_logs where entity_id = 'ac-new' and action = 'updated'),
  'Accomplishment report approved; #W-1 signed off',
  '…and the sign-off is audited'
);
select is(
  tests.error_of('u-admin', $$select public.review_accomplishment('ac-new', false)$$),
  'This accomplishment report was reviewed already.',
  'a report is reviewed once'
);

insert into public.work_orders (id, report_ids, title, description, category, priority, status, assigned_personnel_ids, created_by) values
  ('w-4', array['r-4b'], 'Loose cover', 'Socket.', 'electrical', 'low', 'forReview', array['u-tech2'], 'u-admin');
insert into public.damage_reports (id, reporter_id, reporter_name, title, description, requestor_priority, status, work_order_id) values
  ('r-4b', 'u-req2', 'Ana Gomez', 'Loose cover', 'The socket cover is loose.', 'low', 'forReview', 'w-4');
insert into public.accomplishment_reports (id, work_order_id, submitted_by, completion_notes) values
  ('ac-4', 'w-4', 'u-tech2', 'Tightened.');
select is(
  tests.attempt('u-admin', $$select public.review_accomplishment('ac-4', false, '  The cover still moves. ')$$),
  'ok',
  'an administrator sends work back'
);
select is(
  (select array[w.status, w.admin_notes, r.status]
     from public.work_orders w, public.damage_reports r where w.id = 'w-4' and r.id = 'r-4b'),
  array['inProgress', 'The cover still moves.', 'inProgress'],
  '…with a note for the technician, and the work reopens'
);
select is(
  (select string_agg(title, ',' order by title) from public.notifications
     where related_entity_id in ('w-4', 'r-4b')),
  'Work resumed,Work sent back',
  '…the technician and the requestor are both told'
);
select is(
  tests.error_of('u-admin', $$select public.review_accomplishment('ac-2', true)$$),
  'This work order is Pending, not waiting for sign-off.',
  'only work waiting for sign-off is reviewed'
);
select is(
  tests.attempt('u-tech2', $$select public.review_accomplishment('ac-4', true)$$),
  'PT403',
  'a technician cannot sign off their own work'
);

select * from finish();
rollback;
