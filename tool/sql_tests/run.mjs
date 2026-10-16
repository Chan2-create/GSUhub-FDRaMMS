// Runs the pgTAP tests in supabase/tests against the migrations, in PGlite
// (Postgres compiled to WebAssembly), for a machine without Docker.
//
// The real check is `npx supabase test db` against the local stack; this
// is the same SQL against a stand-in for the Supabase-specific schemas
// (supabase_stub.sql). Use it while Docker is unavailable, and keep using
// it as a fast first check.
//
//   cd tool/sql_tests && npm install && node run.mjs [--seed] [file…]
//
// pgTAP is not bundled with PGlite; the runner loads it from a pgTAP
// source checkout given in PGTAP_SQL (the generated pgtap.sql), or
// downloads release 1.3.3 into .cache/ on first use.

import { PGlite } from '@electric-sql/pglite';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');
const migrations = join(root, 'supabase', 'migrations');
const tests = join(root, 'supabase', 'tests');
const args = process.argv.slice(2);
const withSeed = args.includes('--seed');
const only = args.filter((a) => !a.startsWith('--'));

function pgtapSql() {
  if (process.env.PGTAP_SQL) return readFileSync(process.env.PGTAP_SQL, 'utf8');
  const cache = join(here, '.cache');
  const out = join(cache, 'pgtap.sql');
  if (!existsSync(out)) {
    mkdirSync(cache, { recursive: true });
    const tarball = join(cache, 'pgtap.tar.gz');
    execFileSync('curl', ['-sL', '-o', tarball, 'https://github.com/theory/pgtap/archive/refs/tags/v1.3.3.tar.gz']);
    execFileSync('tar', ['-xzf', tarball, '-C', cache]);
    const source = readFileSync(join(cache, 'pgtap-1.3.3', 'sql', 'pgtap.sql.in'), 'utf8');
    writeFileSync(out, source.replaceAll('__OS__', 'linux').replaceAll('__VERSION__', '1.33'));
  }
  return readFileSync(out, 'utf8');
}

async function freshDatabase() {
  const db = new PGlite();
  await db.exec(readFileSync(join(here, 'supabase_stub.sql'), 'utf8'));
  for (const file of readdirSync(migrations).filter((f) => f.endsWith('.sql')).sort()) {
    try {
      await db.exec(readFileSync(join(migrations, file), 'utf8'));
    } catch (error) {
      throw new Error(`migration ${file}: ${error.message}`);
    }
  }
  if (withSeed) {
    try {
      await db.exec(readFileSync(join(root, 'supabase', 'seed.sql'), 'utf8'));
    } catch (error) {
      throw new Error(`seed.sql: ${error.message}`);
    }
  }
  await db.exec('create extension if not exists plpgsql;');
  await db.exec(pgtapSql());
  return db;
}

const files = readdirSync(tests)
  .filter((f) => f.endsWith('.sql'))
  .filter((f) => only.length === 0 || only.some((o) => f.includes(o)))
  .sort();

// Files named 00_* set up helpers and fixtures, kept for the files after
// them by `supabase test db`; here each test file gets a fresh database, so
// they are applied before every file.
const setupFiles = readdirSync(tests).filter((f) => f.startsWith('00_') && f.endsWith('.sql')).sort();

let failed = 0;
let planned = 0;
for (const file of files) {
  const db = await freshDatabase();
  if (!file.startsWith('00_')) {
    for (const setup of setupFiles) await db.exec(readFileSync(join(tests, setup), 'utf8'));
    // pgTAP keeps its plan in temporary tables; a new session starts clean.
    await db.exec('discard temp');
  }
  const sql = readFileSync(join(tests, file), 'utf8');
  let lines = [];
  try {
    const results = await db.exec(sql);
    for (const result of results) {
      for (const row of result.rows) {
        for (const value of Object.values(row)) {
          if (typeof value === 'string') lines.push(...value.split('\n'));
        }
      }
    }
  } catch (error) {
    console.log(`not ok - ${file}: ${error.message}`);
    failed++;
    continue;
  } finally {
    await db.close();
  }
  const tap = lines.filter((l) => /^(not ok|ok|1\.\.|#)/.test(l));
  const bad = tap.filter((l) => l.startsWith('not ok'));
  const plan = tap.find((l) => l.startsWith('1..'));
  planned += plan ? Number(plan.slice(3)) : 0;
  const passed = tap.filter((l) => l.startsWith('ok')).length;
  console.log(`${bad.length ? 'FAIL' : 'pass'}  ${file}  ${passed}/${plan ? plan.slice(3) : '?'}`);
  for (const line of tap.filter((l) => l.startsWith('not ok') || l.startsWith('#'))) {
    console.log(`      ${line}`);
  }
  if (bad.length || !plan || passed !== Number(plan.slice(3))) failed++;
}

console.log(`\n${files.length} files, ${planned} tests planned, ${failed} file(s) failing`);
process.exitCode = failed ? 1 : 0;
