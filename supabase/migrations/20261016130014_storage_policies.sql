-- Photos (Objective 1, item 2): one private bucket, and policies that do
-- what firebase/storage.rules did, reading the caller's role from
-- `users` by uid (the Firebase rules read it from Firestore, which stops
-- working once users live here).
--
-- Every path starts with what it belongs to, then whose it is:
--
--   damage_reports/{uid}/{reportId}/{file}          the reporter's evidence
--   accomplishment_reports/{uid}/{reportId}/{file}  the technician's
--   tasks/{uid}/{taskId}/{file}                     a task's proof
--   inventory_items/{itemId}/{file}                 a material's photo
--   users/{uid}/{file}                              a profile image
--
-- The uid in the path is what lets a policy say "only your own report's
-- folder": a report's photos are uploaded before the report exists (its id
-- is reserved first), so its owner cannot be looked up yet.
--
-- The bucket itself refuses anything that is not an image or is over
-- 10 MB; the policies also check the file name's extension. No UPDATE
-- policy: a photo is never overwritten (storage.rules `update: false`).
-- Only an administrator deletes.
--
-- Reads are tighter than storage.rules, which let any active account read
-- any photo: a report's photos are its reporter's, the technicians' on its
-- work order, and the administrators'.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 10485760, array['image/*'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The parts of an object's path: storage/kind/owner/…/file.
create or replace function app.path_parts(object_name text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select string_to_array(object_name, '/');
$$;

create or replace function app.is_image_name(object_name text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(substring(object_name from '\.([A-Za-z0-9]+)$'))
    in ('jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif');
$$;

-- Whether the caller may upload [object_name].
create or replace function app.can_upload_photo(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  parts text[] := app.path_parts(object_name);
  depth integer := coalesce(array_length(parts, 1), 0);
  caller text := app.uid();
begin
  if caller is null or not app.is_active() or not app.is_image_name(object_name) then
    return false;
  end if;
  case parts[1]
    when 'damage_reports' then
      return depth = 4 and parts[2] = caller and app.is_requestor();
    when 'accomplishment_reports' then
      return depth = 4 and parts[2] = caller and app.is_personnel();
    when 'tasks' then
      return depth = 4
        and parts[2] = caller
        and app.is_personnel()
        and exists (
          select 1 from public.tasks t
          where t.id = parts[3] and t.assigned_to = caller
        );
    when 'inventory_items' then
      return depth = 3 and app.is_admin();
    when 'users' then
      return depth = 3 and parts[2] = caller;
    else
      return false;
  end case;
end;
$$;

-- Whether the caller may read (download, or sign a URL for) [object_name].
create or replace function app.can_read_photo(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  parts text[] := app.path_parts(object_name);
  caller text := app.uid();
begin
  if caller is null or not app.is_active() then
    return false;
  end if;
  if app.is_admin() then
    return true;
  end if;
  case parts[1]
    when 'damage_reports' then
      return parts[2] = caller
        or exists (
          select 1 from public.damage_reports r
          where r.id = parts[3]
            and r.reporter_id = parts[2]
            and r.work_order_id is not null
            and app.is_assigned_to(r.work_order_id)
        );
    when 'accomplishment_reports', 'tasks' then
      return parts[2] = caller;
    when 'inventory_items', 'users' then
      return true;
    else
      return false;
  end case;
end;
$$;

revoke execute on function
  app.path_parts(text),
  app.is_image_name(text),
  app.can_upload_photo(text),
  app.can_read_photo(text)
from public, anon;
grant execute on function
  app.path_parts(text),
  app.is_image_name(text),
  app.can_upload_photo(text),
  app.can_read_photo(text)
to authenticated, service_role;

create policy photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and app.can_upload_photo(name));

create policy photos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and app.can_read_photo(name));

create policy photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (select app.is_admin()));
