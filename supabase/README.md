# GSUhub on Supabase

GSUhub's application data lives in Postgres here, and its photos in Supabase
Storage. Sign-in stays with Firebase Auth (Objective 1).

This folder is managed by the Supabase CLI. Use it through `npx supabase …`,
which needs no global install.

## What is here

| File | What it holds |
|---|---|
| `migrations/*_tables.sql` | The 19 tables, with their constraints and indexes. |
| `migrations/*_access_helpers.sql` | Who is calling: `app.uid()` (the Firebase uid), `app.is_admin()` and the other role checks. An inactive account has no role. |
| `migrations/*_row_level_security.sql` | Grants and read policies. App users can only read; every write goes through a function. |
| `migrations/*_stock_ledger.sql` | Stock moves only through `inventory_transactions`. The ledger, the audit log and report timelines are insert-only. |
| `migrations/*_storage_policies.sql` | The private `photos` bucket (10 MB, images only) and who may upload or read each folder. |
| `migrations/*_realtime.sql` | The tables the app watches live. |
| `seed.sql` | Demo data. **Generated, don't edit it**: see below. |
| `tests/*.test.sql` | pgTAP tests: the permission matrix, the stock ledger and the storage policies. |

The `app` schema is not exposed through the API. Its functions run with
the owner's rights, so each one checks the caller itself.

## Running the tests

**With Docker** (the real check):

```
npx supabase start
npx supabase test db
node tool/storage_api_test.mjs
```

On an 8 GB machine, leave out the services you don't need:

```
npx supabase start -x studio,imgproxy,vector,logflare,supavisor,mailpit
```

`tool/storage_api_test.mjs` uploads real files. It checks what only the
Storage service enforces: a PDF and an 11 MB image are both refused.

**Without Docker** (a fast first check): run the same SQL tests in PGlite,
which is Postgres compiled to WebAssembly.

```
cd tool/sql_tests
npm install
node run.mjs            # on an empty database
node run.mjs --seed     # with supabase/seed.sql loaded
```

`supabase_stub.sql` stands in for the parts of Supabase that PGlite doesn't
have: the `auth.jwt()` function, the storage tables and the API roles.

## Demo data

`seed.sql` is written by `tool/seed.dart`. To change the demo data, edit
it there and regenerate:

```
dart run tool/seed.dart sql     # writes supabase/seed.sql
npx supabase db reset           # migrations, then the seed
dart run tool/seed.dart auth    # sign-in accounts, in the Firebase Auth emulator
```

All times in the seed are offsets from `now()`, so the demo always looks
recent.

The materials go in at zero stock, and the ledger entries bring them up to
their levels. If the entries no longer add up to the stock written in
`tool/seed.dart`, the seed stops the reset.

**Never run the seed against production.**

## Changing the schema

Create each new migration with `npx supabase migration new <name>`. Never
edit a migration that has already been applied anywhere. Every new policy
or function gets a test in `tests/`.

The permission matrix in `tests/permission_matrix.test.sql` is derived from
the Firestore rules. Verify it against Development Plan §4 when that is
available.
