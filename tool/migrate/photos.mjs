// Copies the photos of migrated rows from Firebase Storage to the private
// Supabase bucket, and points the rows at them (Objective 1).
//
// Each photo is read through the download URL the row stores (they carry
// their own access token), uploaded under the path the bucket's policies
// expect (supabase/migrations/*_storage_policies.sql), and replaced in the
// row by a ten-year signed URL — the same kind of URL the app stores for a
// new photo. Uploads overwrite, so a second run after a failed one is safe.

import { isFirebasePhoto, photoColumns, photoFileName } from './transform.mjs';

const signedUrlSeconds = 3650 * 24 * 60 * 60;

/// The photos [tables] would have copied: [{table, id, url, object}].
export function photosToCopy(tables) {
  const photos = [];
  for (const [table, { column, folder }] of Object.entries(photoColumns)) {
    for (const row of tables[table] ?? []) {
      const value = row[column];
      const urls = Array.isArray(value) ? value : value ? [value] : [];
      for (const url of urls) {
        if (isFirebasePhoto(url)) {
          photos.push({ table, id: row.id, url, object: `${folder(row)}/${photoFileName(url)}` });
        }
      }
    }
  }
  return photos;
}

/// Copies every photo and rewrites the rows in place. [supabaseUrl] and
/// [serviceRoleKey] are the hosted (or local) project's; the key never
/// leaves this machine. Returns the failures, as messages.
export async function copyPhotos(tables, { supabaseUrl, serviceRoleKey, log = console.log, fetchImpl = fetch }) {
  // A secret key (sb_secret_...) goes in `apikey` only: the gateway turns it
  // into a service-role token itself, and refuses it as a bearer token. A
  // legacy service_role key is a JWT and goes in both.
  const headers = serviceRoleKey.startsWith('sb_secret_')
    ? { apikey: serviceRoleKey }
    : { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` };
  const failures = [];
  const replaced = new Map();
  const photos = photosToCopy(tables);
  for (const [n, photo] of photos.entries()) {
    try {
      const source = await fetchImpl(photo.url);
      if (!source.ok) throw new Error(`download answered ${source.status}`);
      const bytes = new Uint8Array(await source.arrayBuffer());
      const type = source.headers.get('content-type') ?? 'image/jpeg';

      const upload = await fetchImpl(`${supabaseUrl}/storage/v1/object/photos/${photo.object}`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': type, 'x-upsert': 'true' },
        body: bytes,
      });
      if (!upload.ok) throw new Error(`upload answered ${upload.status} ${await upload.text()}`);

      const sign = await fetchImpl(`${supabaseUrl}/storage/v1/object/sign/photos/${photo.object}`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ expiresIn: signedUrlSeconds }),
      });
      if (!sign.ok) throw new Error(`signing answered ${sign.status}`);
      const { signedURL } = await sign.json();
      replaced.set(photo.url, `${supabaseUrl}/storage/v1${signedURL}`);
      if ((n + 1) % 25 === 0) log(`  ${n + 1} of ${photos.length} photos copied`);
    } catch (error) {
      failures.push(`${photo.table} ${photo.id}: ${photo.url.slice(0, 80)}…: ${error.message}`);
    }
  }

  for (const [table, { column }] of Object.entries(photoColumns)) {
    for (const row of tables[table] ?? []) {
      const value = row[column];
      if (Array.isArray(value)) row[column] = value.map((url) => replaced.get(url) ?? url);
      else if (value) row[column] = replaced.get(value) ?? value;
    }
  }
  return failures;
}
