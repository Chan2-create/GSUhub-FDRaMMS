-- Sessions end after 15 minutes of inactivity (Chris, 2026-11-15), down
-- from the 30 of 2026-11-14 (*_session_inactivity.sql): the same rule,
-- the same table and the same code, a shorter limit. Two things carry
-- the number: the function every check reads, and the words of the
-- refusal. The app's SessionPolicy holds the same 15, and its unit test
-- reads this file to keep the two equal.

create or replace function app.inactivity_limit()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '15 minutes';
$$;

create or replace function app.require_session()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select app.uid()) is not null and not (select app.session_alive()) then
    perform app.refuse('PT401',
      'Your session ended after 15 minutes of inactivity. Sign in again to continue.');
  end if;
end;
$$;
