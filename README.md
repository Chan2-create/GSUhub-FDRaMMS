# GSUhub

**Facility Damage Reporting and Maintenance Management System** for the
General Services Unit (GSU) of Davao Oriental State University (DOrSU).

| | |
|---|---|
| Team | Estologa, Joemarie L. · Landoy, Nicole James S. · Ranque, Christian Ville M. |
| Program | Bachelor of Science in Information Technology, Davao Oriental State University |
| Live admin console | https://gsuhub-dorsu.vercel.app |
| Where each feature is in the code | [`CODE_GUIDE.md`](CODE_GUIDE.md) |

---

## 1. About the project

GSUhub replaces the GSU's paper-and-walk-in maintenance process with one
system. Faculty and staff report facility damage from their phones, with
photos, the place, a GPS geo-tag and a QR code. The system classifies
each report and recommends a priority by fixed rules. GSU administrators
review, assign and track the work on a web console. Maintenance
personnel receive the work on their phones, record the materials and
tools they use, and send an accomplishment report. The person who
reported the damage follows it live and rates the service.

## 2. System overview

One Flutter codebase builds three apps against one shared backend:

| App | Used by | Runs on | What it does |
|---|---|---|---|
| Admin console | GSU administrators | Web browser | Review and classify reports, set priorities, handle duplicates, assign work orders, sign off finished work, manage inventory, tools, rooms, equipment and accounts, analytics, Map View, settings |
| Faculty and staff app | Faculty and staff | Android | Sign up, report damage (photos, building and room, geo-tag, QR code), follow reports live, get notified, rate the service |
| Maintenance app | GSU maintenance personnel | Android | See assigned work orders and the day's tasks, tick tasks with proof photos, scan QR codes, record materials, borrow and return tools, send accomplishment reports |

The two phone apps are one APK; the account's role decides which opens.

```
 Admin console (web)     Faculty and staff app     Maintenance app
          \                       |                       /
           \______________ one Flutter codebase _________/
                                  |
        Firebase Authentication  ─┤─  sign-in (email and password)
        Firebase Cloud Messaging ─┤─  push notifications
                                  |
                 token exchange (Supabase Edge Function)
                                  |
                       Supabase (the backend)
          Postgres database: tables, row level security, and one
          database function per change; file storage for photos;
          live updates to every open screen
```

How a report moves: **Pending → Under review → Approved → Assigned → In
progress → For review → Completed → Closed** (or Merged as a duplicate,
Rejected, or Archived). Completion happens only through the administrator's
sign-off of the accomplishment report; rating the service closes it.

### Project status

All seven objectives of the work breakdown structure are built.

| Objective | Status |
|---|---|
| 1. Foundation, data model and backend services | Complete |
| 2. Admin web console: dashboard, reports, work orders, users, analytics | Complete |
| 3. Faculty and staff app: reporting, live tracking, notifications, feedback | Complete |
| 4. Rule-based classification, weighted priority, duplicate handling | Complete |
| 5. Maintenance app: work orders, tasks, accomplishment reports, scanning | Complete |
| 6. Inventory, tools, QR codes across the modules | Complete |
| 7. Integration, testing, documentation and deployment | Complete; usability testing with users is the team's ([`docs/testing.md`](docs/testing.md)) |

What was built, objective by objective, and why each decision was made:
[`docs/architecture_decisions.md`](docs/architecture_decisions.md).

## 3. Technologies

| Layer | Technology |
|---|---|
| Apps (web and Android) | Flutter 3.47.4, Dart 3.13 |
| State management | Riverpod |
| Navigation | go_router: one router for all three apps, each under its own URL prefix |
| Database | Supabase Postgres: row level security, and every change made by a database function that checks who is asking |
| Sign-in | Firebase Authentication (email and password); a Supabase Edge Function trades its token for a database token |
| Photos | Supabase Storage (a private bucket, signed links) |
| Live updates | Supabase Realtime |
| Push notifications | Firebase Cloud Messaging |
| Maps | flutter_map with OpenStreetMap tiles (no API key) |
| QR codes | mobile_scanner (scanning), barcode_widget and pdf (printable labels) |
| Hosting | Vercel (admin console), APK installed on Android 8.0 and later |
| Testing | flutter_test (unit and screen tests), pgTAP (database), Deno (sign-in bridge) |

## 4. Project structure

```
GSUhub/
├── lib/                          the app: all three apps' code
│   ├── main.dart, app.dart       start-up and the app itself
│   ├── core/                     shared by every feature
│   │   ├── config/               connection settings (URL, key, live or local)
│   │   ├── constants/            colors, text styles, screen sizes, table names
│   │   ├── data/                 base for the repositories: database calls, rows into records
│   │   ├── di/                   which repository and service the app uses
│   │   ├── enums/                statuses and roles (report status, work order status, ...)
│   │   ├── errors/               failures and plain-language error messages
│   │   ├── routing/              every page's URL, and who may open it
│   │   ├── services/             sign-in, database session, storage, GPS, camera, push
│   │   ├── utils/                small helpers (Result, dates, IDs)
│   │   └── widgets/              shared components: tables, cards, chips, dialogs, dropdowns
│   ├── features/                 one folder per system feature
│   │   ├── auth/                 login, sign-up
│   │   ├── dashboard/            admin dashboard, phone home screens
│   │   ├── analytics/            analytics page, CSV export
│   │   ├── user_management/      user accounts, personnel directory, profiles
│   │   ├── facilities/           rooms and equipment (assets)
│   │   ├── damage_reports/       report form, My Reports, admin report list and review
│   │   ├── classification/       keyword classification, priority score, duplicates
│   │   ├── work_orders/          assignment, Kanban board, work orders (admin and maintenance)
│   │   ├── tasks/                maintenance personnel's daily tasks
│   │   ├── accomplishment/       accomplishment reports, materials used on a job
│   │   ├── inventory/            materials, stock, deliveries, material requests
│   │   ├── tools/                tools, check-out and check-in, borrowing
│   │   ├── qr_codes/             QR labels (generating) and the scanner (reading)
│   │   ├── map_view/             Map View, geo-tag map and pin picker
│   │   ├── notifications/        notification pages and push
│   │   ├── feedback/             service ratings
│   │   ├── settings/             the Settings page
│   │   └── audit/                audit trail
│   └── shells/                   the frame around each app
│       ├── admin/                console sidebar, header, account menu
│       ├── requestor/            faculty and staff app's tabs
│       ├── personnel/            maintenance app's tabs
│       ├── mobile/               pieces both phone apps share
│       └── app_viewport.dart     screen-size scaling
├── supabase/                     the backend
│   ├── migrations/               the database, built step by step
│   ├── tests/                    database tests (pgTAP)
│   ├── functions/                the sign-in token exchange
│   └── seed.sql                  demo data for local runs
├── test/                         unit, screen and end-to-end tests
├── assets/                       fonts, icons, images
├── docs/                         documentation and diagrams
├── scripts/                      release builds: website and Android APK
├── tool/                         developer tools: run everything locally, demo data, SQL tests
├── android/, web/                platform projects
├── deploy/                       the website's hosting settings
├── firebase/                     old Firestore rules, kept until Firestore is locked
├── README.md                     this file
└── CODE_GUIDE.md                 where each feature is in the code
```

Inside every feature folder: `presentation/` (screens, dialogs and their
controllers), `domain/` (pure logic, where there is any), and
`data/models/` and `data/repositories/` (the records and the code that
reads and writes them). [`CODE_GUIDE.md`](CODE_GUIDE.md) lists the file
behind every feature, page and database function.

## 5. Installation and setup

You need:

- **Flutter 3.47 or later** (`flutter doctor` should pass).
- **Node.js 20 or later**, for the Supabase and Firebase command-line tools (`npx`).
- **Docker Desktop**, for the local Supabase stack.
- **Firebase CLI** (`npm install -g firebase-tools`), which needs **JDK 21**.
- For Android builds: the **Android SDK** (platform 35, build-tools 35.0.0) and **JDK 17**.

Then:

```powershell
git clone https://github.com/Chan2-create/GSUhub-FDRaMMS.git
cd GSUhub-FDRaMMS
flutter pub get

dart pub global activate flutterfire_cli
flutterfire configure --project=gsuhub-dorsu
```

**Credentials are not committed.** `lib/firebase_options.dart` holds the
Firebase keys and is gitignored, so a fresh clone does not build until
`flutterfire configure` writes it.
[`lib/firebase_options.example.dart`](lib/firebase_options.example.dart)
shows its shape. Ask a team member for access to the Firebase project.

## 6. Running the web application (admin console)

### Locally, with demo data

Debug builds sign in through the Firebase **Auth emulator** and read
data from the **local Supabase stack**, never the live projects. An
orange **EMULATOR** ribbon marks every screen while they do.

On Windows, one command starts everything (Docker Desktop running): the
database stack, the Auth emulator in its own window, the demo accounts,
and the app in Edge.

```powershell
tool\run_local.cmd              # opens the app in Edge
tool\run_local.cmd -Server      # serves it at http://localhost:5556 instead
tool\run_local.cmd -Reseed      # loads the demo data again
tool\run_local.cmd -Stop        # stops the stack
```

The demo accounts all use the password `password123`:

| Email | Role | Opens |
|---|---|---|
| `admin@dorsu.edu.ph` | Administrator | `/admin/login` (the console) |
| `faculty@dorsu.edu.ph` | Faculty and staff | `/staff/login` (faculty and staff app) |
| `personnel@dorsu.edu.ph` | Maintenance personnel | `/staff/login` (maintenance app) |

### Publishing the live website

The live console at https://gsuhub-dorsu.vercel.app is built on this
machine and uploaded to Vercel (signed in with `vercel login`):

```powershell
$env:SUPABASE_URL = 'https://<project-ref>.supabase.co'
$env:SUPABASE_ANON_KEY = '<the project publishable key>'
.\scripts\deploy_web.ps1        # -SkipDeploy builds and checks without uploading
```

Details, and the automatic deploy from GitHub:
[`docs/manual_deploy.md`](docs/manual_deploy.md).

## 7. Running the backend

GSUhub has **no custom server**. The backend is a Supabase project
(database, storage, live updates and the token exchange function) plus
Firebase for sign-in and push. Locally, both run on your machine:

```powershell
npx supabase start                    # database, storage, live updates, token exchange (Docker)
node tool/supabase_function_env.mjs   # first time only: the token exchange's secrets
npx supabase db reset                 # builds the database from the migrations, loads the demo data

firebase emulators:start --only auth  # sign-in on port 9099; keep this terminal open
dart run tool/seed.dart auth          # in a second terminal: the demo accounts
```

`tool\run_local.cmd` does all of this for you. Changing the database
means adding a migration to [`supabase/migrations/`](supabase/migrations/)
and its tests to [`supabase/tests/`](supabase/tests/);
[`supabase/README.md`](supabase/README.md) explains how a change to the
data works.

The live backend is the hosted Supabase project and the Firebase project
`gsuhub-dorsu`. New migrations reach it with
`npx supabase@2.122.1 db push --linked`
([`docs/manual_deploy.md`](docs/manual_deploy.md)).

## 8. Running the mobile application

With the local backend running (section 7), on an Android emulator:

```powershell
flutter run -d <device> --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=SUPABASE_ANON_KEY=<ANON_KEY from npx supabase status>
```

An Android emulator reaches your computer at `10.0.2.2`; a physical phone
needs your computer's LAN address (`ipconfig`) on the same network. The
phone apps also open in a browser at `/staff/login`.

### Building the release APK

```powershell
$env:SUPABASE_URL = 'https://<project-ref>.supabase.co'
$env:SUPABASE_ANON_KEY = '<the project publishable key>'
.\scripts\build_apk.ps1         # -Universal: one APK for every phone
```

Before each APK you share, raise the build number after the `+` in the
`version:` line of [`pubspec.yaml`](pubspec.yaml); Android will not
install a lower one over a higher one. The script needs the release
signing key ([`docs/manual_deploy.md`](docs/manual_deploy.md), "Release
signing") and writes
`build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.

## 9. Database configuration and connection overview

| Setting | Debug builds (development) | Release builds (website, APK) |
|---|---|---|
| Database | Local stack at `http://localhost:54321` | `--dart-define=SUPABASE_URL=https://<project-ref>.supabase.co` |
| Database key | `--dart-define=SUPABASE_ANON_KEY=<local key>` | `--dart-define=SUPABASE_ANON_KEY=<publishable key>` |
| Sign-in | Firebase Auth emulator on port 9099 | Firebase project `gsuhub-dorsu` |

The settings are read in [`lib/core/config/env.dart`](lib/core/config/env.dart).
The app refuses to start without the key, or with a secret
(service-role) key, which must never reach an app.

How a signed-in request reaches the data:

1. The person signs in with Firebase Authentication
   ([`firebase_auth_service.dart`](lib/core/services/firebase/firebase_auth_service.dart)).
2. The app trades the Firebase token for a short-lived database token at
   the token exchange function
   ([`supabase/functions/firebase-token-exchange/`](supabase/functions/firebase-token-exchange/)),
   through [`supabase_session.dart`](lib/core/services/supabase/supabase_session.dart).
3. Every read goes through row level security, which limits each person
   to what their role may see
   ([`20261016130005_row_level_security.sql`](supabase/migrations/20261016130005_row_level_security.sql)).
4. Every change is a call to a database function, which checks the role
   and the record's state, writes the change, the audit entry and any
   notification together, or refuses with a reason
   ([`supabase/migrations/`](supabase/migrations/)).
5. Screens that show live data subscribe to Supabase Realtime and update
   on their own.

In the app, each feature's repository
(`lib/features/<feature>/data/repositories/*_repository_impl.dart`) is
the only code that calls the database, on the base class
[`lib/core/data/supabase_repository.dart`](lib/core/data/supabase_repository.dart).
Every table, field and permission:
[`docs/data_dictionary.md`](docs/data_dictionary.md).

## 10. Important modules and where to find them

| System feature | Where to find it |
|---|---|
| Login and authentication | [`lib/features/auth/`](lib/features/auth/), [`lib/core/routing/route_guards.dart`](lib/core/routing/route_guards.dart), [`supabase/functions/firebase-token-exchange/`](supabase/functions/firebase-token-exchange/) |
| Dashboard | [`lib/features/dashboard/`](lib/features/dashboard/) |
| User management | [`lib/features/user_management/`](lib/features/user_management/) |
| Facility and asset management | [`lib/features/facilities/`](lib/features/facilities/) |
| Damage reporting | [`lib/features/damage_reports/`](lib/features/damage_reports/) |
| Classification and priority | [`lib/features/classification/`](lib/features/classification/) |
| Maintenance management | [`lib/features/work_orders/`](lib/features/work_orders/), [`lib/features/tasks/`](lib/features/tasks/), [`lib/features/accomplishment/`](lib/features/accomplishment/) |
| Inventory | [`lib/features/inventory/`](lib/features/inventory/) |
| Tools management | [`lib/features/tools/`](lib/features/tools/) |
| QR codes | [`lib/features/qr_codes/`](lib/features/qr_codes/) |
| Map View | [`lib/features/map_view/`](lib/features/map_view/) |
| Notifications | [`lib/features/notifications/`](lib/features/notifications/) |
| Feedback and ratings | [`lib/features/feedback/`](lib/features/feedback/) |
| Analytics | [`lib/features/analytics/`](lib/features/analytics/) |
| Settings | [`lib/features/settings/`](lib/features/settings/) |
| Shared components and layouts | [`lib/core/widgets/`](lib/core/widgets/), [`lib/shells/`](lib/shells/) |
| Database | [`supabase/migrations/`](supabase/migrations/), [`supabase/tests/`](supabase/tests/) |

Every file, page and database function, feature by feature:
**[`CODE_GUIDE.md`](CODE_GUIDE.md)**.

---

## Tests

```powershell
flutter analyze                 # static checks
flutter test                    # unit and screen tests
dart format --set-exit-if-changed lib test

npx supabase test db            # database tests (needs the local stack)
cd tool/sql_tests; npm install; node run.mjs   # the same, without Docker
```

[`test/e2e/`](test/e2e/) drives the three main flows against the local
stack when `SUPABASE_E2E=1` is set. Which test proves each requirement,
and the usability checklist: [`docs/testing.md`](docs/testing.md).

## First administrator account

Only an administrator can create accounts with a role, so no account can
promote itself. The **first** administrator is created once, by hand:

1. **Firebase Console → Authentication → Add user**: the institutional
   email and a temporary password. Copy the generated UID.
2. **Supabase dashboard → SQL Editor**:

   ```sql
   insert into public.users (id, full_name, email, role, account_status)
   values ('<the UID>', '<full name>', '<the email>', 'admin', 'active');
   ```

3. Sign in and change the password.

Every account after that is created in the app, so the audit trail
records who created whom.

## Troubleshooting

- **"The database connection is not configured"**: `SUPABASE_ANON_KEY` is
  missing or wrong; the screen says which.
- **`firebase emulators:start` says "port taken"** with nothing
  listening: Windows reserves shifting port ranges at boot. Check with
  `netsh interface ipv4 show excludedportrange protocol=tcp`; an elevated
  `net stop winnat` then `net start winnat`, or a restart, frees them.
- More: [`docs/local_setup.md`](docs/local_setup.md).

## Documentation

| Document | Contents |
|---|---|
| [`CODE_GUIDE.md`](CODE_GUIDE.md) | Where each feature, page and database function is in the code |
| [`docs/architecture_decisions.md`](docs/architecture_decisions.md) | What was built, what was deferred, and why |
| [`docs/data_dictionary.md`](docs/data_dictionary.md) | Every table, field and constraint, and who may read and change what |
| [`docs/testing.md`](docs/testing.md) | Each requirement and the tests that prove it; the usability checklist |
| [`docs/demo_script.md`](docs/demo_script.md) | The final presentation's walkthrough, account by account |
| [`docs/local_setup.md`](docs/local_setup.md) | Running everything locally, in detail |
| [`docs/manual_deploy.md`](docs/manual_deploy.md) | The hosted projects, website deploys, release APKs |
| [`docs/firebase_setup.md`](docs/firebase_setup.md) | Firebase console settings |
| [`supabase/README.md`](supabase/README.md) | The database: how a change works, the tests, the demo data |
| [`docs/git_workflow.md`](docs/git_workflow.md) | Branches, commit messages, pull requests |
| [`docs/diagrams/`](docs/diagrams/) | System diagrams |

## Contributing

Branch from `main` as `feature/<wbs-id>-<short-description>` and open a
pull request; `main` stays buildable. See
[`docs/git_workflow.md`](docs/git_workflow.md).
