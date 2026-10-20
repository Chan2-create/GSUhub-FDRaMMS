# GSUhub

**Facility Damage Reporting and Maintenance Management System** for the
General Services Unit (GSU) of Davao Oriental State University (DOrSU).

GSUhub replaces the GSU's paper-and-walk-in maintenance workflow with a
single system for reporting facility damage, classifying and prioritising
it, assigning work to maintenance personnel, and tracking the job through
to completion. One Flutter codebase serves three role-specific clients
against one shared backend — sign-in on Firebase, data and photos on
Supabase:

| Role | Platform | Shell |
|---|---|---|
| GSU Administrator | Web | `lib/shells/admin/` |
| Faculty/Staff (Requestor) | Mobile (Android) | `lib/shells/requestor/` |
| GSU Maintenance Personnel | Mobile (Android) | `lib/shells/personnel/` |

## Team

- Estologa, Joemarie L.
- Landoy, Nicole James S.
- Ranque, Christian Ville M.

Bachelor of Science in Information Technology — Davao Oriental State
University.

## Tech stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.47 / Dart 3.13 |
| State & DI | Riverpod |
| Routing | go_router — one path-prefixed router for all three shells |
| Database | Supabase Postgres — row level security, every write a database function |
| Auth | Firebase Authentication (email/password); a Supabase Edge Function trades its token for a database token |
| Files | Supabase Storage (a private bucket, signed links) |
| Live updates | Supabase Realtime |
| Push | Firebase Cloud Messaging |
| Testing | flutter_test, pgTAP (in PGlite without Docker), Deno, fake_cloud_firestore for the widget harnesses |

Firebase project `gsuhub-dorsu` (sign-in and push), Spark plan; a
Supabase project for the data (Objective 1, docs/architecture_decisions.md
§21).

## Progress

Work proceeds objective by objective against the project WBS.

| Objective | Scope | Status |
|---|---|---|
| 1.A | Project scaffold, three shells, routing, config, service interfaces | Complete |
| 1.B | Data models, repository contracts, security rules, indexes | Complete |
| 1.C | Firebase wiring, repository implementations, emulator suite | Complete |
| 1 (backend split) | Data, photos and live updates on Supabase; Firebase for sign-in and push only | Complete; not yet run against a real Supabase stack (needs Docker) |
| 2.A | Admin authentication, dashboard, main layout | Complete |
| 2.B | Damage report management, task assignment, work-order Kanban | Complete |
| 2.C | Analytics, personnel and user account management | Complete |
| 3.A | Faculty and staff sign-in and sign-up (pending approval), home, My Reports, bottom bar | Complete |
| 3.B | Real-time report tracking, status timeline, notifications and the Alerts tab | Complete (push to a closed app needs Blaze; not yet tried on a phone) |
| 3.C | Faculty and staff damage report submission (photos, geo-tag, QR lookup) | Complete |
| 3.C (feedback) | Post-service feedback and rating: three ratings, rating closes the report | Complete |
| 4.A | Rule-based keyword classification, run as a report is filed; keyword editor in Settings | Complete |
| 4.B | Weighted priority score (§3.4 formula), administrator's ratings with a Frequency hint | Complete |
| 4.C | Confirming or changing the official priority before assignment; duplicate detection, merge, keep separate | Complete |
| 5.A | Personnel sign-in (shared with faculty), dashboard, tasks, work orders; admin adds tasks in the console | Complete |
| 5.B | Starting work, ticking tasks with proof, the accomplishment report; admin signs off or sends back | Complete |
| 5.C | Scanning QR codes and barcodes; recording materials used, borrowing and returning tools | Complete (requesting more materials came in 6.B) |
| 6.A | Inventory Management page (Figure 15): materials, unit costs, deliveries, stock counts, stock history, low-stock alerts | Complete |
| 6.B | Tools: check out, check in, repair, retire; technicians' material requests and pre-assigned materials | Complete |
| 6.C | QR codes and printable labels for materials, tools, rooms and equipment; Facilities & Equipment page; Most Used Materials and the inventory CSV | Complete |

The administrator console has working screens for every 2.x objective:
the dashboard, damage reports and their detail view, task assignment,
the work-order board, the personnel directory, analytics with a CSV
export, and user account management, where faculty sign-ups are
approved. Each report's page holds its review: damage type, the four
priority ratings and score, the official priority, and any possible
duplicates to merge or keep separate (4.A–4.C); Settings edits the
classification keywords. The faculty and staff app has its own sign-in and sign-up, a
home screen with the requestor's report overview, My Reports, the damage
report form (3.C), live tracking with a status timeline and an Alerts
tab (3.B), and rating a finished job, which closes the report (3.C) —
see docs/local_setup.md. Its Profile tab holds
only Sign out. Maintenance personnel sign in on the same page and land
in their own app (5.A–5.C): a dashboard with the day's tasks, their work
orders with tasks to tick off and proof photos, materials and tools
recorded by scan or from a list, and the accomplishment report that
sends the work to GSU for sign-off. Each work order has a page in the
console, where the administrator adds tasks and signs off or sends back
the report. Inventory Management (6.A–6.B) keeps the store: materials with
their stock, cost and history, deliveries and counts, low-stock alerts,
the tools and who has them, and the technicians' requests for more
materials. Facilities & Equipment registers the rooms and equipment, and
every material, tool, room and piece of equipment prints its QR label
(6.C).

## Setup

Requires Flutter 3.47+, and the Android SDK (platform 35, build-tools
35.0.0) plus JDK 17 for mobile builds. The Firebase CLI needs JDK 21.

**Credentials are not committed.** `lib/firebase_options.dart` holds real
API keys and is gitignored, so a fresh clone will not build until you
generate your own:

```bash
flutter pub get

dart pub global activate flutterfire_cli
flutterfire configure --project=gsuhub-dorsu
```

`lib/firebase_options.example.dart` documents the shape of the generated
file. Ask a team member for access to the Firebase project.

## Running locally

### Against the local services (recommended for development)

Debug builds sign in with the Firebase **Auth emulator** and read data
from the **local Supabase stack** by default. `gsuhub-dorsu` is the
project the team demos from, so reaching the live projects from a debug
build takes explicit flags. Docker Desktop must be running for the local
stack. The full walkthrough is [`docs/local_setup.md`](docs/local_setup.md).

```bash
npx supabase start                    # the database, photos, realtime, the token exchange
node tool/supabase_function_env.mjs   # first time: the token exchange's secrets
npx supabase db reset                 # the demo data

firebase emulators:start --only auth  # sign-in, on port 9099; keeps its terminal
dart run tool/seed.dart auth          # in a second terminal: the sign-in accounts

flutter run -d edge --dart-define=SUPABASE_ANON_KEY=<ANON_KEY from npx supabase status>
```

Seeded accounts all use the password `password123`:

| Email | Role |
|---|---|
| `admin@dorsu.edu.ph` | Administrator |
| `faculty@dorsu.edu.ph` | Requestor |
| `personnel@dorsu.edu.ph` | Maintenance personnel |

An orange **EMULATOR** ribbon marks the UI whenever the app is pointed at
the local services, so seeded data is never mistaken for the live project.

On Windows, `firebase emulators:start` can fail with *"port taken"* even
when nothing is listening. Windows reserves shifting TCP ranges at boot;
check with `netsh interface ipv4 show excludedportrange protocol=tcp`. An
elevated `net stop winnat` / `net start winnat` frees them.

### Against the live projects

```bash
flutter run -d edge --dart-define=USE_LIVE_FIREBASE=true --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<key>
flutter build web --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…   # release: live by default
```

The app refuses to start without the key, or with the service-role key.

### Tests

```bash
flutter analyze
flutter test                          # Dart unit and widget tests
dart format --set-exit-if-changed .

npx supabase test db                  # the database's pgTAP tests (local stack)
cd tool/sql_tests && npm install && node run.mjs   # the same, without Docker
```

`test/e2e` drives the three main flows against the local stack; it runs
with `SUPABASE_E2E=1` set. See [`supabase/README.md`](supabase/README.md).

## First administrator account

Only an administrator can create accounts with a role, which is
deliberate — it stops any account promoting itself. That means the
**first** administrator cannot be created through the app.

Create it once by hand:

1. **Firebase Console → Authentication → Add user** — institutional email
   and a temporary password. Copy the generated UID.
2. **Supabase dashboard → SQL Editor**, run (it runs as the database
   owner, past row level security):

   ```sql
   insert into public.users (id, full_name, email, role, account_status)
   values ('<the UID>', '<full name>', '<the email>', 'admin', 'active');
   ```

3. Sign in and change the password immediately.

Every account after that is provisioned by an administrator through the
app, so the audit log records who created whom.

## Project structure

```
lib/
  core/          config, constants, enums, error types, Result,
                 abstract service interfaces, routing, shared widgets.
                 No shell-specific or backend-specific code.
  core/services/ the only place the Firebase and Supabase SDKs are
  data/          imported, alongside the repositories. UI talks to
                 repositories, never a backend.
  shells/        one router outlet per role, presentation only.
  features/      feature modules, built per WBS objective.
supabase/        the database: migrations, pgTAP tests, the demo data,
                 the token exchange Edge Function.
firebase/        the old Firestore rules (until its data is moved).
test/            unit, widget, contract and end-to-end tests.
tool/            developer scripts: the seed generator, the SQL test
                 runner, the Firestore → Supabase migration.
scripts/         release builds: web deploy to Vercel, the Android APK.
deploy/          Vercel's settings for the deployed console.
docs/            architecture decisions, data dictionary, setup guides.
assets/          bundled fonts, icons and images.
```

Five architectural rules — the Shared Backend Contract — govern the
boundary between UI and backend. They are stated in
[`docs/architecture_decisions.md`](docs/architecture_decisions.md) and are
the reason a backend swap would touch the DI files and nothing else.

## Documentation

| Document | Contents |
|---|---|
| [`docs/architecture_decisions.md`](docs/architecture_decisions.md) | What was built, what was deferred, and why |
| [`docs/data_dictionary.md`](docs/data_dictionary.md) | Every table, field, type and constraint, and who may read and change what |
| [`docs/firebase_setup.md`](docs/firebase_setup.md) | Console configuration |
| [`docs/local_setup.md`](docs/local_setup.md) | The Auth emulator and the local Supabase stack |
| [`supabase/README.md`](supabase/README.md) | The database: how a write works, the tests, the demo data |
| [`docs/manual_deploy.md`](docs/manual_deploy.md) | Setting up the hosted Supabase project and moving the data, automatic web deploys to Vercel and their secrets, building the release APK |
| [`docs/git_workflow.md`](docs/git_workflow.md) | Branches, commit conventions, PR process |

## Contributing

See [`docs/git_workflow.md`](docs/git_workflow.md). Branch from `main` as
`feature/<wbs-id>-<short-description>`, e.g. `feature/2b-work-orders`, and
open a pull request. `main` stays buildable.
