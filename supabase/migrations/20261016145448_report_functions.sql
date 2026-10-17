-- Damage reports (Objective 1, M3): filing, review, classification and
-- duplicates. DamageReportRepositoryImpl's transactions, and the
-- damage_reports rules in firebase/firestore.rules.
--
-- Every move writes its timeline entry and the requestor's notice in the
-- same transaction (app.record_report_move), and an audit entry.

-- A requestor filing a report (3.C), under the id the app chose when the
-- form opened: photos were uploaded under it first. Filing twice under the
-- same id is a retry and does nothing.
--
-- The keyword classifier runs on the phone (4.A), so a report may arrive
-- with a category, marked automatic; an administrator confirms it in
-- review (4.C). Nothing else an administrator decides can be set here.
create or replace function app.submit_report(
  _id text,
  _title text,
  _description text,
  _requestor_priority text,
  _requestor_category text default null,
  _category text default null,
  _facility_id text default null,
  _facility_name text default null,
  _location_description text default null,
  _asset_id text default null,
  _latitude double precision default null,
  _longitude double precision default null,
  _photo_urls text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  existing_reporter text;
  clean_title text := btrim(coalesce(_title, ''));
  clean_description text := btrim(coalesce(_description, ''));
begin
  if not (select app.is_requestor()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;

  select r.reporter_id into existing_reporter from public.damage_reports r where r.id = _id;
  if found then
    if existing_reporter = caller then
      return;
    end if;
    perform app.refuse('PT409', 'This report could not be filed. Please try again.');
  end if;

  if clean_title = '' or clean_description = '' then
    perform app.refuse('PT422', 'Give the report a title and a description.');
  end if;

  insert into public.damage_reports (
    id, reporter_id, reporter_name, title, description, requestor_priority,
    requestor_category, category, classified_automatically, status,
    facility_id, facility_name, location_description, asset_id,
    latitude, longitude, photo_urls
  )
  select
    _id, caller, u.full_name, clean_title, clean_description, _requestor_priority,
    _requestor_category, _category, _category is not null, 'submitted',
    _facility_id, _facility_name, _location_description, _asset_id,
    _latitude, _longitude, coalesce(_photo_urls, '{}')
  from public.users u
  where u.id = caller;

  perform app.record_report_move(_id, 'submitted');
  perform app.audit('created', 'damage_reports', _id, 'Submitted "' || clean_title || '"',
    jsonb_build_object(
      'facilityId', _facility_id,
      'photos', cardinality(coalesce(_photo_urls, '{}')),
      'geoTagged', _latitude is not null
    ));
end;
$$;

-- The administrator's assessment (4.C): the damage type, the four ratings,
-- the score and recommendation, and the official priority. Only while no
-- work order has been raised.
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
  _official_priority text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.damage_reports;
  score text := to_char(_priority_score, 'FM990.00');
  priority text;
begin
  perform app.require_admin();
  if least(_severity_rating, _safety_risk_rating, _frequency_rating, _location_importance_rating) < 1
     or greatest(_severity_rating, _safety_risk_rating, _frequency_rating, _location_importance_rating) > 4 then
    perform app.refuse('PT422', 'Each rating must be from 1 to 4.');
  end if;
  if _priority_score < 1 or _priority_score > 4 then
    perform app.refuse('PT422', 'The priority score must be between 1.00 and 4.00.');
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

  -- DamageReportRepositoryImpl.describeAssessment: whether the official
  -- priority follows the recommendation or departs from it.
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
    'Classified as ' || app.category_label(_category) || '; ' || priority,
    jsonb_build_object(
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
      'officialPriority', jsonb_build_object('from', stored.official_priority, 'to', _official_priority)
    ));
end;
$$;

-- The moves an administrator makes while reviewing: under review,
-- approved, rejected (with a reason). Every later stage moves with the
-- report's work order.
create or replace function app.transition_report(_report_id text, _to text, _reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  stored public.damage_reports;
  reason text := btrim(coalesce(_reason, ''));
  is_decision boolean := _to in ('approved', 'rejected');
begin
  perform app.require_admin();
  if _to not in ('underReview', 'approved', 'rejected') then
    perform app.refuse('PT422', 'A report moves to ' || app.report_status_label(_to)
      || ' with its work order, not on its own.');
  end if;
  if _to = 'rejected' and reason = '' then
    perform app.refuse('PT422', 'Give a reason for rejecting this report.');
  end if;

  select * into stored from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if stored.status = _to then
    return;
  end if;
  if not app.report_can_move(stored.status, _to) then
    perform app.refuse('PT409', 'A report cannot move from ' || app.report_status_label(stored.status)
      || ' to ' || app.report_status_label(_to) || '.');
  end if;

  update public.damage_reports r
  set status = _to,
      updated_at = now(),
      reviewed_by = case when is_decision then (select app.uid()) else r.reviewed_by end,
      reviewed_at = case when is_decision then now() else r.reviewed_at end,
      rejection_reason = case when _to = 'rejected' then reason else r.rejection_reason end
  where r.id = _report_id;

  perform app.record_report_move(_report_id, _to, stored.status,
    case when _to = 'rejected' then reason end);
  perform app.audit('statusChanged', 'damage_reports', _report_id,
    case when _to = 'rejected' then 'Rejected: ' || reason
      else 'Status changed from ' || app.report_status_label(stored.status)
        || ' to ' || app.report_status_label(_to) end,
    jsonb_build_object('from', stored.status, 'to', _to)
      || case when _to = 'rejected' then jsonb_build_object('reason', reason) else '{}' end);
end;
$$;

-- Folds duplicates into the report they repeat (4.C). All or nothing:
-- every report is checked before any is written, so a partial merge cannot
-- happen.
create or replace function app.merge_duplicates(_parent_id text, _duplicate_ids text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent public.damage_reports;
  duplicate public.damage_reports;
  ids text[];
  dup_id text;
begin
  perform app.require_admin();
  select array_agg(distinct d) into ids from unnest(coalesce(_duplicate_ids, '{}')) d;
  if ids is null then
    perform app.refuse('PT422', 'Choose the reports to merge.');
  end if;
  if _parent_id = any (ids) then
    perform app.refuse('PT422', 'A report cannot be merged into itself.');
  end if;

  -- Locked in one order, so two merges at once cannot deadlock.
  perform 1 from public.damage_reports r where r.id = any (ids || _parent_id) order by r.id for update;

  select * into parent from public.damage_reports r where r.id = _parent_id;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _parent_id);
  end if;
  if parent.duplicate_of is not null or not app.report_is_open(parent.status) then
    perform app.refuse('PT409', 'Report ' || app.display_id(parent.id, 'DR') || ' is '
      || case when parent.duplicate_of is not null then 'itself merged'
           else app.report_status_label(parent.status) end
      || ', so no report can be merged into it.');
  end if;

  foreach dup_id in array ids loop
    select * into duplicate from public.damage_reports r where r.id = dup_id;
    if not found then
      perform app.refuse('PT404', 'No damage report ' || dup_id);
    end if;
    if duplicate.duplicate_of is not null or duplicate.work_order_id is not null
       or not app.report_can_move(duplicate.status, 'merged') then
      perform app.refuse('PT409', 'Report ' || app.display_id(duplicate.id, 'DR') || ' is '
        || case when duplicate.duplicate_of is not null then 'already merged'
             else app.report_status_label(duplicate.status) end
        || '. Only a report still awaiting review can be merged.');
    end if;
  end loop;

  foreach dup_id in array ids loop
    select * into duplicate from public.damage_reports r where r.id = dup_id;
    update public.damage_reports r
    set duplicate_of = _parent_id,
        status = 'merged',
        reviewed_by = (select app.uid()),
        reviewed_at = now(),
        updated_at = now()
    where r.id = dup_id;
    perform app.record_report_move(dup_id, 'merged', duplicate.status, null, null, _parent_id);
    perform app.audit('merged', 'damage_reports', dup_id,
      'Merged into ' || app.display_id(_parent_id, 'DR') || ' as a duplicate',
      jsonb_build_object('from', duplicate.status, 'to', 'merged', 'parent', _parent_id));
  end loop;

  update public.damage_reports r set updated_at = now() where r.id = _parent_id;
end;
$$;

-- Two reports an administrator judged not to be duplicates: noted on both,
-- so the pair is never flagged again whichever is opened next.
create or replace function app.keep_separate(_report_id text, _other_report_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.require_admin();
  if _report_id = _other_report_id then
    perform app.refuse('PT422', 'A report cannot be compared with itself.');
  end if;
  perform 1 from public.damage_reports r
    where r.id in (_report_id, _other_report_id) order by r.id for update;
  if not exists (select 1 from public.damage_reports r where r.id = _report_id) then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if not exists (select 1 from public.damage_reports r where r.id = _other_report_id) then
    perform app.refuse('PT404', 'No damage report ' || _other_report_id);
  end if;

  update public.damage_reports r
  set dismissed_duplicate_ids = case
        when (case r.id when _report_id then _other_report_id else _report_id end) = any (r.dismissed_duplicate_ids)
          then r.dismissed_duplicate_ids
        else r.dismissed_duplicate_ids || (case r.id when _report_id then _other_report_id else _report_id end)
      end,
      updated_at = now()
  where r.id in (_report_id, _other_report_id);

  perform app.audit('updated', 'damage_reports', _report_id,
    'Kept separate from ' || app.display_id(_other_report_id, 'DR') || ': not a duplicate',
    jsonb_build_object('notDuplicateOf', _other_report_id));
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.submit_report(
  id text, title text, description text, requestor_priority text,
  requestor_category text default null, category text default null,
  facility_id text default null, facility_name text default null,
  location_description text default null, asset_id text default null,
  latitude double precision default null, longitude double precision default null,
  photo_urls text[] default '{}'
)
returns void language sql security invoker set search_path = ''
as $$
  select app.submit_report(id, title, description, requestor_priority, requestor_category,
    category, facility_id, facility_name, location_description, asset_id, latitude,
    longitude, photo_urls);
$$;

create or replace function public.record_assessment(
  report_id text, category text, classified_automatically boolean,
  severity_rating integer, safety_risk_rating integer, frequency_rating integer,
  location_importance_rating integer, priority_score double precision,
  recommended_priority text, official_priority text
)
returns void language sql security invoker set search_path = ''
as $$
  select app.record_assessment(report_id, category, classified_automatically, severity_rating,
    safety_risk_rating, frequency_rating, location_importance_rating, priority_score,
    recommended_priority, official_priority);
$$;

create or replace function public.transition_report(report_id text, to_status text, reason text default null)
returns void language sql security invoker set search_path = ''
as $$ select app.transition_report(report_id, to_status, reason); $$;

create or replace function public.merge_duplicates(parent_id text, duplicate_ids text[])
returns void language sql security invoker set search_path = ''
as $$ select app.merge_duplicates(parent_id, duplicate_ids); $$;

create or replace function public.keep_separate(report_id text, other_report_id text)
returns void language sql security invoker set search_path = ''
as $$ select app.keep_separate(report_id, other_report_id); $$;

revoke execute on function
  public.submit_report(text, text, text, text, text, text, text, text, text, text,
    double precision, double precision, text[]),
  public.record_assessment(text, text, boolean, integer, integer, integer, integer,
    double precision, text, text),
  public.transition_report(text, text, text),
  public.merge_duplicates(text, text[]),
  public.keep_separate(text, text)
from public, anon;
grant execute on function
  public.submit_report(text, text, text, text, text, text, text, text, text, text,
    double precision, double precision, text[]),
  public.record_assessment(text, text, boolean, integer, integer, integer, integer,
    double precision, text, text),
  public.transition_report(text, text, text),
  public.merge_duplicates(text, text[]),
  public.keep_separate(text, text)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
