-- A report keeps what the requestor chose, and says what the administrator
-- decided (Chris, 2026-11-16; docs/architecture_decisions.md §42).
--
-- The columns were already apart: `requestor_category` and
-- `requestor_priority` are what was filed, `category` and
-- `official_priority` what the review decides, `recommended_priority` and
-- `priority_score` what the formula says. This migration makes three
-- things true that were only true as long as nobody got it wrong:
--
--   1. What the requestor chose can never be changed afterwards, by any
--      function, now or later (a trigger).
--   2. A review cannot silently replace another administrator's: the
--      console says which version of the report it was looking at, and a
--      report changed since then is refused, with the name of who changed
--      it.
--   3. The audit entry of a review holds the whole decision: what the
--      requestor chose, what the classification and the official priority
--      were and became, and the reason, when one was given.
--
-- A review that changes nothing writes nothing, so a save sent twice, or
-- retried after its answer was lost, leaves one audit entry and not two.

-- ------------------------------------------------- what was filed stays

create or replace function app.keep_requestor_selection()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.requestor_priority is distinct from old.requestor_priority
     or new.requestor_category is distinct from old.requestor_category then
    raise exception using
      errcode = 'PT409',
      message = 'What the requestor chose when filing a report is kept as filed. '
        || 'The administrator''s review is recorded beside it.';
  end if;
  return new;
end;
$$;

create trigger damage_reports_keep_requestor_selection
  before update of requestor_priority, requestor_category on public.damage_reports
  for each row execute function app.keep_requestor_selection();

-- ------------------------------------------------------------ the review

-- Replaced, not altered: two more parameters, both optional, so a console
-- built before this migration still calls it as it did.
drop function public.record_assessment(text, text, boolean, integer, integer, integer, integer,
  double precision, text, text);
drop function app.record_assessment(text, text, boolean, integer, integer, integer, integer,
  double precision, text, text);

-- The administrator's assessment (4.C): the damage type, the four ratings,
-- the score and recommendation, and the official priority. Only while no
-- work order has been raised.
--
-- `_expected_updated_at` is the report's `updated_at` as the console last
-- read it. The app's clock keeps milliseconds and the database's
-- microseconds, hence the millisecond of grace.
create or replace function app.record_assessment(
  _report_id text,
  _category text,
  _classified_automatically boolean,
  _severity_rating integer,
  _safety_risk_rating integer,
  _frequency_rating integer,
  _location_importance_rating integer,
  _priority_score double precision,
  _recommended_priority text,
  _official_priority text,
  _reason text default null,
  _expected_updated_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.damage_reports;
  score text := to_char(_priority_score, 'FM990.00');
  reason text := nullif(btrim(coalesce(_reason, '')), '');
  priority text;
  changer_id text;
  changer_name text;
begin
  perform app.require_admin();
  if least(_severity_rating, _safety_risk_rating, _frequency_rating, _location_importance_rating) < 1
     or greatest(_severity_rating, _safety_risk_rating, _frequency_rating, _location_importance_rating) > 4 then
    perform app.refuse('PT422', 'Each rating must be from 1 to 4.');
  end if;
  if _priority_score < 1 or _priority_score > 4 then
    perform app.refuse('PT422', 'The priority score must be between 1.00 and 4.00.');
  end if;
  if char_length(reason) > 500 then
    perform app.refuse('PT422', 'Keep the reason to 500 characters.');
  end if;

  select * into stored from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if stored.duplicate_of is not null then
    perform app.refuse('PT409', 'This report was merged into another. Assess that report instead.');
  end if;
  if stored.work_order_id is not null or stored.status not in ('submitted', 'underReview', 'approved') then
    perform app.refuse('PT409', 'This report is ' || app.report_status_label(stored.status)
      || '. Its damage type and priority are set before a work order is raised, and cannot change now.');
  end if;

  -- Already as asked: a save sent twice, or sent again after its answer
  -- was lost. Checked before the version, which the first one moved.
  if stored.official_priority is not distinct from _official_priority
     and stored.category is not distinct from _category
     and stored.classified_automatically is not distinct from _classified_automatically
     and stored.severity_rating is not distinct from _severity_rating
     and stored.safety_risk_rating is not distinct from _safety_risk_rating
     and stored.frequency_rating is not distinct from _frequency_rating
     and stored.location_importance_rating is not distinct from _location_importance_rating
     and stored.recommended_priority is not distinct from _recommended_priority
     and stored.priority_score is not distinct from _priority_score
     and reason is null then
    return;
  end if;

  if _expected_updated_at is not null
     and stored.updated_at > _expected_updated_at + interval '1 millisecond' then
    -- Named only when the trail says who: not every change to a report
    -- is an entry of its own (a duplicate merged into it is not).
    select a.actor_id, a.actor_name into changer_id, changer_name
      from public.audit_logs a
      where a.entity_type = 'damage_reports' and a.entity_id = _report_id
        and a."timestamp" > _expected_updated_at + interval '1 millisecond'
      order by a."timestamp" desc
      limit 1;
    perform app.refuse('PT409',
      case
        when changer_id is null then 'This report was changed'
        when changer_id = (select app.uid()) then 'You changed this report somewhere else'
        else changer_name || ' changed this report'
      end || ' after you opened it here. The latest details are shown now: check them, then save again.');
  end if;

  update public.damage_reports r
  set category = _category,
      classified_automatically = _classified_automatically,
      severity_rating = _severity_rating,
      safety_risk_rating = _safety_risk_rating,
      frequency_rating = _frequency_rating,
      location_importance_rating = _location_importance_rating,
      priority_score = _priority_score,
      recommended_priority = _recommended_priority,
      official_priority = _official_priority,
      reviewed_by = (select app.uid()),
      reviewed_at = now(),
      updated_at = now()
  where r.id = _report_id;

  -- Whether the official priority follows the recommendation or departs
  -- from it.
  priority := case
    when _official_priority = _recommended_priority then
      'official priority ' || upper(_official_priority) || ' as recommended (score ' || score || ')'
    else
      'official priority ' || upper(_official_priority) || ', '
        || case when app.priority_rank(_official_priority) > app.priority_rank(_recommended_priority)
             then 'raised' else 'lowered' end
        || ' from the recommended ' || upper(_recommended_priority) || ' (score ' || score || ')'
  end;

  perform app.audit('updated', 'damage_reports', _report_id,
    'Classified as ' || app.category_label(_category) || '; ' || priority
      || coalesce('. Reason: ' || reason, ''),
    jsonb_build_object(
      -- What the requestor filed: never changed, kept here so the entry
      -- reads whole on its own.
      'requestor', jsonb_build_object(
        'category', stored.requestor_category,
        'priority', stored.requestor_priority
      ),
      'category', jsonb_build_object('from', stored.category, 'to', _category),
      'classifiedAutomatically', _classified_automatically,
      'ratings', jsonb_build_object(
        'severity', _severity_rating,
        'safetyRisk', _safety_risk_rating,
        'frequency', _frequency_rating,
        'locationImportance', _location_importance_rating
      ),
      'priorityScore', _priority_score,
      'recommendedPriority', _recommended_priority,
      'officialPriority', jsonb_build_object('from', stored.official_priority, 'to', _official_priority),
      -- The first review of the report, or a change to an earlier one.
      'firstReview', stored.official_priority is null
    ) || case when reason is null then '{}'::jsonb else jsonb_build_object('reason', reason) end);
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.record_assessment(
  report_id text, category text, classified_automatically boolean,
  severity_rating integer, safety_risk_rating integer, frequency_rating integer,
  location_importance_rating integer, priority_score double precision,
  recommended_priority text, official_priority text,
  reason text default null, expected_updated_at timestamptz default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.record_assessment(report_id, category, classified_automatically, severity_rating,
    safety_risk_rating, frequency_rating, location_importance_rating, priority_score,
    recommended_priority, official_priority, reason, expected_updated_at);
$$;

revoke execute on function
  public.record_assessment(text, text, boolean, integer, integer, integer, integer,
    double precision, text, text, text, timestamptz)
from public, anon;
grant execute on function
  public.record_assessment(text, text, boolean, integer, integer, integer, integer,
    double precision, text, text, text, timestamptz)
to authenticated, service_role;

-- These two only. A grant on every function in `app`, as the earlier
-- migrations end with, would hand the scheduler's own
-- `app.sweep_tool_requests` back to every signed-in user.
revoke execute on function
  app.record_assessment(text, text, boolean, integer, integer, integer, integer,
    double precision, text, text, text, timestamptz),
  app.keep_requestor_selection()
from public, anon;
grant execute on function
  app.record_assessment(text, text, boolean, integer, integer, integer, integer,
    double precision, text, text, text, timestamptz)
to authenticated, service_role;
