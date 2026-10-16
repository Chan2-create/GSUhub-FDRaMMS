-- Row level security: who reads what (Objective 1, item 5).
--
-- The permission matrix (docs/data_dictionary.md "Security rules", and
-- supabase/tests/permission_matrix.test.sql) is DERIVED from manuscript
-- §3.4's Requirements Specification, because the development plan's §4
-- was never available. Verify against Development Plan §4 when available.
--
-- Reads follow firestore.rules, role by role. Writes are another matter:
-- an app user writes nothing directly. Every write is a Postgres function
-- (RPC) that checks the caller, the row and the move, and writes the
-- change, its timeline, its notices and its audit entry in one
-- transaction, as the Firestore transactions did. So `authenticated` is
-- granted SELECT and nothing else; INSERT, UPDATE and DELETE are revoked
-- from every app role. `service_role` (the import script and tests, never
-- the app) keeps full access and bypasses RLS, as the Firebase Admin SDK
-- did.
--
-- Policies are written `to authenticated` with the caller's identity in the
-- predicate, and each helper call wrapped in (select …) so it runs once per
-- statement, not once per row.

do $$
declare
  t text;
begin
  foreach t in array array[
    'users', 'facilities', 'assets', 'damage_reports',
    'report_status_history', 'work_orders', 'work_order_materials_used',
    'work_order_materials_allocated', 'tasks', 'accomplishment_reports',
    'inventory_items', 'inventory_transactions', 'material_requests',
    'tools', 'tool_loans', 'feedback', 'notifications', 'audit_logs',
    'app_config'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select on table public.%I to authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------- users
-- Everyone reads their own record, whatever its status: the app needs the
-- role to route, and a pending sign-up its "awaiting approval" state.
-- Administrators read everyone (assignment, the directory, accounts).

create policy users_select on public.users
  for select to authenticated
  using (
    id = (select app.uid())
    or (select app.is_admin())
  );

-- ----------------------------------------------------- facilities, assets
-- Any active user: a requestor fills in a report, a technician finds the
-- site.

create policy facilities_select on public.facilities
  for select to authenticated
  using ((select app.is_active()));

create policy assets_select on public.assets
  for select to authenticated
  using ((select app.is_active()));

-- --------------------------------------------------------- damage reports
-- Administrators all; a requestor their own; a technician the reports of
-- work assigned to them.

create policy damage_reports_select on public.damage_reports
  for select to authenticated
  using (
    (select app.is_admin())
    or (reporter_id = (select app.uid()) and (select app.is_active()))
    or (work_order_id is not null and app.is_assigned_to(work_order_id))
  );

-- Whoever may read the report may read how it got where it is.
create policy report_status_history_select on public.report_status_history
  for select to authenticated
  using (app.can_read_report(report_id));

-- ------------------------------------------------------------ work orders
-- Administrators all; personnel those assigned to them. Requestors none:
-- they follow their report, not the work order.

create policy work_orders_select on public.work_orders
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_personnel()) and (select app.uid()) = any (assigned_personnel_ids))
  );

create policy work_order_materials_used_select on public.work_order_materials_used
  for select to authenticated
  using ((select app.is_admin()) or app.is_assigned_to(work_order_id));

create policy work_order_materials_allocated_select on public.work_order_materials_allocated
  for select to authenticated
  using ((select app.is_admin()) or app.is_assigned_to(work_order_id));

-- ------------------------------------------------------------------ tasks

create policy tasks_select on public.tasks
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_personnel()) and assigned_to = (select app.uid()))
  );

-- ------------------------------------------------- accomplishment reports
-- A technician their own; administrators all.

create policy accomplishment_reports_select on public.accomplishment_reports
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_personnel()) and submitted_by = (select app.uid()))
  );

-- -------------------------------------------------------------- inventory
-- The catalogue, to any active user; the ledger to administrators and
-- personnel (§3.4); requests, a technician their own.

create policy inventory_items_select on public.inventory_items
  for select to authenticated
  using ((select app.is_active()));

create policy inventory_transactions_select on public.inventory_transactions
  for select to authenticated
  using ((select app.is_admin()) or (select app.is_personnel()));

create policy material_requests_select on public.material_requests
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_personnel()) and requested_by = (select app.uid()))
  );

-- ------------------------------------------------------------------ tools

create policy tools_select on public.tools
  for select to authenticated
  using ((select app.is_active()));

create policy tool_loans_select on public.tool_loans
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_personnel()) and borrowed_by = (select app.uid()))
  );

-- --------------------------------------------------------------- feedback
-- §1.5: ratings "do not automatically determine personnel performance
-- evaluations", so personnel never read them. A requestor reads their own.

create policy feedback_select on public.feedback
  for select to authenticated
  using (
    (select app.is_admin())
    or ((select app.is_requestor()) and submitted_by = (select app.uid()))
  );

-- -------------------------------------------------------- notifications

create policy notifications_select on public.notifications
  for select to authenticated
  using (
    recipient_id = (select app.uid())
    and (select app.is_active())
  );

-- -------------------------------------------------------------- audit log

create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using ((select app.is_admin()));

-- ------------------------------------------------------------ app config
-- The apps need the keyword dictionary and the thresholds.

create policy app_config_select on public.app_config
  for select to authenticated
  using ((select app.is_active()));
