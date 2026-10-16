-- Photo storage policies (Objective 1, item 2). The Firebase Storage rules
-- had no tests.
--
-- Here: who may put a file where, and who may read it. The bucket's own
-- limits (images only, 10 MB) are enforced by the Storage service before
-- any row is written; this file checks they are set, and
-- tool/storage_api_test.mjs uploads real files against the local stack to
-- show them refusing a PDF and an 11 MB image.

begin;
select tests.create_fixtures();
select plan(22);

create temporary table uploads (who text, uid text, path text, expected text, why text);
insert into uploads values
  ('requestor', 'u-req', 'damage_reports/u-req/r-new/photo-1.jpg', 'ok', 'uploads an image to their own report folder'),
  ('requestor', 'u-req', 'damage_reports/u-req/r-new/photo-2.PNG', 'ok', 'in any image type'),
  ('requestor', 'u-req', 'damage_reports/u-req2/r-new/photo-1.jpg', '42501', 'cannot upload to another reporter''s folder'),
  ('requestor', 'u-req', 'damage_reports/u-req/r-new/notes.pdf', '42501', 'cannot upload a file that is not an image'),
  ('inactive requestor', 'u-inactive', 'damage_reports/u-inactive/r-new/photo-1.jpg', '42501', 'cannot upload once deactivated'),
  ('pending requestor', 'u-pending', 'damage_reports/u-pending/r-new/photo-1.jpg', '42501', 'cannot upload before approval'),
  ('technician', 'u-tech', 'damage_reports/u-tech/r-new/photo-1.jpg', '42501', 'does not file damage reports'),
  ('technician', 'u-tech', 'tasks/u-tech/t-1/proof-1.jpg', 'ok', 'adds proof to their own task'),
  ('technician', 'u-tech', 'tasks/u-tech/t-2/proof-1.jpg', '42501', 'not to another technician''s task'),
  ('technician', 'u-tech', 'accomplishment_reports/u-tech/ac-new/after-1.jpg', 'ok', 'uploads the finished work'),
  ('requestor', 'u-req', 'inventory_items/i-1/photo.jpg', '42501', 'cannot set a material''s photo'),
  ('admin', 'u-admin', 'inventory_items/i-1/photo.jpg', 'ok', 'sets a material''s photo'),
  ('anonymous', null, 'damage_reports/u-req/r-new/photo-3.jpg', '42501', 'with no sign-in, nothing is uploaded');

select is(
  tests.attempt(uid, format($q$insert into storage.objects (bucket_id, name) values ('photos', %L)$q$, path)),
  expected,
  format('%s %s', who, why)
)
from uploads
order by path, who;

-- Reading: a report's photos are its reporter's, its technicians', and
-- the administrators'. (The uploads above are cleared first.)
delete from storage.objects;
insert into storage.objects (bucket_id, name) values
  ('photos', 'damage_reports/u-req/r-1/photo-1.jpg'),
  ('photos', 'damage_reports/u-req/r-3/photo-1.jpg'),
  ('photos', 'damage_reports/u-req2/r-2/photo-1.jpg');

select is(
  tests.query_as('u-req2', $$select count(*)::text from storage.objects where name like 'damage_reports/u-req/%'$$),
  '0',
  'a requestor cannot read another reporter''s photos'
);
select is(
  tests.query_as('u-req', $$select count(*)::text from storage.objects where name like 'damage_reports/u-req/%'$$),
  '2',
  'a requestor reads their own'
);
select is(
  tests.query_as('u-tech', $$select string_agg(name, ',' order by name) from storage.objects where name like 'damage_reports/%'$$),
  'damage_reports/u-req/r-1/photo-1.jpg',
  'a technician reads the photos of the report they are working, and no other'
);
select is(
  tests.query_as('u-admin', $$select count(*)::text from storage.objects where name like 'damage_reports/%'$$),
  '3',
  'an administrator reads them all'
);
select is(
  tests.query_as('u-inactive', $$select count(*)::text from storage.objects$$),
  '0',
  'a deactivated account reads nothing'
);

-- Only an administrator removes a photo; nobody overwrites one.
select is(
  tests.query_as('u-req', $$with gone as (delete from storage.objects where name = 'damage_reports/u-req/r-1/photo-1.jpg' returning 1) select count(*)::text from gone$$),
  '0',
  'a requestor cannot delete even their own photo'
);
select is(
  tests.attempt('u-req', $$update storage.objects set name = 'damage_reports/u-req/r-1/other.jpg' where name = 'damage_reports/u-req/r-1/photo-1.jpg'$$),
  'ok',
  'an update statement runs…'
);
select is(
  (select count(*)::int from storage.objects where name = 'damage_reports/u-req/r-1/photo-1.jpg'),
  1,
  '…but changes nothing: there is no update policy'
);

-- The bucket.
select is(
  (select array[public::text, file_size_limit::text, array_to_string(allowed_mime_types, ',')]
     from storage.buckets where id = 'photos'),
  array['false', '10485760', 'image/*'],
  'the photos bucket is private, 10 MB, images only'
);

select * from finish();
rollback;
