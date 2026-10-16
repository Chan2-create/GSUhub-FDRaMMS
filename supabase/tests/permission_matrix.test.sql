-- The permission matrix (Objective 1, item 5): role × table × operation,
-- allowed and denied.
--
-- DERIVED from manuscript §3.4's Requirements Specification, because the
-- development plan's §4 was never available. Verify against Development
-- Plan §4 when available. The same matrix, as a table, is in
-- docs/data_dictionary.md ("Security rules").
--
-- Reads: each identity sees exactly the rows listed, and nothing else.
-- An account that is not active (inactive, or pending approval) sees only
-- its own profile; a request with no signed-in user is refused outright.
--
-- Writes: no app user writes any table directly. Every write is an RPC
-- (tested with the RPCs), so INSERT, UPDATE and DELETE are refused for the
-- administrator, the requestor and the technician alike.

begin;
select tests.create_fixtures();

create temporary table expected (who text, uid text, tbl text, key text, ids text);
insert into expected (who, uid, tbl, key, ids) values
  -- users: own record; administrators everyone
  ('admin', 'u-admin', 'users', 'id', 'u-admin,u-inactive,u-pending,u-req,u-req2,u-tech,u-tech-off,u-tech2'),
  ('requestor', 'u-req', 'users', 'id', 'u-req'),
  ('technician', 'u-tech', 'users', 'id', 'u-tech'),
  ('inactive', 'u-inactive', 'users', 'id', 'u-inactive'),
  ('pending', 'u-pending', 'users', 'id', 'u-pending'),
  ('inactive technician', 'u-tech-off', 'users', 'id', 'u-tech-off'),
  ('anonymous', null, 'users', 'id', 'ERROR 42501'),

  -- facilities and assets: any active user
  ('admin', 'u-admin', 'facilities', 'id', 'f-1,f-2'),
  ('requestor', 'u-req', 'facilities', 'id', 'f-1,f-2'),
  ('technician', 'u-tech', 'facilities', 'id', 'f-1,f-2'),
  ('inactive', 'u-inactive', 'facilities', 'id', ''),
  ('pending', 'u-pending', 'facilities', 'id', ''),
  ('inactive technician', 'u-tech-off', 'facilities', 'id', ''),
  ('anonymous', null, 'facilities', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'assets', 'id', 'a-1'),
  ('requestor', 'u-req', 'assets', 'id', 'a-1'),
  ('technician', 'u-tech', 'assets', 'id', 'a-1'),
  ('inactive', 'u-inactive', 'assets', 'id', ''),
  ('pending', 'u-pending', 'assets', 'id', ''),
  ('inactive technician', 'u-tech-off', 'assets', 'id', ''),
  ('anonymous', null, 'assets', 'id', 'ERROR 42501'),

  -- damage reports: own; the technician's work; administrators all
  ('admin', 'u-admin', 'damage_reports', 'id', 'r-1,r-2,r-3,r-4'),
  ('requestor', 'u-req', 'damage_reports', 'id', 'r-1,r-3'),
  ('technician', 'u-tech', 'damage_reports', 'id', 'r-1'),
  ('inactive', 'u-inactive', 'damage_reports', 'id', ''),
  ('pending', 'u-pending', 'damage_reports', 'id', ''),
  ('inactive technician', 'u-tech-off', 'damage_reports', 'id', ''),
  ('anonymous', null, 'damage_reports', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'report_status_history', 'id', 'h-1,h-2,h-3'),
  ('requestor', 'u-req', 'report_status_history', 'id', 'h-1,h-3'),
  ('technician', 'u-tech', 'report_status_history', 'id', 'h-1'),
  ('inactive', 'u-inactive', 'report_status_history', 'id', ''),
  ('pending', 'u-pending', 'report_status_history', 'id', ''),
  ('inactive technician', 'u-tech-off', 'report_status_history', 'id', ''),
  ('anonymous', null, 'report_status_history', 'id', 'ERROR 42501'),

  -- work orders and what is on them: assigned personnel; administrators all
  ('admin', 'u-admin', 'work_orders', 'id', 'w-1,w-2'),
  ('requestor', 'u-req', 'work_orders', 'id', ''),
  ('technician', 'u-tech', 'work_orders', 'id', 'w-1'),
  ('inactive', 'u-inactive', 'work_orders', 'id', ''),
  ('pending', 'u-pending', 'work_orders', 'id', ''),
  ('inactive technician', 'u-tech-off', 'work_orders', 'id', ''),
  ('anonymous', null, 'work_orders', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'work_order_materials_used', 'work_order_id', 'w-1,w-2'),
  ('requestor', 'u-req', 'work_order_materials_used', 'work_order_id', ''),
  ('technician', 'u-tech', 'work_order_materials_used', 'work_order_id', 'w-1'),
  ('inactive', 'u-inactive', 'work_order_materials_used', 'work_order_id', ''),
  ('pending', 'u-pending', 'work_order_materials_used', 'work_order_id', ''),
  ('inactive technician', 'u-tech-off', 'work_order_materials_used', 'work_order_id', ''),
  ('anonymous', null, 'work_order_materials_used', 'work_order_id', 'ERROR 42501'),

  ('admin', 'u-admin', 'work_order_materials_allocated', 'work_order_id', 'w-1,w-2'),
  ('requestor', 'u-req', 'work_order_materials_allocated', 'work_order_id', ''),
  ('technician', 'u-tech', 'work_order_materials_allocated', 'work_order_id', 'w-1'),
  ('inactive', 'u-inactive', 'work_order_materials_allocated', 'work_order_id', ''),
  ('pending', 'u-pending', 'work_order_materials_allocated', 'work_order_id', ''),
  ('inactive technician', 'u-tech-off', 'work_order_materials_allocated', 'work_order_id', ''),
  ('anonymous', null, 'work_order_materials_allocated', 'work_order_id', 'ERROR 42501'),

  ('admin', 'u-admin', 'tasks', 'id', 't-1,t-2'),
  ('requestor', 'u-req', 'tasks', 'id', ''),
  ('technician', 'u-tech', 'tasks', 'id', 't-1'),
  ('inactive', 'u-inactive', 'tasks', 'id', ''),
  ('pending', 'u-pending', 'tasks', 'id', ''),
  ('inactive technician', 'u-tech-off', 'tasks', 'id', ''),
  ('anonymous', null, 'tasks', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'accomplishment_reports', 'id', 'ac-1,ac-2'),
  ('requestor', 'u-req', 'accomplishment_reports', 'id', ''),
  ('technician', 'u-tech', 'accomplishment_reports', 'id', 'ac-1'),
  ('inactive', 'u-inactive', 'accomplishment_reports', 'id', ''),
  ('pending', 'u-pending', 'accomplishment_reports', 'id', ''),
  ('inactive technician', 'u-tech-off', 'accomplishment_reports', 'id', ''),
  ('anonymous', null, 'accomplishment_reports', 'id', 'ERROR 42501'),

  -- inventory: the catalogue to active users; the ledger to staff
  ('admin', 'u-admin', 'inventory_items', 'id', 'i-1'),
  ('requestor', 'u-req', 'inventory_items', 'id', 'i-1'),
  ('technician', 'u-tech', 'inventory_items', 'id', 'i-1'),
  ('inactive', 'u-inactive', 'inventory_items', 'id', ''),
  ('pending', 'u-pending', 'inventory_items', 'id', ''),
  ('inactive technician', 'u-tech-off', 'inventory_items', 'id', ''),
  ('anonymous', null, 'inventory_items', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'inventory_transactions', 'id', 'l-1'),
  ('requestor', 'u-req', 'inventory_transactions', 'id', ''),
  ('technician', 'u-tech', 'inventory_transactions', 'id', 'l-1'),
  ('inactive', 'u-inactive', 'inventory_transactions', 'id', ''),
  ('pending', 'u-pending', 'inventory_transactions', 'id', ''),
  ('inactive technician', 'u-tech-off', 'inventory_transactions', 'id', ''),
  ('anonymous', null, 'inventory_transactions', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'material_requests', 'id', 'm-1,m-2'),
  ('requestor', 'u-req', 'material_requests', 'id', ''),
  ('technician', 'u-tech', 'material_requests', 'id', 'm-1'),
  ('inactive', 'u-inactive', 'material_requests', 'id', ''),
  ('pending', 'u-pending', 'material_requests', 'id', ''),
  ('inactive technician', 'u-tech-off', 'material_requests', 'id', ''),
  ('anonymous', null, 'material_requests', 'id', 'ERROR 42501'),

  -- tools: the list to active users; loans, a technician their own
  ('admin', 'u-admin', 'tools', 'id', 'tl-1,tl-2'),
  ('requestor', 'u-req', 'tools', 'id', 'tl-1,tl-2'),
  ('technician', 'u-tech', 'tools', 'id', 'tl-1,tl-2'),
  ('inactive', 'u-inactive', 'tools', 'id', ''),
  ('pending', 'u-pending', 'tools', 'id', ''),
  ('inactive technician', 'u-tech-off', 'tools', 'id', ''),
  ('anonymous', null, 'tools', 'id', 'ERROR 42501'),

  ('admin', 'u-admin', 'tool_loans', 'id', 'lo-1,lo-2'),
  ('requestor', 'u-req', 'tool_loans', 'id', ''),
  ('technician', 'u-tech', 'tool_loans', 'id', 'lo-1'),
  ('inactive', 'u-inactive', 'tool_loans', 'id', ''),
  ('pending', 'u-pending', 'tool_loans', 'id', ''),
  ('inactive technician', 'u-tech-off', 'tool_loans', 'id', ''),
  ('anonymous', null, 'tool_loans', 'id', 'ERROR 42501'),

  -- feedback: a requestor their own; never personnel (§1.5)
  ('admin', 'u-admin', 'feedback', 'id', 'r-1,r-2'),
  ('requestor', 'u-req', 'feedback', 'id', 'r-1'),
  ('technician', 'u-tech', 'feedback', 'id', ''),
  ('inactive', 'u-inactive', 'feedback', 'id', ''),
  ('pending', 'u-pending', 'feedback', 'id', ''),
  ('inactive technician', 'u-tech-off', 'feedback', 'id', ''),
  ('anonymous', null, 'feedback', 'id', 'ERROR 42501'),

  -- notifications: one's own, while active
  ('admin', 'u-admin', 'notifications', 'id', ''),
  ('requestor', 'u-req', 'notifications', 'id', 'n-1'),
  ('technician', 'u-tech', 'notifications', 'id', 'n-2'),
  ('inactive', 'u-inactive', 'notifications', 'id', ''),
  ('pending', 'u-pending', 'notifications', 'id', ''),
  ('inactive technician', 'u-tech-off', 'notifications', 'id', ''),
  ('anonymous', null, 'notifications', 'id', 'ERROR 42501'),

  -- the audit log: administrators
  ('admin', 'u-admin', 'audit_logs', 'id', 'au-1'),
  ('requestor', 'u-req', 'audit_logs', 'id', ''),
  ('technician', 'u-tech', 'audit_logs', 'id', ''),
  ('inactive', 'u-inactive', 'audit_logs', 'id', ''),
  ('pending', 'u-pending', 'audit_logs', 'id', ''),
  ('inactive technician', 'u-tech-off', 'audit_logs', 'id', ''),
  ('anonymous', null, 'audit_logs', 'id', 'ERROR 42501'),

  -- config: any active user
  ('admin', 'u-admin', 'app_config', 'id', 'classification_rules'),
  ('requestor', 'u-req', 'app_config', 'id', 'classification_rules'),
  ('technician', 'u-tech', 'app_config', 'id', 'classification_rules'),
  ('inactive', 'u-inactive', 'app_config', 'id', ''),
  ('pending', 'u-pending', 'app_config', 'id', ''),
  ('inactive technician', 'u-tech-off', 'app_config', 'id', ''),
  ('anonymous', null, 'app_config', 'id', 'ERROR 42501');

create temporary table writable (tbl text, key text);
insert into writable values
  ('users', 'id'), ('facilities', 'id'), ('assets', 'id'),
  ('damage_reports', 'id'), ('report_status_history', 'id'),
  ('work_orders', 'id'), ('work_order_materials_used', 'work_order_id'),
  ('work_order_materials_allocated', 'work_order_id'), ('tasks', 'id'),
  ('accomplishment_reports', 'id'), ('inventory_items', 'id'),
  ('inventory_transactions', 'id'), ('material_requests', 'id'),
  ('tools', 'id'), ('tool_loans', 'id'), ('feedback', 'id'),
  ('notifications', 'id'), ('audit_logs', 'id'), ('app_config', 'id');

create temporary table writers (who text, uid text);
insert into writers values
  ('admin', 'u-admin'), ('requestor', 'u-req'), ('technician', 'u-tech');

select plan(
  (select count(*)::int from expected)
  + (select count(*)::int * 3 from writable, writers)
);

select is(
  tests.visible(uid, tbl, key),
  ids,
  format('%s reads %s: %s', who, tbl, coalesce(nullif(ids, ''), 'none'))
)
from expected
order by tbl, who;

select is(
  tests.attempt(
    w.uid,
    case op
      when 'insert' then format('insert into public.%I default values', t.tbl)
      when 'update' then format('update public.%I set %I = %I where false', t.tbl, t.key, t.key)
      else format('delete from public.%I where false', t.tbl)
    end
  ),
  '42501',
  format('%s cannot %s %s directly', w.who, op, t.tbl)
)
from writable t, writers w, (values ('insert'), ('update'), ('delete')) ops (op)
order by t.tbl, w.who, op;

select * from finish();
rollback;
