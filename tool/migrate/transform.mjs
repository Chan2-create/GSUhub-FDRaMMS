// Firestore documents → Supabase rows (Objective 1).
//
// Pure: no network, no database. migrate.mjs reads the documents and loads
// the rows; the tests feed this made-up documents.
//
// The mapping is the one tool/seed.dart renders supabase/seed.sql with:
// camelCase fields become snake_case columns, a GeoPoint `coordinates`
// becomes `latitude` and `longitude`, timestamps become ISO strings, and
// three subcollections become tables of their own.

/// Tables in the order their rows go in: each after what it points at.
export const tableOrder = [
  'users',
  'facilities',
  'assets',
  'app_config',
  'inventory_items',
  'tools',
  'work_orders',
  'damage_reports',
  'report_status_history',
  'tasks',
  'accomplishment_reports',
  'work_order_materials_used',
  'work_order_materials_allocated',
  'tool_loans',
  'material_requests',
  'feedback',
  'notifications',
  'audit_logs',
  'inventory_transactions',
];

/// The top-level Firestore collections, by the table each becomes.
export const collections = {
  users: 'users',
  facilities: 'facilities',
  assets: 'assets',
  config: 'app_config',
  inventory_items: 'inventory_items',
  tools: 'tools',
  work_orders: 'work_orders',
  damage_reports: 'damage_reports',
  tasks: 'tasks',
  accomplishment_reports: 'accomplishment_reports',
  tool_loans: 'tool_loans',
  material_requests: 'material_requests',
  feedback: 'feedback',
  notifications: 'notifications',
  audit_logs: 'audit_logs',
  inventory_transactions: 'inventory_transactions',
};

/// Subcollections, by parent collection: name → table.
export const subcollections = {
  damage_reports: { status_history: 'report_status_history' },
  work_orders: {
    materials_used: 'work_order_materials_used',
    materials_allocated: 'work_order_materials_allocated',
  },
};

/// Columns holding JSON: a list or map there is a document, not a text array.
const jsonColumns = new Set(['materials_used', 'items', 'changes', 'data']);

export const snake = (name) => name.replace(/[A-Z]/g, (c) => '_' + c.toLowerCase());

const isTimestamp = (v) => v !== null && typeof v === 'object' && typeof v.toDate === 'function';
const isGeoPoint = (v) =>
  v !== null && typeof v === 'object' && typeof v.latitude === 'number' && typeof v.longitude === 'number';

/// A Firestore value as plain JSON: timestamps as ISO strings, a GeoPoint
/// as {latitude, longitude}, a document reference as its path.
export function plain(value) {
  if (value === null || value === undefined) return null;
  if (isTimestamp(value)) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(plain);
  if (typeof value === 'object') {
    if (typeof value.path === 'string' && typeof value.id === 'string' && value.firestore) return value.path;
    if (isGeoPoint(value) && Object.keys(value).length <= 2) {
      return { latitude: value.latitude, longitude: value.longitude };
    }
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  }
  return value;
}

/// One document's row. [parentId] is set for a subcollection document.
export function rowOf(table, id, data, parentId) {
  const row = {};
  switch (table) {
    case 'report_status_history':
      // Firestore ids were per report (h1, h2…); here they are global.
      row.id = `${parentId}-${id}`;
      row.report_id = parentId;
      break;
    case 'work_order_materials_used':
    case 'work_order_materials_allocated':
      row.work_order_id = parentId;
      row.inventory_item_id = id;
      break;
    case 'app_config': {
      const { updatedAt, updatedBy, ...document } = data;
      return {
        id,
        data: plain(document),
        updated_by: updatedBy ?? null,
        updated_at: plain(updatedAt) ?? new Date(0).toISOString(),
      };
    }
    default:
      row.id = id;
  }

  for (const [key, value] of Object.entries(data)) {
    if (key === 'coordinates') {
      // A GeoPoint becomes two plain columns (no PostGIS).
      row.latitude = isGeoPoint(value) ? value.latitude : null;
      row.longitude = isGeoPoint(value) ? value.longitude : null;
      continue;
    }
    const column = snake(key);
    row[column] = jsonColumns.has(column) ? plain(value) ?? null : plain(value);
  }
  return row;
}

/// The photo fields: table → [column, how the bucket folder is named].
export const photoColumns = {
  damage_reports: { column: 'photo_urls', folder: (row) => `damage_reports/${row.reporter_id}/${row.id}` },
  accomplishment_reports: {
    column: 'photo_urls',
    folder: (row) => `accomplishment_reports/${row.submitted_by}/${row.id}`,
  },
  tasks: { column: 'proof_photo_urls', folder: (row) => `tasks/${row.assigned_to}/${row.id}` },
  inventory_items: { column: 'photo_url', folder: (row) => `inventory_items/${row.id}` },
};

/// Whether [url] is a Firebase Storage download URL, live or emulator.
export const isFirebasePhoto = (url) =>
  typeof url === 'string' &&
  (/^https:\/\/firebasestorage\.googleapis\.com\//.test(url) || /\/v0\/b\/[^/]+\/o\//.test(url));

/// The file name in a Firebase Storage download URL:
/// .../o/damage_reports%2Fr1%2Fphoto-1.jpg?alt=media → photo-1.jpg.
export function photoFileName(url) {
  const match = /\/o\/([^?]+)/.exec(url);
  const object = match ? decodeURIComponent(match[1]) : url;
  return object.split('/').pop();
}

/// Every Firestore document as rows, by table, in load order.
///
/// [read] is {collection: [{id, data, sub: {name: [{id, data}]}}]}, as
/// migrate.mjs reads it. Returns {tables, warnings}.
export function transform(read) {
  const tables = Object.fromEntries(tableOrder.map((t) => [t, []]));
  const warnings = [];
  for (const [collection, docs] of Object.entries(read)) {
    const table = collections[collection];
    if (!table) {
      warnings.push(`Firestore collection "${collection}" has no table; its ${docs.length} documents are not migrated.`);
      continue;
    }
    for (const doc of docs) {
      tables[table].push(rowOf(table, doc.id, doc.data ?? {}));
      for (const [name, children] of Object.entries(doc.sub ?? {})) {
        const childTable = subcollections[collection]?.[name];
        if (!childTable) {
          warnings.push(`Subcollection ${collection}/${doc.id}/${name} has no table; not migrated.`);
          continue;
        }
        for (const child of children) tables[childTable].push(rowOf(childTable, child.id, child.data ?? {}, doc.id));
      }
    }
  }
  // A merged report points at the report it was merged into: parents first.
  tables.damage_reports.sort((a, b) => (a.duplicate_of ? 1 : 0) - (b.duplicate_of ? 1 : 0));
  // The ledger, oldest first.
  tables.inventory_transactions.sort((a, b) => String(a.performed_at).localeCompare(String(b.performed_at)));
  return { tables, warnings };
}
