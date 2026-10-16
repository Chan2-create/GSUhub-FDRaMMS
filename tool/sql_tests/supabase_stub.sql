-- A stand-in for the parts of a Supabase database the migrations touch, so
-- tool/sql_tests/run.mjs can run the pgTAP tests in PGlite (Postgres in
-- WebAssembly) on a machine without Docker. The real stack (`supabase
-- start`, then `supabase test db`) provides all of this itself; this file
-- is never applied to it.
--
-- Matches Supabase's shapes where the tests depend on them: the three API
-- roles, auth.jwt() reading request.jwt.claims, storage.buckets and
-- storage.objects with row level security and the grants `authenticated`
-- has there, and the supabase_realtime publication.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), ''),
    '{}'
  )::jsonb;
$$;
grant execute on function auth.jwt() to anon, authenticated, service_role;

create schema storage;
grant usage on schema storage to anon, authenticated, service_role;

create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner_id text,
  metadata jsonb,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;

grant all on storage.objects to authenticated, service_role;
grant select on storage.buckets to authenticated;
create policy buckets_read on storage.buckets for select to authenticated using (true);

create publication supabase_realtime;

-- Supabase's defaults: new objects in public reachable by the API roles.
-- The migrations revoke what they must not have.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
