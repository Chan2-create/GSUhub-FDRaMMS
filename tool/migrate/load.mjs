// Loads transformed rows into the Supabase database (Objective 1).
//
// [query] is (sql, params) => Promise<{rows}>: a node-postgres client's
// query, or PGlite's in the tests. One transaction, a savepoint per row,
// so a dry run reports every row that would fail, not just the first; a
// real run commits only if none did.

import { tableOrder } from './transform.mjs';

/// Inventory and its ledger are copied as Firestore has them: balances and
/// history exactly, with the stock triggers off for those rows only
/// (session_replication_role = replica). Replaying the history through the
/// triggers would recompute every balance and refuse any gap Firestore's
/// history has. The check afterwards reports what does not add up.
const copiedAsIs = new Set(['inventory_items', 'inventory_transactions']);

const literalFor = (type, index) =>
  ({
    'ARRAY': `(select coalesce(array_agg(value), '{}') from jsonb_array_elements_text($${index}::jsonb))`,
    'jsonb': `$${index}::jsonb`,
    'timestamp with time zone': `$${index}::timestamptz`,
    'double precision': `$${index}::double precision`,
    'integer': `$${index}::integer`,
    'boolean': `$${index}::boolean`,
  })[type] ?? `$${index}::text`;

const paramFor = (type, value) => {
  if (value === null || value === undefined) return null;
  if (type === 'ARRAY' || type === 'jsonb') return JSON.stringify(value);
  return value;
};

export async function columnsOf(query) {
  const { rows } = await query(
    `select table_name, column_name, data_type from information_schema.columns
     where table_schema = 'public' order by table_name, ordinal_position`,
  );
  const columns = {};
  for (const r of rows) (columns[r.table_name] ??= {})[r.column_name] = r.data_type;
  return columns;
}

/// The tables that already hold rows: a migration goes into an empty
/// database, or it would mix two histories.
export async function nonEmptyTables(query) {
  const filled = [];
  for (const table of tableOrder) {
    const { rows } = await query(`select count(*)::int as n from public.${table}`);
    if (rows[0].n > 0) filled.push(`${table} (${rows[0].n})`);
  }
  return filled;
}

/// Inserts every row; returns {inserted, problems, dropped, checks}.
/// Leaves the transaction to the caller.
export async function loadRows(query, tables) {
  const columns = await columnsOf(query);
  const inserted = {};
  const problems = [];
  const dropped = {};
  for (const table of tableOrder) {
    const rows = tables[table] ?? [];
    inserted[table] = 0;
    if (rows.length === 0) continue;
    const known = columns[table];
    if (!known) {
      problems.push(`${table}: no such table in the database`);
      continue;
    }
    if (copiedAsIs.has(table)) await query('set local session_replication_role = replica');
    for (const row of rows) {
      const names = Object.keys(row).filter((name) => {
        if (name in known) return true;
        (dropped[table] ??= new Set()).add(name);
        return false;
      });
      const sql =
        `insert into public.${table} (${names.map((n) => `"${n}"`).join(', ')}) values (` +
        names.map((n, i) => literalFor(known[n], i + 1)).join(', ') +
        ')';
      await query('savepoint migrate_row');
      try {
        await query(sql, names.map((n) => paramFor(known[n], row[n])));
        await query('release savepoint migrate_row');
        inserted[table]++;
      } catch (error) {
        await query('rollback to savepoint migrate_row');
        const key = row.id ?? `${row.work_order_id}/${row.inventory_item_id}`;
        problems.push(`${table} ${key}: ${error.message}`);
      }
    }
    if (copiedAsIs.has(table)) await query('set local session_replication_role = origin');
  }
  return {
    inserted,
    problems,
    dropped: Object.fromEntries(Object.entries(dropped).map(([t, s]) => [t, [...s]])),
    checks: await checkInventory(query),
  };
}

/// What the copied inventory says that does not add up: a ledger entry for
/// a material that is not there, or a balance its last entry disagrees
/// with. Reported, not fixed: the history is Firestore's.
export async function checkInventory(query) {
  const orphans = await query(
    `select t.id, t.inventory_item_id from public.inventory_transactions t
     left join public.inventory_items i on i.id = t.inventory_item_id where i.id is null`,
  );
  const balances = await query(
    `select i.id, i.name, i.quantity_available, last.quantity_after
     from public.inventory_items i
     join lateral (
       select t.quantity_after from public.inventory_transactions t
       where t.inventory_item_id = i.id order by t.performed_at desc, t.id desc limit 1
     ) last on true
     where last.quantity_after is distinct from i.quantity_available`,
  );
  return [
    ...orphans.rows.map((r) => `ledger entry ${r.id} is for ${r.inventory_item_id}, which is not in the inventory`),
    ...balances.rows.map(
      (r) => `${r.name} (${r.id}) holds ${r.quantity_available}, but its last ledger entry left ${r.quantity_after}`,
    ),
  ];
}
