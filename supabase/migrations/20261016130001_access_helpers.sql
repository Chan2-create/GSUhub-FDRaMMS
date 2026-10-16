-- Who is asking, and what they may do (Objective 1).
--
-- The app signs in with Firebase. The `firebase-token-exchange` Edge
-- Function verifies the Firebase ID token and hands back a short-lived
-- Supabase JWT whose `sub` is the Firebase uid and whose role is
-- `authenticated` (docs/architecture_decisions.md §21). Firebase uids are
-- not UUIDs, so nothing here uses auth.uid(), which casts to uuid: the uid
-- is read from the claim as text.
--
-- The role and account status come from `users`, by that uid, exactly as
-- firestore.rules read them from `users/{uid}`. An account that is not
-- active (inactive, or a sign-up still pending) is nobody: every check
-- below fails for it, except reading its own profile (row level security).
--
-- These are SECURITY DEFINER so a policy on `users` can consult `users`
-- without recursing through its own policy. They live in `app`, which the
-- API does not expose, and each one decides only about the caller.

-- The caller's Firebase uid, or null for a request without a user token.
create or replace function app.uid()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif((select auth.jwt()) ->> 'sub', '');
$$;

-- The caller's role, when their account is active; null otherwise.
create or replace function app.active_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.role
  from public.users u
  where u.id = (select app.uid())
    and u.account_status = 'active';
$$;

create or replace function app.is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select app.active_role()) is not null;
$$;

create or replace function app.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select app.active_role()) = 'admin', false);
$$;

create or replace function app.is_personnel()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select app.active_role()) = 'maintenancePersonnel', false);
$$;

create or replace function app.is_requestor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select app.active_role()) = 'requestor', false);
$$;

-- Personnel act only on work assigned to them (firestore.rules
-- isAssignedTo, Objective 5).
create or replace function app.is_assigned_to(work_order_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select app.is_personnel())
    and exists (
      select 1
      from public.work_orders w
      where w.id = work_order_id
        and (select app.uid()) = any (w.assigned_personnel_ids)
    );
$$;

-- Whether the caller may read a damage report: an administrator, its
-- reporter (active), or a technician on its work order. The same test the
-- report's own policy makes, shared with its status history and photos.
create or replace function app.can_read_report(report_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select app.is_admin())
    or exists (
      select 1
      from public.damage_reports r
      where r.id = report_id
        and (
          (r.reporter_id = (select app.uid()) and (select app.is_active()))
          or (r.work_order_id is not null and app.is_assigned_to(r.work_order_id))
        )
    );
$$;

-- Policies call these as the requesting user, who therefore needs
-- EXECUTE. They reveal nothing beyond the caller's own role and
-- assignments. Nobody else gets them: not anon, not PUBLIC.
revoke all on schema app from public;
grant usage on schema app to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on function
  app.uid(),
  app.active_role(),
  app.is_active(),
  app.is_admin(),
  app.is_personnel(),
  app.is_requestor(),
  app.is_assigned_to(text),
  app.can_read_report(text),
  app.is_category(text),
  app.is_priority(text),
  app.is_condition(text)
to authenticated, service_role;
grant execute on function app.new_id() to service_role;
