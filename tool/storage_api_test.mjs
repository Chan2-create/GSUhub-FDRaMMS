// Uploads real files to the local Supabase stack's `photos` bucket and
// checks what the Storage service lets through (Objective 1, item 2).
//
// supabase/tests/storage_policies.test.sql covers the policies: who may
// write where, and who may read what. The bucket's own limits (images
// only, 10 MB) are checked by the Storage service before a row is ever
// written, so only a real upload shows them working. This does that.
//
//   npx supabase start
//   npx supabase db reset          (loads supabase/seed.sql: the accounts)
//   node tool/storage_api_test.mjs
//
// LOCAL ONLY. It signs its own short-lived tokens with the local stack's
// JWT secret, and refuses to run against anything but localhost.

import { createHmac, randomUUID } from 'node:crypto';
import { execSync } from 'node:child_process';

// Seeded accounts (tool/seed.dart).
const owner = 'seed-faculty-0001'; // active requestor
const otherReporter = 'seed-faculty-0002'; // active requestor
const inactive = 'seed-faculty-0004'; // deactivated requestor
const admin = 'seed-admin-0001';

function localStack() {
  let env = {};
  try {
    const out = execSync('npx supabase status -o env', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    for (const line of out.split(/\r?\n/)) {
      const match = /^([A-Z_]+)="?(.*?)"?$/.exec(line.trim());
      if (match) env[match[1]] = match[2];
    }
  } catch (error) {
    console.error('Could not read the local stack. Is it running?  npx supabase start');
    console.error(String(error.stderr ?? error.message).trim());
    process.exit(1);
  }
  const url = env.API_URL;
  const apiKey = env.ANON_KEY || env.PUBLISHABLE_KEY;
  const secret = env.JWT_SECRET;
  if (!url || !apiKey || !secret) {
    console.error('`supabase status -o env` did not give API_URL, ANON_KEY and JWT_SECRET.');
    process.exit(1);
  }
  const host = new URL(url).hostname;
  if (host !== '127.0.0.1' && host !== 'localhost') {
    console.error(`Refusing to run against ${url}: this test is for the local stack only.`);
    process.exit(1);
  }
  return { url, apiKey, secret };
}

const { url, apiKey, secret } = localStack();

const base64url = (value) => Buffer.from(value).toString('base64url');

/// A token shaped like the ones firebase-token-exchange issues: the
/// Firebase uid as `sub`, five minutes to live.
function tokenFor(uid) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = base64url(JSON.stringify({ sub: uid, role: 'authenticated', aud: 'authenticated', iat: now, exp: now + 300 }));
  const signature = createHmac('sha256', secret).update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${signature}`;
}

const headersFor = (uid) => ({ apikey: apiKey, Authorization: `Bearer ${tokenFor(uid)}` });

async function upload(uid, path, body, contentType, { upsert = false } = {}) {
  const response = await fetch(`${url}/storage/v1/object/photos/${path}`, {
    method: 'POST',
    headers: { ...headersFor(uid), 'Content-Type': contentType, 'x-upsert': String(upsert) },
    body,
  });
  return { ok: response.ok, status: response.status, message: await response.text() };
}

async function download(uid, path) {
  const response = await fetch(`${url}/storage/v1/object/authenticated/photos/${path}`, { headers: headersFor(uid) });
  return { ok: response.ok, status: response.status, message: response.ok ? '' : await response.text() };
}

async function remove(uid, paths) {
  const response = await fetch(`${url}/storage/v1/object/photos`, {
    method: 'DELETE',
    headers: { ...headersFor(uid), 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefixes: paths }),
  });
  const removed = response.ok ? await response.json() : [];
  return { ok: response.ok, status: response.status, count: removed.length };
}

// The files.
const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64',
);
const jpegOf = (bytes) => {
  const file = Buffer.alloc(bytes);
  file.set([0xff, 0xd8, 0xff, 0xe0]);
  return file;
};
const pdf = Buffer.from('%PDF-1.4\n1 0 obj <<>> endobj\ntrailer <<>>\n%%EOF\n');
const MiB = 1024 * 1024;

// Each run writes under a fresh report id, and cleans up after itself.
const report = `storage-test-${randomUUID().slice(0, 8)}`;
const folder = (uid) => `damage_reports/${uid}/${report}`;

let failures = 0;
let count = 0;
function check(passed, description, detail) {
  count++;
  if (passed) {
    console.log(`ok ${count} - ${description}`);
  } else {
    failures++;
    console.log(`not ok ${count} - ${description}`);
    if (detail) console.log(`      # ${detail}`);
  }
}

/// Refused, and for the reason the test is about: a refusal for some
/// other reason would prove nothing about the limit.
function refused(result, reason, description) {
  const said = `${result.status} ${result.message}`.trim();
  check(!result.ok && reason.test(result.message), description, result.ok ? `accepted: ${said}` : `server said: ${said}`);
}

const sizeLimit = /size|too large/i;
const imagesOnly = /mime/i;
const policy = /row-level security|security policy|unauthorized/i;

// Uploads.
const accepted = await upload(owner, `${folder(owner)}/photo-1.png`, png, 'image/png');
check(accepted.ok, 'the reporter uploads an image to their own report', `${accepted.status} ${accepted.message}`);

const large = await upload(owner, `${folder(owner)}/photo-2.jpg`, jpegOf(9 * MiB), 'image/jpeg');
check(large.ok, 'a 9 MB image is under the limit', `${large.status} ${large.message}`);

refused(
  await upload(owner, `${folder(owner)}/photo-3.jpg`, jpegOf(11 * MiB), 'image/jpeg'),
  sizeLimit,
  'an 11 MB image is refused by the 10 MB limit',
);
refused(
  await upload(owner, `${folder(owner)}/photo-4.jpg`, pdf, 'application/pdf'),
  imagesOnly,
  'a PDF is refused by the images-only rule, even named like a photo',
);
refused(
  await upload(owner, `${folder(owner)}/scan.pdf`, pdf, 'application/pdf'),
  new RegExp(`${imagesOnly.source}|${policy.source}`, 'i'),
  'a PDF under its own name is refused',
);
refused(
  await upload(inactive, `${folder(inactive)}/photo-1.png`, png, 'image/png'),
  policy,
  'a deactivated account cannot upload',
);
refused(
  await upload(otherReporter, `${folder(owner)}/photo-5.png`, png, 'image/png'),
  policy,
  'a reporter cannot upload into another reporter\'s report',
);
refused(
  await upload(owner, `${folder(owner)}/photo-1.png`, png, 'image/png', { upsert: true }),
  policy,
  'an uploaded photo cannot be overwritten',
);

// Reads.
const own = await download(owner, `${folder(owner)}/photo-1.png`);
check(own.ok, 'the reporter reads their own photo', `${own.status} ${own.message}`);
const other = await download(otherReporter, `${folder(owner)}/photo-1.png`);
check(!other.ok, 'another reporter cannot read it', `${other.status} (expected a refusal)`);
const byAdmin = await download(admin, `${folder(owner)}/photo-1.png`);
check(byAdmin.ok, 'an administrator reads it', `${byAdmin.status} ${byAdmin.message}`);
const byInactive = await download(inactive, `${folder(owner)}/photo-1.png`);
check(!byInactive.ok, 'a deactivated account cannot read it', `${byInactive.status} (expected a refusal)`);

// Removal: only an administrator. This also cleans up.
const paths = [`${folder(owner)}/photo-1.png`, `${folder(owner)}/photo-2.jpg`];
const byOwner = await remove(owner, paths);
check(byOwner.count === 0, 'the reporter cannot delete their photos', `${byOwner.status}, removed ${byOwner.count}`);
const cleanup = await remove(admin, paths);
check(cleanup.count === 2, 'an administrator can', `${cleanup.status}, removed ${cleanup.count}`);

console.log(`\n${count} checks, ${failures} failing`);
process.exitCode = failures ? 1 : 0;
