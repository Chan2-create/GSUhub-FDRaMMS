// Tests for the Firestore → Supabase move, against the real migrations in
// PGlite (as tool/sql_tests runs them):  cd tool/migrate && npm test

import { PGlite } from '@electric-sql/pglite';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { loadRows, nonEmptyTables } from './load.mjs';
import { copyPhotos, photosToCopy } from './photos.mjs';
import { photoFileName, rowOf, snake, transform } from './transform.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');

async function database() {
  const db = new PGlite();
  await db.exec(readFileSync(join(root, 'tool', 'sql_tests', 'supabase_stub.sql'), 'utf8'));
  const migrations = join(root, 'supabase', 'migrations');
  for (const file of readdirSync(migrations).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(migrations, file), 'utf8'));
  }
  return db;
}

/// What firebase-admin hands back, as far as the transform looks.
class Timestamp {
  constructor(iso) {
    this.iso = iso;
  }
  toDate() {
    return new Date(this.iso);
  }
}
class GeoPoint {
  constructor(latitude, longitude) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

const t = (iso) => new Timestamp(iso);
const photo = (path) =>
  `https://firebasestorage.googleapis.com/v0/b/gsuhub-dorsu.appspot.com/o/${encodeURIComponent(path)}?alt=media&token=abc`;

/// A small Firestore, one of everything that moves.
function firestore() {
  return {
    users: [
      { id: 'u-admin', data: { fullName: 'Ramon Dela Cruz', email: 'admin@test.ph', role: 'admin', accountStatus: 'active', activeTaskCount: 0, createdAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-01T00:00:00Z') } },
      { id: 'u-req', data: { fullName: 'Maria Santos', email: 'req@test.ph', role: 'requestor', accountStatus: 'active', activeTaskCount: 0, fcmToken: 'tok', createdAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-01T00:00:00Z') } },
      { id: 'u-tech', data: { fullName: 'Marcus Wright', email: 'tech@test.ph', role: 'maintenancePersonnel', accountStatus: 'active', specialization: 'electrical', availability: 'available', activeTaskCount: 1, createdAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-01T00:00:00Z') } },
    ],
    facilities: [
      { id: 'f-1', data: { name: 'Engineering Building', buildingName: 'Engineering Building', roomIdentifier: 'Room 101', coordinates: new GeoPoint(7.07, 126.21), qrCode: 'FAC-F-1', isActive: true, createdAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-01T00:00:00Z') } },
    ],
    config: [
      { id: 'classification_rules', data: { keywordsByCategory: { plumbing: ['leak'] }, caseSensitive: false, updatedAt: t('2026-09-02T00:00:00Z'), updatedBy: 'u-admin' } },
    ],
    inventory_items: [
      { id: 'i-1', data: { name: 'LED Bulbs', category: 'Electrical', quantityAvailable: 18, unitOfMeasurement: 'units', storageLocation: 'Store A', qrCode: 'INV-I-1', minimumThreshold: 5, photoUrl: photo('inventory_items/i-1/photo.jpg'), createdAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-03T00:00:00Z') } },
      { id: 'i-2', data: { name: 'Tape', category: 'Electrical', quantityAvailable: 7, unitOfMeasurement: 'rolls', storageLocation: 'Store A', qrCode: 'INV-I-2', minimumThreshold: 2, createdAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-01T00:00:00Z') } },
    ],
    work_orders: [
      {
        id: 'w-1',
        data: { reportIds: ['r-1'], title: 'Flickering lights', description: 'Room 101', category: 'electrical', priority: 'high', status: 'inProgress', assignedPersonnelIds: ['u-tech'], facilityId: 'f-1', createdBy: 'u-admin', createdAt: t('2026-09-02T00:00:00Z'), updatedAt: t('2026-09-02T00:00:00Z') },
        sub: {
          materials_used: [{ id: 'i-1', data: { itemName: 'LED Bulbs', quantityUsed: 2, unitOfMeasurement: 'units', recordedBy: 'u-tech', recordedAt: t('2026-09-03T00:00:00Z') } }],
        },
      },
    ],
    damage_reports: [
      {
        id: 'r-dup',
        data: { reporterId: 'u-req', reporterName: 'Maria Santos', title: 'Lights again', description: 'Same.', requestorPriority: 'low', status: 'merged', duplicateOf: 'r-1', submittedAt: t('2026-09-01T02:00:00Z'), updatedAt: t('2026-09-02T00:00:00Z') },
      },
      {
        id: 'r-1',
        data: { reporterId: 'u-req', reporterName: 'Maria Santos', title: 'Flickering lights', description: 'Lights flicker.', requestorPriority: 'high', status: 'inProgress', workOrderId: 'w-1', facilityId: 'f-1', coordinates: new GeoPoint(7.07, 126.21), photoUrls: [photo('damage_reports/r-1/photo-1.jpg')], legacyField: 'gone', submittedAt: t('2026-09-01T00:00:00Z'), updatedAt: t('2026-09-02T00:00:00Z') },
        sub: { status_history: [{ id: 'h1', data: { status: 'submitted', changedAt: t('2026-09-01T00:00:00Z'), changedBy: 'u-req' } }] },
      },
    ],
    inventory_transactions: [
      { id: 'l-2', data: { inventoryItemId: 'i-1', itemName: 'LED Bulbs', type: 'consumption', quantity: 2, quantityBefore: 20, quantityAfter: 18, performedBy: 'u-tech', performedAt: t('2026-09-03T00:00:00Z') } },
      { id: 'l-1', data: { inventoryItemId: 'i-1', itemName: 'LED Bulbs', type: 'replenishment', quantity: 20, quantityBefore: 0, quantityAfter: 20, performedBy: 'u-admin', performedAt: t('2026-09-01T00:00:00Z') } },
      // Firestore's history for i-2 says 5; its balance says 7.
      { id: 'l-3', data: { inventoryItemId: 'i-2', itemName: 'Tape', type: 'replenishment', quantity: 5, quantityBefore: 0, quantityAfter: 5, performedBy: 'u-admin', performedAt: t('2026-09-01T00:00:00Z') } },
    ],
    audit_logs: [
      { id: 'au-1', data: { actorId: 'u-admin', actorName: 'Ramon Dela Cruz', action: 'created', entityType: 'damage_reports', entityId: 'r-1', description: 'Report created', changes: { photos: 1 }, timestamp: t('2026-09-01T00:00:00Z') } },
    ],
    something_else: [{ id: 'x', data: {} }],
  };
}

test('fields become columns; a GeoPoint becomes latitude and longitude; times become ISO strings', () => {
  assert.equal(snake('unitOfMeasurement'), 'unit_of_measurement');
  const row = rowOf('damage_reports', 'r-1', firestore().damage_reports[1].data);
  assert.equal(row.reporter_id, 'u-req');
  assert.equal(row.latitude, 7.07);
  assert.equal(row.longitude, 126.21);
  assert.equal(row.submitted_at, '2026-09-01T00:00:00.000Z');
  assert.equal('coordinates' in row, false);
});

test('subcollections become tables keyed by their parent', () => {
  const { tables, warnings } = transform(firestore());
  assert.deepEqual(tables.report_status_history[0], {
    id: 'r-1-h1', report_id: 'r-1', status: 'submitted', changed_at: '2026-09-01T00:00:00.000Z', changed_by: 'u-req',
  });
  assert.equal(tables.work_order_materials_used[0].work_order_id, 'w-1');
  assert.equal(tables.work_order_materials_used[0].inventory_item_id, 'i-1');
  assert.deepEqual(tables.app_config[0].data, { keywordsByCategory: { plumbing: ['leak'] }, caseSensitive: false });
  assert.equal(tables.app_config[0].updated_by, 'u-admin');
  // A merged report goes after the one it points at; the ledger oldest first.
  assert.deepEqual(tables.damage_reports.map((r) => r.id), ['r-1', 'r-dup']);
  assert.deepEqual(tables.inventory_transactions.map((r) => r.id), ['l-1', 'l-3', 'l-2']);
  assert.match(warnings.join('\n'), /something_else/);
});

test('everything loads into the real schema, exactly as it was', async () => {
  const db = await database();
  const query = (sql, params) => db.query(sql, params);
  const { tables } = transform(firestore());
  await query('begin');
  const result = await loadRows(query, tables);
  await query('commit');

  assert.deepEqual(result.problems, []);
  assert.equal(result.inserted.damage_reports, 2);
  assert.deepEqual(result.dropped, { damage_reports: ['legacy_field'] });

  const report = (await query(`select latitude, longitude, photo_urls, work_order_id from public.damage_reports where id = 'r-1'`)).rows[0];
  assert.deepEqual([report.latitude, report.longitude, report.work_order_id], [7.07, 126.21, 'w-1']);
  assert.equal(report.photo_urls.length, 1);

  // The ledger and the balances, as Firestore had them: nothing recomputed.
  const ledger = (await query(`select id, quantity_before, quantity_after from public.inventory_transactions order by id`)).rows;
  assert.deepEqual(ledger, [
    { id: 'l-1', quantity_before: 0, quantity_after: 20 },
    { id: 'l-2', quantity_before: 20, quantity_after: 18 },
    { id: 'l-3', quantity_before: 0, quantity_after: 5 },
  ]);
  const stock = (await query(`select id, quantity_available from public.inventory_items order by id`)).rows;
  assert.deepEqual(stock, [{ id: 'i-1', quantity_available: 18 }, { id: 'i-2', quantity_available: 7 }]);
  // …and what does not add up is said.
  assert.deepEqual(result.checks, ['Tape (i-2) holds 7, but its last ledger entry left 5']);

  // The guards are back on once it is loaded.
  await assert.rejects(query(`update public.inventory_items set quantity_available = 1 where id = 'i-1'`), /ledger/);
  await db.close();
});

test('a dry run loads everything, says what failed, and leaves nothing behind', async () => {
  const db = await database();
  const query = (sql, params) => db.query(sql, params);
  const read = firestore();
  // A report about a room that is not there.
  read.damage_reports[1].data.facilityId = 'f-gone';
  const { tables } = transform(read);

  await query('begin');
  const result = await loadRows(query, tables);
  await query('rollback');

  // The report, and what hangs off it: its duplicate and its timeline.
  assert.equal(result.problems.length, 3);
  assert.match(result.problems[0], /damage_reports r-1: .*foreign key/);
  assert.match(result.problems[1], /damage_reports r-dup: .*foreign key/);
  assert.match(result.problems[2], /report_status_history r-1-h1: .*foreign key/);
  assert.equal(result.inserted.users, 3, 'every other row was still tried');
  assert.deepEqual(await nonEmptyTables(query), []);
  await db.close();
});

test('a database that already holds data is noticed', async () => {
  const db = await database();
  const query = (sql, params) => db.query(sql, params);
  await query(`insert into public.users (id, full_name, email, role, account_status) values ('u-x', 'X', 'x@test.ph', 'admin', 'active')`);
  assert.deepEqual(await nonEmptyTables(query), ['users (1)']);
  await db.close();
});

test('photos are copied under the paths the bucket expects, and the rows point at them', async () => {
  const { tables } = transform(firestore());
  assert.equal(photoFileName(photo('damage_reports/r-1/photo-1.jpg')), 'photo-1.jpg');
  const photos = photosToCopy(tables);
  assert.deepEqual(photos.map((p) => p.object).sort(), [
    'damage_reports/u-req/r-1/photo-1.jpg',
    'inventory_items/i-1/photo.jpg',
  ]);

  const calls = [];
  const fetchImpl = async (url, init = {}) => {
    calls.push([init.method ?? 'GET', url]);
    if (url.includes('/object/sign/')) {
      const object = url.split('/object/sign/photos/')[1];
      return new Response(JSON.stringify({ signedURL: `/object/sign/photos/${object}?token=t` }), { status: 200 });
    }
    if (url.startsWith('https://firebasestorage')) {
      return new Response(new Uint8Array([1, 2, 3]), { status: 200, headers: { 'content-type': 'image/jpeg' } });
    }
    return new Response('{}', { status: 200 });
  };
  const failures = await copyPhotos(tables, {
    supabaseUrl: 'http://localhost:54321',
    serviceRoleKey: 'service-key',
    log: () => {},
    fetchImpl,
  });
  assert.deepEqual(failures, []);
  assert.equal(
    tables.damage_reports.find((r) => r.id === 'r-1').photo_urls[0],
    'http://localhost:54321/storage/v1/object/sign/photos/damage_reports/u-req/r-1/photo-1.jpg?token=t',
  );
  assert.ok(calls.some(([method, url]) => method === 'POST' && url.endsWith('/object/photos/inventory_items/i-1/photo.jpg')));
});

test('a secret key is sent as the apikey only, a legacy key as the bearer token too, and neither to Firebase', async () => {
  const sent = async (serviceRoleKey) => {
    const { tables } = transform(firestore());
    const headers = [];
    await copyPhotos(tables, {
      supabaseUrl: 'http://localhost:54321',
      serviceRoleKey,
      log: () => {},
      fetchImpl: async (url, init = {}) => {
        headers.push([url, init.headers ?? {}]);
        if (url.includes('/object/sign/')) {
          return new Response(JSON.stringify({ signedURL: '/object/sign/photos/x?token=t' }), { status: 200 });
        }
        return new Response(new Uint8Array([1]), { status: 200, headers: { 'content-type': 'image/jpeg' } });
      },
    });
    return headers;
  };

  for (const [url, h] of await sent('sb_secret_abc')) {
    if (url.startsWith('https://firebasestorage')) {
      assert.equal(h.apikey, undefined);
      continue;
    }
    assert.equal(h.apikey, 'sb_secret_abc');
    assert.equal(h.Authorization, undefined);
  }
  for (const [url, h] of await sent('eyJ.legacy.key')) {
    if (url.startsWith('https://firebasestorage')) {
      assert.equal(h.Authorization, undefined);
      continue;
    }
    assert.equal(h.Authorization, 'Bearer eyJ.legacy.key');
  }
});

test('a photo that cannot be read keeps its old URL, and is reported', async () => {
  const { tables } = transform(firestore());
  const failures = await copyPhotos(tables, {
    supabaseUrl: 'http://localhost:54321',
    serviceRoleKey: 'k',
    log: () => {},
    fetchImpl: async () => new Response('gone', { status: 404 }),
  });
  assert.equal(failures.length, 2);
  assert.match(tables.damage_reports.find((r) => r.id === 'r-1').photo_urls[0], /^https:\/\/firebasestorage/);
});
