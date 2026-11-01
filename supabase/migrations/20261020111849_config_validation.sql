-- The settings an administrator saves are checked here too (Objective 7.A).
--
-- update_config stored whatever JSON it was given, under any id, trusting
-- the console's models to have checked it. Now that Settings edits the
-- priority weights and score bands and the duplicate rules (§3.4, Tables
-- 3.2-3.5; configurable because the manuscript's Table 3.2 and its formula
-- disagree, see docs/architecture_decisions.md §18 and §22), a bad save
-- would change every score. So the database refuses what the models would
-- refuse, with the same reasons:
--
--   prioritization        a known scheme; four weights per scheme, each
--                         0 or more, at least one above 0; four score
--                         bands, Critical > High > Medium > Low, within the
--                         rating scale; a frequency window of 1-365 days;
--                         one report count per rating above the lowest,
--                         rising from 2
--   duplicate_detection   on or off; a similarity of 0-1; a window of
--                         1-2160 hours (90 days); the three match switches
--   classification_rules  for known categories only, lists of words, each
--                         1-80 characters, at most 200 a category
--
-- Any other id is refused: the console has no other settings.

create or replace function app.number_in(_data jsonb, _path text[])
returns double precision
language sql
immutable
set search_path = ''
as $$
  select case when jsonb_typeof(_data #> _path) = 'number' then (_data #>> _path)::double precision end;
$$;

create or replace function app.check_config(_id text, _data jsonb)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  scheme text;
  criterion text;
  level text;
  weight double precision;
  positive boolean;
  min_rating double precision;
  max_rating double precision;
  previous double precision;
  bound double precision;
  band jsonb;
  bands_previous double precision;
  category text;
  words jsonb;
  word jsonb;
begin
  case _id
  when 'prioritization' then
    if _data ->> 'activeScheme' is null
       or _data ->> 'activeScheme' not in ('integerWeights', 'decimalWeights') then
      perform app.refuse('PT422', 'Choose which weights to use: the integer weights or the decimal weights.');
    end if;
    foreach scheme in array array['integerWeights', 'decimalWeights'] loop
      positive := false;
      foreach criterion in array array['severity', 'safetyRisk', 'frequency', 'locationImportance'] loop
        weight := app.number_in(_data, array[scheme, criterion]);
        if weight is null or weight < 0 or weight > 100 then
          perform app.refuse('PT422', 'Every weight must be a number from 0 to 100.');
        end if;
        positive := positive or weight > 0;
      end loop;
      if not positive then
        perform app.refuse('PT422', 'At least one weight must be above 0.');
      end if;
    end loop;

    min_rating := coalesce(app.number_in(_data, array['minRating']), 1);
    max_rating := coalesce(app.number_in(_data, array['maxRating']), 4);
    if min_rating <> 1 or max_rating <> 4 then
      perform app.refuse('PT422', 'Ratings run from 1 to 4 (manuscript Table 3.4).');
    end if;

    previous := null;
    foreach level in array array['critical', 'high', 'medium', 'low'] loop
      bound := app.number_in(_data, array['thresholds', level]);
      if bound is null or bound < min_rating or bound > max_rating then
        perform app.refuse('PT422', 'Each score band must start between 1.00 and 4.00.');
      end if;
      if previous is not null and bound >= previous then
        perform app.refuse('PT422', 'The score bands must fall from Critical to Low: Critical starts '
          || 'highest, Low lowest.');
      end if;
      previous := bound;
    end loop;

    bound := app.number_in(_data, array['frequencyWindowDays']);
    if _data ? 'frequencyWindowDays' and (bound is null or bound < 1 or bound > 365 or bound <> trunc(bound)) then
      perform app.refuse('PT422', 'The frequency window must be a whole number of days from 1 to 365.');
    end if;
    if _data ? 'frequencyBands' then
      if jsonb_typeof(_data -> 'frequencyBands') <> 'array'
         or jsonb_array_length(_data -> 'frequencyBands') <> 3 then
        perform app.refuse('PT422', 'Give one report count for each Frequency rating above 1.');
      end if;
      bands_previous := 1;
      for band in select value from jsonb_array_elements(_data -> 'frequencyBands') loop
        if jsonb_typeof(band) <> 'number' or (band #>> '{}')::double precision <= bands_previous
           or (band #>> '{}')::double precision <> trunc((band #>> '{}')::double precision) then
          perform app.refuse('PT422', 'The report counts for Frequency must be whole numbers that rise '
            || 'with the rating, starting above 1.');
        end if;
        bands_previous := (band #>> '{}')::double precision;
      end loop;
    end if;

  when 'duplicate_detection' then
    if jsonb_typeof(_data -> 'enabled') <> 'boolean' then
      perform app.refuse('PT422', 'Say whether duplicate detection is on.');
    end if;
    bound := app.number_in(_data, array['descriptionSimilarityThreshold']);
    if bound is null or bound < 0 or bound > 1 then
      perform app.refuse('PT422', 'The description similarity must be from 0 to 1.');
    end if;
    bound := app.number_in(_data, array['timeWindowHours']);
    if bound is null or bound < 1 or bound > 2160 or bound <> trunc(bound) then
      perform app.refuse('PT422', 'The duplicate window must be a whole number of hours from 1 to 2160 '
        || '(90 days).');
    end if;
    foreach criterion in array array['matchOnFacilityIdentifier', 'matchOnLocation', 'matchOnCategory'] loop
      if _data ? criterion and jsonb_typeof(_data -> criterion) <> 'boolean' then
        perform app.refuse('PT422', 'The duplicate matching switches must be on or off.');
      end if;
    end loop;

  when 'classification_rules' then
    if jsonb_typeof(_data -> 'keywordsByCategory') <> 'object' then
      perform app.refuse('PT422', 'The keyword list could not be read.');
    end if;
    for category, words in select key, value from jsonb_each(_data -> 'keywordsByCategory') loop
      if not app.is_category(category) then
        perform app.refuse('PT422', 'There is no damage category ' || category || '.');
      end if;
      if jsonb_typeof(words) <> 'array' or jsonb_array_length(words) > 200 then
        perform app.refuse('PT422', 'Each category takes a list of at most 200 keywords.');
      end if;
      for word in select value from jsonb_array_elements(words) loop
        if jsonb_typeof(word) <> 'string'
           or char_length(btrim(word #>> '{}')) not between 1 and 80 then
          perform app.refuse('PT422', 'Each keyword must be 1 to 80 characters.');
        end if;
      end loop;
    end loop;
    if _data ? 'caseSensitive' and jsonb_typeof(_data -> 'caseSensitive') <> 'boolean' then
      perform app.refuse('PT422', 'Say whether keywords match case.');
    end if;

  else
    perform app.refuse('PT422', 'There are no settings called ' || coalesce(_id, '(none)') || '.');
  end case;
end;
$$;

create or replace function app.update_config(_id text, _data jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.require_admin();
  if _data is null or jsonb_typeof(_data) <> 'object' then
    perform app.refuse('PT422', 'The settings could not be read.');
  end if;
  perform app.check_config(_id, _data - 'updatedAt' - 'updatedBy');
  insert into public.app_config (id, data, updated_by, updated_at)
  values (_id, _data - 'updatedAt' - 'updatedBy', (select app.uid()), now())
  on conflict (id) do update
    set data = excluded.data, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
end;
$$;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
