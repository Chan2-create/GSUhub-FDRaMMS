-- The stock ledger (Objective 1, item 1).
--
-- Under Firestore a technician's account could write `quantityAvailable`
-- with no ledger entry beside it: the rules could not see whether the
-- matching entry was in the same batch, and closing that gap needed a
-- Cloud Function, so the Blaze plan. Here the database closes it:
--
--   * a stock quantity changes in exactly one way: by inserting an
--     `inventory_transactions` row. A trigger on that insert locks the
--     material, works out the balance before and after from the stored
--     quantity (never from anything the caller sends), refuses to go below
--     zero, and writes the new quantity, in the same statement;
--   * any other change to `inventory_items.quantity_available` is refused,
--     whoever makes it: an app user (who has no UPDATE grant anyway), an
--     RPC, the service role, or the table owner;
--   * a new material starts at zero; its opening stock is a ledger entry;
--   * the ledger and the audit log are insert-only, for everyone.
--
-- The one way round it is `session_replication_role = replica`, which
-- skips triggers and needs a superuser: the one-time import script uses it
-- to copy history as it was (tool/migrate_firestore_to_supabase.mjs).

-- "4 units", "1.5 rolls", "1 roll": as the app writes quantities
-- (lib/core/utils/quantity_format.dart).
create or replace function app.format_quantity(quantity double precision, unit text)
returns text
language sql
immutable
set search_path = ''
as $$
  select
    case
      when quantity = trunc(quantity) then trunc(quantity)::bigint::text
      else quantity::text
    end
    || ' '
    || case
         when quantity = 1
           and char_length(unit) > 2
           and right(unit, 1) = 's'
           and right(unit, 2) <> 'ss'
         then left(unit, char_length(unit) - 1)
         else unit
       end;
$$;

-- Applies a ledger entry to its material. BEFORE INSERT on the ledger, so
-- the entry is stored with the balances it actually produced.
--
-- For every type but an adjustment, `quantity` is the amount moved and the
-- direction comes from the type. An adjustment is a physical count: the
-- caller gives the counted balance in `quantity_after`, and `quantity`
-- becomes the size of the correction.
create or replace function app.apply_ledger_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  item record;
begin
  select i.name, i.quantity_available, i.unit_of_measurement
    into item
    from public.inventory_items i
    where i.id = new.inventory_item_id
    for update;
  if not found then
    raise exception using
      errcode = 'PT404',
      message = 'This material is no longer in the inventory.';
  end if;

  new.item_name := coalesce(new.item_name, item.name);
  new.quantity_before := item.quantity_available;

  if new.type in ('issuance', 'consumption') then
    new.quantity_after := item.quantity_available - new.quantity;
  elsif new.type in ('replenishment', 'returned') then
    new.quantity_after := item.quantity_available + new.quantity;
  else
    if new.quantity_after is null or new.quantity_after < 0 then
      raise exception using
        errcode = 'PT422',
        message = 'The count cannot be below zero.';
    end if;
    if new.quantity_after = item.quantity_available then
      raise exception using
        errcode = 'PT409',
        message = format(
          'The count matches the record: %s.',
          app.format_quantity(item.quantity_available, item.unit_of_measurement)
        );
    end if;
    new.quantity := abs(new.quantity_after - item.quantity_available);
  end if;

  if new.quantity is null or new.quantity <= 0 then
    raise exception using
      errcode = 'PT422',
      message = 'Enter a quantity above zero.';
  end if;
  if new.quantity_after < 0 then
    raise exception using
      errcode = 'PT409',
      message = format(
        'Only %s of %s in stock.',
        app.format_quantity(item.quantity_available, item.unit_of_measurement),
        item.name
      );
  end if;

  update public.inventory_items
    set quantity_available = new.quantity_after,
        updated_at = now()
    where id = new.inventory_item_id;

  return new;
end;
$$;

create trigger inventory_transactions_apply
  before insert on public.inventory_transactions
  for each row execute function app.apply_ledger_entry();

-- Refuses a quantity change that did not come from the ledger trigger.
-- The ledger's own update runs one trigger level down (depth 2); any other
-- UPDATE, from an RPC or a console, is at depth 1.
create or replace function app.guard_stock_quantity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.quantity_available <> 0 and pg_trigger_depth() < 2 then
      raise exception using
        errcode = 'PT403',
        message = 'A new material starts at zero; its opening stock is a ledger entry.';
    end if;
  elsif new.quantity_available is distinct from old.quantity_available
    and pg_trigger_depth() < 2 then
    raise exception using
      errcode = 'PT403',
      message = 'Stock changes only through the inventory ledger.';
  end if;
  return new;
end;
$$;

create trigger inventory_items_quantity_guard
  before insert or update on public.inventory_items
  for each row execute function app.guard_stock_quantity();

-- Insert-only: no UPDATE, DELETE or TRUNCATE, for anyone (§3.4
-- Auditability; a ledger an administrator could rewrite is not a ledger).
create or replace function app.refuse_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'PT403',
    message = format('%s is append-only: entries are never changed or removed.', tg_table_name);
end;
$$;

create trigger inventory_transactions_insert_only
  before update or delete on public.inventory_transactions
  for each row execute function app.refuse_change();
create trigger inventory_transactions_no_truncate
  before truncate on public.inventory_transactions
  for each statement execute function app.refuse_change();

create trigger audit_logs_insert_only
  before update or delete on public.audit_logs
  for each row execute function app.refuse_change();
create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function app.refuse_change();

-- The timeline is a record too (Objective 3.B).
create trigger report_status_history_insert_only
  before update or delete on public.report_status_history
  for each row execute function app.refuse_change();

-- Not even the service role rewrites them through the API.
revoke update, delete, truncate on public.inventory_transactions, public.audit_logs,
  public.report_status_history from service_role;

grant execute on function app.format_quantity(double precision, text) to authenticated, service_role;
