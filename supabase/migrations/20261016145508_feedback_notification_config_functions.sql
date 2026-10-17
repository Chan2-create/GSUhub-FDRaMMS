-- Rating the service, reading notifications, and saving settings
-- (Objective 1, M3): FeedbackRepositoryImpl.rate,
-- NotificationRepositoryImpl.markAsRead / markAllAsRead and
-- ConfigRepositoryImpl's saves.

-- The person who filed a report rates the completed work, once, and the
-- rating closes the report (3.C). The three ratings stay separate (§1.5).
-- Rating again after a rating that already landed is a retry and does
-- nothing.
create or replace function app.rate_service(
  _report_id text,
  _response_time integer,
  _service_quality integer,
  _overall_satisfaction integer,
  _comments text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller text := (select app.uid());
  report public.damage_reports;
  rated_by text;
begin
  if not (select app.is_requestor()) then
    perform app.refuse('PT403', 'You do not have permission to perform this action.');
  end if;

  select * into report from public.damage_reports r where r.id = _report_id for update;
  if not found then
    perform app.refuse('PT404', 'No damage report ' || _report_id);
  end if;
  if report.reporter_id <> caller then
    perform app.refuse('PT409', 'Only the person who filed this report can rate the service.');
  end if;

  select f.submitted_by into rated_by from public.feedback f where f.id = _report_id;
  if found then
    if rated_by = caller and report.status = 'closed' then
      return;
    end if;
    perform app.refuse('PT409', 'This service has already been rated.');
  end if;

  if report.status <> 'completed' or report.work_order_id is null then
    perform app.refuse('PT409', 'Only completed work can be rated. This report is '
      || lower(app.report_timeline_label(report.status)) || '.');
  end if;
  if least(_response_time, _service_quality, _overall_satisfaction) < 1
     or greatest(_response_time, _service_quality, _overall_satisfaction) > 5 then
    perform app.refuse('PT422', 'Each rating must be from 1 to 5.');
  end if;

  insert into public.feedback (id, work_order_id, report_id, submitted_by, response_time_rating,
    service_quality_rating, overall_satisfaction_rating, comments)
  values (_report_id, report.work_order_id, _report_id, caller, _response_time,
    _service_quality, _overall_satisfaction, app.blank_to_null(_comments));

  update public.damage_reports r set status = 'closed', updated_at = now() where r.id = _report_id;

  perform app.record_report_move(_report_id, 'closed', 'completed');
  perform app.audit('statusChanged', 'damage_reports', _report_id,
    'Rated the service and closed the report',
    jsonb_build_object('from', 'completed', 'to', 'closed', 'feedbackId', _report_id));
end;
$$;

-- One's own notification, marked read; never unread again.
create or replace function app.mark_notification_read(_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.require_active();
  perform 1 from public.notifications n where n.id = _id and n.recipient_id = (select app.uid());
  if not found then
    perform app.refuse('PT404', 'That notification no longer exists.');
  end if;
  update public.notifications n
  set is_read = true, read_at = now()
  where n.id = _id and not n.is_read;
end;
$$;

create or replace function app.mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app.require_active();
  update public.notifications n
  set is_read = true, read_at = now()
  where n.recipient_id = (select app.uid()) and not n.is_read;
end;
$$;

-- One of the three settings documents, saved whole by an administrator:
-- the keyword dictionary, the prioritization scheme, duplicate detection.
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
  insert into public.app_config (id, data, updated_by, updated_at)
  values (_id, _data - 'updatedAt' - 'updatedBy', (select app.uid()), now())
  on conflict (id) do update
    set data = excluded.data, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
end;
$$;

-- ------------------------------------------------------------ the API

create or replace function public.rate_service(
  report_id text, response_time integer, service_quality integer,
  overall_satisfaction integer, comments text default null
)
returns void language sql security invoker set search_path = ''
as $$
  select app.rate_service(report_id, response_time, service_quality, overall_satisfaction, comments);
$$;

create or replace function public.mark_notification_read(id text)
returns void language sql security invoker set search_path = ''
as $$ select app.mark_notification_read(id); $$;

create or replace function public.mark_all_notifications_read()
returns void language sql security invoker set search_path = ''
as $$ select app.mark_all_notifications_read(); $$;

create or replace function public.update_config(id text, data jsonb)
returns void language sql security invoker set search_path = ''
as $$ select app.update_config(id, data); $$;

revoke execute on function
  public.rate_service(text, integer, integer, integer, text),
  public.mark_notification_read(text),
  public.mark_all_notifications_read(),
  public.update_config(text, jsonb)
from public, anon;
grant execute on function
  public.rate_service(text, integer, integer, integer, text),
  public.mark_notification_read(text),
  public.mark_all_notifications_read(),
  public.update_config(text, jsonb)
to authenticated, service_role;

revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
