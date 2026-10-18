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
| `migrations/*_server_helpers.sql` | What every write shares: the status rules and labels (mirroring the Dart enums), the audit entry, the notification wording, the report's timeline entry, a work order's move. |
| `migrations/*_account_functions.sql` … `*_feedback_notification_config_functions.sql` | The writes: signing up, accounts, rooms and equipment, reports, work orders, ratings, notifications, settings. |
| `seed.sql` | Demo data. **Generated, don't edit it**: see below. |
| `tests/*.test.sql` | pgTAP tests: the permission matrix, the stock ledger and the storage policies. |
| `functions/firebase-token-exchange/` | Trades a Firebase ID token for a Supabase access token. See below. |
| `functions/tests/` | Its tests, in Deno. |

The `app` schema is not exposed through the API. Its functions run with
the owner's rights, so each one checks the caller itself.

### How a write works

App users can read tables (row level security decides which rows) and
write nothing. Every change is a function:

- `public.submit_report(...)` is what the API exposes. It runs as the
  caller and only hands over to `app.submit_report(...)`.
- `app.submit_report(...)` checks who is calling and the stored state,
  makes the change, writes the timeline entry, the notification and the
  audit entry, all in one transaction.
- A refusal raises SQLSTATE `PTxxx`. The API answers HTTP `xxx`, and the
  app shows the message as written:
  - `PT403`: not allowed;
  - `PT404`: not there;
  - `PT409` or `PT422`: the data says no.

`tests/function_privileges.test.sql` holds every function to these rules,
read from the catalog, so a function added later is checked without being
listed. `test/unit/repositories/supabase_contract_test.dart` checks the
other side: every function the app calls exists, with the parameters the
app sends.

## How Supabase knows who is calling

People sign in with Firebase. The app then trades the Firebase ID token
for a Supabase one, at the `firebase-token-exchange` Edge Function
(`lib/core/services/supabase/supabase_session.dart`). The Supabase token's
`sub` is the Firebase uid. The database reads the role and account status
from the `users` row with that id on every request, so a deactivated
account is locked out at once, whatever token it holds.

The function needs three secrets:

| Secret | Local | Hosted |
|---|---|---|
| `FIREBASE_PROJECT_ID` | `gsuhub-dorsu` | `gsuhub-dorsu` |
| `TOKEN_SIGNING_KEY` | the local stack's JWT secret, as a JSON Web Key | an ES256 key from `npx supabase gen signing-key --algorithm ES256`, imported as the project's signing key ([signing keys](https://supabase.com/docs/guides/auth/signing-keys)) |
| `ALLOW_EMULATOR_TOKENS` | `true`: accepts the Auth emulator's unsigned tokens | **never set**. The function refuses to run if it is set on a hosted project. |

Locally, `node tool/supabase_function_env.mjs` writes them to
`supabase/functions/.env`, which git ignores. Run it after
`npx supabase start`, then restart the stack so the function reads them.
For the hosted project, `node tool/supabase_function_env.mjs --hosted
supabase/signing_keys.json` writes them to `supabase/functions/.env.hosted`
(also ignored) for `npx supabase secrets set --env-file`; delete it once
sent. docs/manual_deploy.md, "Going live", has the steps in order.

## Running the app against the local stack

Development builds use the Firebase Auth emulator and the local Supabase
stack together. `SUPABASE_URL` defaults to `http://localhost:54321`. The
key is passed in rather than written into the code:

```
firebase emulators:start --only auth
dart run tool/seed.dart auth
npx supabase start
flutter run -d chrome --dart-define=SUPABASE_ANON_KEY=<ANON_KEY from npx supabase status>
```

The app refuses to start on a bad combination, and says why:

- no key;
- the service-role or secret key, which skips every access rule;
- the Auth emulator with a hosted database.

Release builds (`scripts/deploy_web.ps1`, `scripts/build_apk.ps1` and the
web deploy workflow) take `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the
environment, or from the repository secrets of the same names.

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
which is Postgres compiled to WebAssembly. It is Postgres 18 where the
stack runs 17, so a pass here does not replace `npx supabase test db`.

```
cd tool/sql_tests
npm install
node run.mjs            # on an empty database
node run.mjs --seed     # with supabase/seed.sql loaded
```

`supabase_stub.sql` stands in for the parts of Supabase that PGlite doesn't
have: the `auth.jwt()` function, the storage tables and the API roles.

**The token exchange**, in Deno, offline:

```
npx deno@2.1.4 test --no-lock --config supabase/functions/firebase-token-exchange/deno.json supabase/functions/tests/
```

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
