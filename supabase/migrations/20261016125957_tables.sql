-- GSUhub on Supabase (Objective 1): the tables.
--
-- One table per Firestore collection and subcollection the app used
-- (docs/data_dictionary.md). Ids stay text, so Firebase uids, the seed's
-- readable ids (`rep-0001`) and ids the app reserves before writing
-- (`newReportId`) all carry over unchanged. Enumerations are text with a
-- CHECK listing the app's own ids (lib/core/enums), so a row reads the same
-- as the Firestore document did. Timestamps are timestamptz, stamped by the
-- database.
--
-- Access is in later migrations: nothing here is readable or writable by
-- an app user until 20261016130005_row_level_security.sql says so.

create schema if not exists app;
comment on schema app is
  'GSUhub helpers: who is asking, and the checks the policies and RPCs share. Not exposed through the API.';

-- A 20-character random id, the shape of a Firestore auto id, for rows the
-- server creates (status history, ledger, audit, notifications).
create or replace function app.new_id()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
    substr(
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',
      1 + floor(random() * 62)::int,
      1
    ),
    ''
  )
  from generate_series(1, 20);
$$;

-- The damage categories (lib/core/constants/damage_categories.dart).
create or replace function app.is_category(value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select value in (
    'electrical', 'plumbing', 'structural', 'carpentry', 'airConditioning',
    'cleaningAndSanitation', 'generalMaintenance'
  );
$$;

create or replace function app.is_priority(value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select value in ('low', 'medium', 'high', 'critical');
$$;

create or replace function app.is_condition(value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select value in ('excellent', 'good', 'fair', 'poor');
$$;

-- ---------------------------------------------------------------- users

create table public.users (
  id text primary key,
  full_name text not null check (char_length(full_name) between 1 and 120),
  email text not null check (char_length(email) between 3 and 254),
  role text not null
    check (role in ('requestor', 'maintenancePersonnel', 'admin')),
  account_status text not null default 'pending'
    check (account_status in ('active', 'inactive', 'pending')),
  department text check (char_length(department) <= 120),
  contact_number text check (char_length(contact_number) <= 40),
  specialization text check (specialization is null or app.is_category(specialization)),
  availability text
    check (availability is null or availability in ('available', 'busy', 'onLeave')),
  active_task_count integer not null default 0 check (active_task_count >= 0),
  fcm_token text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index users_email_key on public.users (lower(email));
create index users_role_idx on public.users (role, account_status);

-- ----------------------------------------------------- facilities, assets

create table public.facilities (
  id text primary key default app.new_id(),
  name text not null check (char_length(name) between 1 and 120),
  building_name text not null check (char_length(building_name) between 1 and 120),
  room_identifier text check (char_length(room_identifier) <= 120),
  location_description text check (char_length(location_description) <= 200),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  qr_code text not null unique check (char_length(qr_code) between 1 and 80),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);
create index facilities_building_idx on public.facilities (building_name, room_identifier);

create table public.assets (
  id text primary key default app.new_id(),
  name text not null check (char_length(name) between 1 and 120),
  qr_code text not null unique check (char_length(qr_code) between 1 and 80),
  facility_id text not null references public.facilities (id),
  condition text not null check (app.is_condition(condition)),
  category text check (char_length(category) <= 60),
  serial_number text check (char_length(serial_number) <= 60),
  acquired_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index assets_facility_idx on public.assets (facility_id);

-- ------------------------------------------------------------ work orders
-- Before damage_reports, which points at it.

create table public.work_orders (
  id text primary key default app.new_id(),
  -- An array, not a join table: merged duplicates share one work order and
  -- the app reads the list whole (WorkOrder.reportIds).
  report_ids text[] not null check (cardinality(report_ids) >= 1),
  title text not null check (char_length(title) between 1 and 200),
  description text not null check (char_length(description) <= 5000),
  category text not null check (app.is_category(category)),
  priority text not null check (app.is_priority(priority)),
  status text not null default 'pending'
    check (status in ('pending', 'inProgress', 'forReview', 'completed')),
  assigned_personnel_ids text[] not null default '{}',
  facility_id text references public.facilities (id),
  facility_name text,
  admin_notes text check (char_length(admin_notes) <= 1000),
  scheduled_for timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_by text not null references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index work_orders_status_idx on public.work_orders (status, priority);
create index work_orders_assignees_idx on public.work_orders using gin (assigned_personnel_ids);

-- --------------------------------------------------------- damage reports

create table public.damage_reports (
  id text primary key default app.new_id(),
  reporter_id text not null references public.users (id),
  reporter_name text not null,
  title text not null check (char_length(title) between 1 and 200),
  description text not null check (char_length(description) between 1 and 5000),
  category text check (category is null or app.is_category(category)),
  classified_automatically boolean not null default false,
  requestor_category text
    check (requestor_category is null or app.is_category(requestor_category)),
  facility_id text references public.facilities (id),
  facility_name text,
  location_description text check (char_length(location_description) <= 300),
  asset_id text references public.assets (id),
  -- The geo-tag: plain numbers, captured on the phone (Objective 3.C). No
  -- query filters or sorts by distance, so PostGIS earns nothing here
  -- (docs/architecture_decisions.md §21).
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  photo_urls text[] not null default '{}' check (cardinality(photo_urls) <= 10),
  requestor_priority text not null check (app.is_priority(requestor_priority)),
  severity_rating integer check (severity_rating >= 0),
  safety_risk_rating integer check (safety_risk_rating >= 0),
  frequency_rating integer check (frequency_rating >= 0),
  location_importance_rating integer check (location_importance_rating >= 0),
  priority_score double precision,
  recommended_priority text check (recommended_priority is null or app.is_priority(recommended_priority)),
  official_priority text check (official_priority is null or app.is_priority(official_priority)),
  status text not null default 'submitted' check (status in (
    'submitted', 'underReview', 'approved', 'assigned', 'inProgress',
    'forReview', 'completed', 'closed', 'merged', 'rejected', 'archived'
  )),
  duplicate_of text references public.damage_reports (id),
  dismissed_duplicate_ids text[] not null default '{}',
  work_order_id text references public.work_orders (id) deferrable initially deferred,
  reviewed_by text references public.users (id),
  reviewed_at timestamptz,
  rejection_reason text check (char_length(rejection_reason) <= 1000),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);
create index damage_reports_reporter_idx on public.damage_reports (reporter_id, submitted_at desc);
create index damage_reports_status_idx on public.damage_reports (status, submitted_at desc);
create index damage_reports_similar_idx on public.damage_reports (facility_id, category, submitted_at);
create index damage_reports_work_order_idx on public.damage_reports (work_order_id);

-- One row per status change: the requestor's timeline (Objective 3.B).
create table public.report_status_history (
  id text primary key default app.new_id(),
  report_id text not null references public.damage_reports (id),
  status text not null,
  changed_at timestamptz not null default now(),
  changed_by text not null,
  note text,
  personnel_name text,
  personnel_specialization text
);
create index report_status_history_report_idx on public.report_status_history (report_id, changed_at);

-- --------------------------------------------- materials on a work order

-- Recorded as used while the work is open; deducted when the report is
-- filed (Objective 5.C).
create table public.work_order_materials_used (
  work_order_id text not null references public.work_orders (id),
  inventory_item_id text not null,
  item_name text not null,
  quantity_used double precision not null check (quantity_used > 0),
  unit_of_measurement text not null,
  recorded_by text not null references public.users (id),
  recorded_at timestamptz not null default now(),
  primary key (work_order_id, inventory_item_id)
);

-- Pre-assigned by GSU; moves no stock (Objective 6.B).
create table public.work_order_materials_allocated (
  work_order_id text not null references public.work_orders (id),
  inventory_item_id text not null,
  item_name text not null,
  quantity double precision not null check (quantity > 0),
  unit_of_measurement text not null,
  allocated_by text not null references public.users (id),
  allocated_at timestamptz not null default now(),
  primary key (work_order_id, inventory_item_id)
);

-- ------------------------------------------------------------------ tasks

create table public.tasks (
  id text primary key default app.new_id(),
  work_order_id text not null references public.work_orders (id),
  title text not null check (char_length(title) between 1 and 120),
  description text check (char_length(description) <= 500),
  assigned_to text not null references public.users (id),
  status text not null default 'pending'
    check (status in ('pending', 'inProgress', 'completed')),
  due_date timestamptz,
  proof_photo_urls text[] not null default '{}',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tasks_assignee_idx on public.tasks (assigned_to, due_date);
create index tasks_work_order_idx on public.tasks (work_order_id);

-- ------------------------------------------------- accomplishment reports

create table public.accomplishment_reports (
  id text primary key default app.new_id(),
  work_order_id text not null references public.work_orders (id),
  submitted_by text not null references public.users (id),
  completion_notes text not null check (char_length(completion_notes) between 1 and 2000),
  photo_urls text[] not null default '{}' check (cardinality(photo_urls) <= 5),
  -- [{inventoryItemId, itemName, quantityUsed, unitOfMeasurement}], as the
  -- report carries them (MaterialUsage.toMap).
  materials_used jsonb not null default '[]' check (jsonb_typeof(materials_used) = 'array'),
  inventory_deducted boolean not null default false,
  reviewed_by text references public.users (id),
  reviewed_at timestamptz,
  submitted_at timestamptz not null default now()
);
create index accomplishment_reports_work_order_idx on public.accomplishment_reports (work_order_id, submitted_at desc);

-- -------------------------------------------------------------- inventory

create table public.inventory_items (
  id text primary key default app.new_id(),
  name text not null check (char_length(name) between 1 and 80),
  category text not null check (char_length(category) between 1 and 40),
  specification text check (char_length(specification) <= 40),
  -- Changed only by the ledger (20261016130009_stock_ledger.sql).
  quantity_available double precision not null default 0 check (quantity_available >= 0),
  unit_of_measurement text not null check (char_length(unit_of_measurement) between 1 and 40),
  storage_location text not null check (char_length(storage_location) between 1 and 80),
  qr_code text not null unique check (char_length(qr_code) between 1 and 80),
  minimum_threshold double precision not null default 0 check (minimum_threshold >= 0),
  unit_cost double precision check (unit_cost >= 0),
  photo_url text,
  condition text check (condition is null or app.is_condition(condition)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index inventory_items_name_idx on public.inventory_items (name);

-- The stock ledger. Insert-only, for everyone.
create table public.inventory_transactions (
  id text primary key default app.new_id(),
  inventory_item_id text not null references public.inventory_items (id),
  item_name text not null,
  type text not null check (type in (
    'issuance', 'consumption', 'returned', 'replenishment', 'adjustment'
  )),
  quantity double precision not null check (quantity > 0),
  quantity_before double precision not null check (quantity_before >= 0),
  quantity_after double precision not null check (quantity_after >= 0),
  work_order_id text,
  accomplishment_report_id text,
  notes text check (char_length(notes) <= 500),
  performed_by text not null,
  performed_by_name text,
  performed_at timestamptz not null default now()
);
create index inventory_transactions_item_idx on public.inventory_transactions (inventory_item_id, performed_at desc);
create index inventory_transactions_work_order_idx on public.inventory_transactions (work_order_id, performed_at desc);
create index inventory_transactions_time_idx on public.inventory_transactions (performed_at desc);

create table public.material_requests (
  id text primary key default app.new_id(),
  work_order_id text not null references public.work_orders (id),
  requested_by text not null references public.users (id),
  requested_by_name text not null,
  -- [{inventoryItemId, itemName, quantity, unitOfMeasurement}] (MaterialLine).
  items jsonb not null check (
    jsonb_typeof(items) = 'array'
    and jsonb_array_length(items) between 1 and 20
  ),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined')),
  note text check (char_length(note) <= 300),
  admin_note text check (char_length(admin_note) <= 300),
  reviewed_by text references public.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index material_requests_work_order_idx on public.material_requests (work_order_id, created_at desc);
create index material_requests_created_idx on public.material_requests (created_at desc);

-- ------------------------------------------------------------------ tools

create table public.tools (
  id text primary key default app.new_id(),
  tool_code text not null unique check (char_length(tool_code) between 1 and 20),
  name text not null check (char_length(name) between 1 and 80),
  status text not null default 'available'
    check (status in ('available', 'borrowed', 'inRepair', 'retired')),
  condition text not null check (app.is_condition(condition)),
  category text check (char_length(category) <= 40),
  storage_location text check (char_length(storage_location) <= 80),
  current_holder_id text references public.users (id),
  current_loan_id text,
  qr_code text not null unique check (char_length(qr_code) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- §1.5 personnel accountability: a tool out has a holder.
  check (status <> 'borrowed' or current_holder_id is not null)
);

create table public.tool_loans (
  id text primary key default app.new_id(),
  tool_id text not null references public.tools (id),
  tool_name text not null,
  borrowed_by text not null references public.users (id),
  work_order_id text references public.work_orders (id),
  borrowed_at timestamptz not null default now(),
  expected_return_at timestamptz,
  returned_at timestamptz,
  condition_on_borrow text not null check (app.is_condition(condition_on_borrow)),
  condition_on_return text
    check (condition_on_return is null or app.is_condition(condition_on_return)),
  notes text check (char_length(notes) <= 300),
  check (returned_at is null or returned_at >= borrowed_at),
  check (returned_at is null or condition_on_return is not null)
);
create index tool_loans_open_idx on public.tool_loans (borrowed_by) where returned_at is null;
create index tool_loans_tool_idx on public.tool_loans (tool_id, borrowed_at desc);
create index tool_loans_work_order_idx on public.tool_loans (work_order_id);

-- ------------------------------------------------------------ feedback

-- One rating per report, under the report's own id (Objective 3.C).
create table public.feedback (
  id text primary key references public.damage_reports (id),
  work_order_id text not null references public.work_orders (id),
  report_id text not null references public.damage_reports (id),
  submitted_by text not null references public.users (id),
  response_time_rating integer not null check (response_time_rating between 1 and 5),
  service_quality_rating integer not null check (service_quality_rating between 1 and 5),
  overall_satisfaction_rating integer not null check (overall_satisfaction_rating between 1 and 5),
  comments text check (char_length(comments) <= 1000),
  submitted_at timestamptz not null default now(),
  check (id = report_id)
);
create index feedback_work_order_idx on public.feedback (work_order_id);
create index feedback_submitted_idx on public.feedback (submitted_by, submitted_at desc);

-- -------------------------------------------------------- notifications

create table public.notifications (
  id text primary key default app.new_id(),
  recipient_id text not null references public.users (id),
  type text not null check (type in (
    'reportAcknowledged', 'workOrderAssigned', 'taskAssigned',
    'statusUpdate', 'maintenanceCompleted', 'lowStockAlert'
  )),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) <= 1000),
  related_entity_type text,
  related_entity_id text,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

-- -------------------------------------------------------------- audit log
-- Insert-only, for everyone (§3.4 Auditability).

create table public.audit_logs (
  id text primary key default app.new_id(),
  actor_id text not null,
  actor_name text not null,
  action text not null check (action in (
    'created', 'updated', 'statusChanged', 'assigned', 'merged', 'deleted'
  )),
  entity_type text not null,
  entity_id text not null,
  description text not null,
  changes jsonb,
  "timestamp" timestamptz not null default now()
);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id, "timestamp" desc);
create index audit_logs_actor_idx on public.audit_logs (actor_id, "timestamp" desc);
create index audit_logs_time_idx on public.audit_logs ("timestamp" desc);

-- ------------------------------------------------------------ app config
-- The three config documents, kept as the JSON the models already read
-- (ClassificationRulesConfig, PrioritizationConfig,
-- DuplicateDetectionConfig).

create table public.app_config (
  id text primary key
    check (id in ('classification_rules', 'prioritization', 'duplicate_detection')),
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  updated_by text,
  updated_at timestamptz not null default now()
);
