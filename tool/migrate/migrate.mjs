// One-time move of GSUhub's data from Firestore to Supabase (Objective 1).
//
//   cd tool/migrate && npm install
//
//   # Read Firestore and report what would move; writes nothing anywhere:
//   node migrate.mjs --dry-run
//
//   # Also load it into the database inside a transaction, then roll back:
//   # every row that would fail is listed.
//   node migrate.mjs --dry-run --db "$SUPABASE_DB_URL"
//
//   # The move itself, into an empty database (after `supabase db push`):
//   node migrate.mjs --db "$SUPABASE_DB_URL" --copy-photos --yes
//
// Reading Firestore needs a service account for the Firebase project:
// GOOGLE_APPLICATION_CREDENTIALS=path/to/key.json (never commit it). With
// FIRESTORE_EMULATOR_HOST set it reads the emulator instead.
//
//   --project <id>     Firebase project (default: .firebaserc's)
//   --export <file>    save what was read as JSON, and stop
//   --from <file>      read a saved export instead of Firestore
//   --db <url>         Postgres connection string (or SUPABASE_DB_URL)
//   --ca <file>        the project's SSL certificate, to verify the server
//   --copy-photos      copy photos into the Supabase bucket; needs
//                      SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
//   --yes              write for real (without --dry-run)
//
// The database must be empty: a second run would mix two histories.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadRows, nonEmptyTables } from './load.mjs';
import { copyPhotos, photosToCopy } from './photos.mjs';
import { collections, plain, tableOrder, transform } from './transform.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

function parseArgs(argv) {
  const args = { flags: new Set() };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (['--project', '--export', '--from', '--db', '--ca'].includes(arg)) args[arg.slice(2)] = argv[++i];
    else if (arg.startsWith('--')) args.flags.add(arg.slice(2));
    else throw new Error(`Unexpected argument: ${arg}`);
  }
  return args;
}

async function readFirestore(projectId) {
  const { initializeApp, applicationDefault } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  const app = initializeApp(
    process.env.FIRESTORE_EMULATOR_HOST ? { projectId } : { credential: applicationDefault(), projectId },
  );
  const db = getFirestore(app);
  const read = {};
  const documents = async (ref) => (await ref.get()).docs.map((doc) => ({ id: doc.id, data: doc.data(), ref: doc.ref }));

  // Every collection there is, so one the app never had is reported
  // rather than silently left behind.
  const names = (await db.listCollections()).map((c) => c.id);
  for (const name of new Set([...Object.keys(collections), ...names])) {
    const docs = await documents(db.collection(name));
    read[name] = [];
    for (const doc of docs) {
      const entry = { id: doc.id, data: doc.data };
      const subs = (await doc.ref.listCollections()).map((c) => c.id);
      if (subs.length > 0) {
        entry.sub = {};
        for (const sub of subs) entry.sub[sub] = (await documents(doc.ref.collection(sub))).map(({ id, data }) => ({ id, data }));
      }
      read[name].push(entry);
    }
  }
  return read;
}

/// What was read, as plain JSON: timestamps as ISO strings, GeoPoints as
/// {latitude, longitude}.
const exportable = (read) =>
  Object.fromEntries(
    Object.entries(read).map(([name, docs]) => [
      name,
      docs.map((doc) => ({
        id: doc.id,
        data: plain(doc.data),
        ...(doc.sub && {
          sub: Object.fromEntries(
            Object.entries(doc.sub).map(([s, children]) => [s, children.map((c) => ({ id: c.id, data: plain(c.data) }))]),
          ),
        }),
      })),
    ]),
  );

async function connect(url, caFile) {
  const { default: pg } = await import('pg');
  const host = new URL(url).hostname;
  const local = host === 'localhost' || host === '127.0.0.1';
  const client = new pg.Client({
    connectionString: url,
    // Verified against the project's certificate, never accepted blind:
    // the connection carries the database password.
    ssl: local ? false : { rejectUnauthorized: true, ...(caFile && { ca: readFileSync(caFile, 'utf8') }) },
  });
  await client.connect();
  return { client, host };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const dryRun = args.flags.has('dry-run');
  if (!dryRun && !args.flags.has('yes') && !args.export) {
    throw new Error('A real run writes to the database: pass --yes, or --dry-run to look first.');
  }

  let read;
  if (args.from) {
    read = JSON.parse(readFileSync(args.from, 'utf8'));
    console.log(`Read ${args.from}`);
  } else {
    const projectId = args.project ?? JSON.parse(readFileSync(join(root, '.firebaserc'), 'utf8')).projects.default;
    console.log(`Reading Firestore${process.env.FIRESTORE_EMULATOR_HOST ? ' (emulator)' : ''}: ${projectId}`);
    read = await readFirestore(projectId);
  }
  if (args.export) {
    writeFileSync(args.export, JSON.stringify(exportable(read), null, 2));
    console.log(`Saved ${args.export}`);
    return 0;
  }

  const { tables, warnings } = transform(read);
  console.log('\nRows to move:');
  for (const table of tableOrder) console.log(`  ${table.padEnd(32)} ${tables[table].length}`);
  for (const warning of warnings) console.log(`  ! ${warning}`);

  const photos = photosToCopy(tables);
  if (args.flags.has('copy-photos') && !dryRun) {
    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('--copy-photos needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.');
    }
    console.log(`\nCopying ${photos.length} photos to ${supabaseUrl}…`);
    const failures = await copyPhotos(tables, { supabaseUrl, serviceRoleKey });
    for (const failure of failures) console.log(`  ! ${failure}`);
    if (failures.length > 0) {
      console.log(`${failures.length} photos could not be copied; their rows keep the Firebase URL.`);
    }
  } else {
    console.log(`\nPhotos in Firebase Storage: ${photos.length}${args.flags.has('copy-photos') ? ' (not copied in a dry run)' : ''}`);
  }

  const url = args.db ?? process.env.SUPABASE_DB_URL;
  if (!url) {
    console.log('\nNo database given (--db or SUPABASE_DB_URL): nothing loaded.');
    return dryRun ? 0 : 1;
  }

  const { client, host } = await connect(url, args.ca);
  const query = (sql, params) => client.query(sql, params);
  let problems = [];
  try {
    await query('begin');
    const filled = await nonEmptyTables(query);
    if (filled.length > 0) {
      problems.push(`The database already holds data: ${filled.join(', ')}. Migrate into an empty one.`);
    }
    const result = await loadRows(query, tables);
    problems = [...problems, ...result.problems];

    console.log(`\nLoaded into ${host}${dryRun ? ' (dry run: rolled back)' : ''}:`);
    for (const table of tableOrder) {
      if (tables[table].length > 0) console.log(`  ${table.padEnd(32)} ${result.inserted[table]} of ${tables[table].length}`);
    }
    for (const [table, fields] of Object.entries(result.dropped)) {
      console.log(`  ~ ${table}: fields with no column, left behind: ${fields.join(', ')}`);
    }
    for (const check of result.checks) console.log(`  ? ${check}`);
    for (const problem of problems) console.log(`  ! ${problem}`);

    if (dryRun || problems.length > 0) {
      await query('rollback');
      if (!dryRun) console.log('\nNothing was written: fix the rows above and run again.');
    } else {
      await query('commit');
      console.log('\nCommitted.');
    }
  } catch (error) {
    await query('rollback').catch(() => {});
    throw error;
  } finally {
    await client.end();
  }
  return problems.length > 0 ? 1 : 0;
}

main().then(
  (code) => {
    process.exitCode = code;
  },
  (error) => {
    console.error(`\nSTOPPED: ${error.message}`);
    process.exitCode = 1;
  },
);
