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
| `functions/firebase-token-exchange/` | Trades a Firebase ID token for a Supabase access token. See below. |
| `functions/tests/` | Its tests, in Deno. |

The `app` schema is not exposed through the API. Its functions run with
the owner's rights, so each one checks the caller itself.

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
On the hosted project, use `npx supabase secrets set`.

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
which is Postgres compiled to WebAssembly.

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
