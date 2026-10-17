-- Who can call the database's functions (Objective 1, M3).
--
-- Read from the catalog rather than listed, so a function added later is
-- held to the same rules without anyone remembering to add it here.
--
--   public.*  the API: thin wrappers that run as the caller and hand over
--             to app.*. Never security definer; never callable signed out.
--   app.*     the implementations: security definer, so each checks its
--             caller, with a fixed search_path. Not exposed by the API.

begin;
select plan(8);

create temporary view api_functions as
  select p.oid, p.proname, p.prosecdef
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosrc like '%app.%';

create temporary view app_functions as
  select p.oid, p.proname, p.prosecdef, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app';

select cmp_ok(
  (select count(*)::int from api_functions), '>=', 23,
  'the API has its functions'
);
select is(
  (select string_agg(proname, ', ' order by proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef),
  null,
  'no function in public runs with its owner''s rights'
);
select is(
  (select string_agg(proname, ', ' order by proname) from api_functions
     where has_function_privilege('anon', oid, 'execute')),
  null,
  'nobody signed out can call any of them'
);
select is(
  (select string_agg(proname, ', ' order by proname) from api_functions
     where not has_function_privilege('authenticated', oid, 'execute')),
  null,
  'a signed-in user can call every one (each decides what they may do)'
);
select is(
  (select string_agg(proname, ', ' order by proname) from app_functions
     where not coalesce(proconfig, '{}') @> array['search_path=""']),
  null,
  'every app function fixes its search_path, so no caller''s schema can stand in'
);
select is(
  (select string_agg(proname, ', ' order by proname) from app_functions
     where has_function_privilege('anon', oid, 'execute')),
  null,
  'nobody signed out can run an app function'
);
select ok(
  not has_schema_privilege('anon', 'app', 'usage'),
  'nor even see the app schema'
);
select ok(
  (select bool_and(prosecdef) from app_functions
     where proname in ('submit_report', 'assign_work_order', 'rate_service', 'update_account', 'move_work_order')),
  'the implementations run as the owner, past row level security, and check their caller themselves'
);

select * from finish();
rollback;
