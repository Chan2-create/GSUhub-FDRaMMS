-- Accomplishment reports (Objective 1, M4): AccomplishmentReportRepositoryImpl.
--
-- Filing one carries the system's most important invariant (§3.4): the
-- completion report and the stock deducted for the materials it used are
-- written together or not at all. The deductions are ledger entries; the
-- ledger moves the stock (supabase/migrations/*_stock_ledger.sql).

-- The technician assigned files the report for work in progress (5.B):
-- notes, one to five photos, and the materials used, each deducted from
-- stock. The work order moves to for review. Filing again under the same
-- id is a retry and does nothing — nothing is deducted twice.
--
-- [_materials] is the report's list as the app keeps it:
-- [{"inventoryItemId", "itemName", "quantityUsed", "unitOfMeasurement"}].
create or replace function app.submit_accomplishment(
  _id text,
  _work_order_id text,
  _completion_notes text,
  _photo_urls text[],
  _materials jsonb default '[]'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  caller_name text := (select u.full_name from public.users u where u.id = (select app.uid()));
  clean_notes text := btrim(coalesce(_completion_notes, ''));
  photos text[] := coalesce(_photo_urls, '{}');
  materials jsonb := coalesce(_materials, '[]');
  existing_author text;
  work_order public.work_orders;
  line jsonb;
  item public.inventory_items;
  used double precision;
begin
  if not (select app.is_personnel()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;

  select a.submitted_by into existing_author from public.accomplishment_reports a where a.id = _id;
  if found then
    if existing_author = caller then
      return;
    end if;
    perform app.refuse('PT409', 'This report could not be filed. Please try again.');
  end if;

  if clean_notes = '' then
    perform app.refuse('PT422', 'Describe the work that was done.');
  end if;
  if char_length(clean_notes) > 2000 then
    perform app.refuse('PT422', 'Keep the notes to 2000 characters.');
  end if;
  if cardinality(photos) < 1 then
    perform app.refuse('PT422', 'Add at least one photo of the finished work.');
  end if;
  if cardinality(photos) > 5 then
    perform app.refuse('PT422', 'Attach at most 5 photos.');
  end if;
  if jsonb_typeof(materials) <> 'array' then
    perform app.refuse('PT422', 'The materials used could not be read.');
  end if;

  select * into work_order from public.work_orders w where w.id = _work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || _work_order_id);
  end if;
  if not (caller = any (work_order.assigned_personnel_ids)) then
    perform app.refuse('PT409', 'This work order is not assigned to you.');
  end if;
  if work_order.status <> 'inProgress' then
    perform app.refuse('PT409', case
      when work_order.status = 'pending' then 'Start the work before marking it complete.'
      else 'This work order is ' || app.work_order_status_title(work_order.status)
        || ', so it cannot be submitted again.'
    end);
  end if;

  -- Every material checked before anything is written, in the app's words.
  for line in select value from jsonb_array_elements(materials) loop
    used := (line ->> 'quantityUsed')::double precision;
    if used is null or used <= 0 then
      perform app.refuse('PT422', 'Enter how much ' || coalesce(line ->> 'itemName', 'material') || ' was used.');
    end if;
    select * into item from public.inventory_items i where i.id = line ->> 'inventoryItemId' for update;
    if not found then
      perform app.refuse('PT404', coalesce(line ->> 'itemName', 'A material')
        || ' is no longer in the inventory. Remove it from the materials used.');
    end if;
    if item.quantity_available - used < 0 then
      perform app.refuse('PT409', 'Not enough ' || coalesce(line ->> 'itemName', item.name) || ' in stock: '
        || app.format_amount(item.quantity_available) || ' ' || coalesce(line ->> 'unitOfMeasurement', item.unit_of_measurement)
        || ' left, ' || app.format_amount(used) || ' recorded as used.');
    end if;
  end loop;

  -- The work order and its reports move first: a report that cannot
  -- follow refuses the whole filing before any stock moves.
  perform app.move_work_order(_work_order_id, 'forReview');

  insert into public.accomplishment_reports (id, work_order_id, submitted_by, completion_notes,
    photo_urls, materials_used, inventory_deducted)
  values (_id, _work_order_id, caller, clean_notes, photos, materials, jsonb_array_length(materials) > 0);

  for line in select value from jsonb_array_elements(materials) loop
    insert into public.inventory_transactions (inventory_item_id, item_name, type, quantity,
      work_order_id, accomplishment_report_id, notes, performed_by, performed_by_name)
    values (line ->> 'inventoryItemId', line ->> 'itemName', 'consumption',
      (line ->> 'quantityUsed')::double precision, _work_order_id, _id,
      'Deducted on accomplishment report submission', caller, caller_name);
    -- The recorded line has done its job once deducted.
    delete from public.work_order_materials_used m
    where m.work_order_id = _work_order_id and m.inventory_item_id = line ->> 'inventoryItemId';
  end loop;

  perform app.audit('created', 'accomplishment_reports', _id,
    'Accomplishment report filed for ' || app.display_id(_work_order_id, 'WO'),
    jsonb_build_object(
      'workOrderId', _work_order_id,
      'photos', cardinality(photos),
      'materials', coalesce((
        select jsonb_agg(jsonb_build_object('item', m ->> 'inventoryItemId',
          'quantity', (m ->> 'quantityUsed')::double precision))
        from jsonb_array_elements(materials) m
      ), '[]')
    ));
end;
$$;

-- An administrator signs the work off, or sends it back with a note shown
-- at the top of the work order on the technician's phone (5.B).
create or replace function app.review_accomplishment(
  _report_id text,
  _approve boolean,
  _note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  report public.accomplishment_reports;
  work_order public.work_orders;
  reason text := app.blank_to_null(_note);
  technician text;
begin
  perform app.require_admin();
  select * into report from public.accomplishment_reports a where a.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No accomplishment report ' || _report_id);
  end if;
  if report.reviewed_at is not null then
    perform app.refuse('PT409', 'This accomplishment report was reviewed already.');
  end if;
  select * into work_order from public.work_orders w where w.id = report.work_order_id for update;
  if not found then
    perform app.refuse('PT404', 'No work order ' || report.work_order_id);
  end if;
  if work_order.status <> 'forReview' then
    perform app.refuse('PT409', 'This work order is ' || app.work_order_status_title(work_order.status)
      || ', not waiting for sign-off.');
  end if;

  update public.accomplishment_reports a
  set reviewed_by = (select app.uid()), reviewed_at = now()
  where a.id = _report_id;
  if not _approve and reason is not null then
    update public.work_orders w set admin_notes = reason where w.id = work_order.id;
  end if;

  perform app.move_work_order(work_order.id, case when _approve then 'completed' else 'inProgress' end);

  foreach technician in array work_order.assigned_personnel_ids loop
    if _approve then
      -- PersonnelNotice.signedOff
      perform app.notify(technician, 'maintenanceCompleted', 'Work signed off',
        'GSU signed off "' || work_order.title || '" as completed.', 'work_orders', work_order.id);
    else
      -- PersonnelNotice.sentBack
      perform app.notify(technician, 'statusUpdate', 'Work sent back',
        'GSU reviewed your accomplishment report for "' || work_order.title
          || '" and sent the work back to be finished.', 'work_orders', work_order.id);
    end if;
  end loop;

  perform app.audit('updated', 'accomplishment_reports', _report_id,
    case when _approve
      then 'Accomplishment report approved; ' || app.display_id(work_order.id, 'WO') || ' signed off'
      else 'Accomplishment report sent back; ' || app.display_id(work_order.id, 'WO') || ' reopened'
    end,
    jsonb_build_object('approved', _approve)
      || case when reason is not null then jsonb_build_object('note', reason) else '{}' end);
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.submit_accomplishment(
  id text, work_order_id text, completion_notes text, photo_urls text[],
  materials jsonb default '[]'
)
returns void language sql security invoker set search_path = ''
as $$ select app.submit_accomplishment(id, work_order_id, completion_notes, photo_urls, materials); $$;

create or replace function public.review_accomplishment(report_id text, approve boolean, note text default null)
returns void language sql security invoker set search_path = ''
as $$ select app.review_accomplishment(report_id, approve, note); $$;

revoke execute on function
  public.submit_accomplishment(text, text, text, text[], jsonb),
  public.review_accomplishment(text, boolean, text)
from public, anon;
grant execute on function
  public.submit_accomplishment(text, text, text, text[], jsonb),
  public.review_accomplishment(text, boolean, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
