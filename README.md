# GSUhub

**Facility Damage Reporting and Maintenance Management System** for the
General Services Unit (GSU) of Davao Oriental State University (DOrSU).

GSUhub replaces the GSU's paper-and-walk-in maintenance workflow with a
single system for reporting facility damage, classifying and prioritising
it, assigning work to maintenance personnel, and tracking the job through
to completion. One Flutter codebase serves three role-specific clients
against one shared Firebase backend:

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
| Database | Cloud Firestore |
| Auth | Firebase Authentication (email/password) |
| Files | Firebase Storage |
| Push | Firebase Cloud Messaging |
| Testing | flutter_test, fake_cloud_firestore, `@firebase/rules-unit-testing` |

Firebase project `gsuhub-dorsu`, region `asia-southeast1`, Spark plan.

## Progress

Work proceeds objective by objective against the project WBS.

| Objective | Scope | Status |
|---|---|---|
| 1.A | Project scaffold, three shells, routing, config, service interfaces | Complete |
| 1.B | Data models, repository contracts, security rules, indexes | Complete |
| 1.C | Firebase wiring, repository implementations, emulator suite | Complete |
| 2.A | Admin authentication, dashboard, main layout | Complete |
| 2.B | Damage report management and work orders | Not started |
| 2.C | Analytics, personnel and user account management | Not started |
| 3 | Requestor mobile app | Not started |
| 5 | Maintenance personnel mobile app | Not started |
| 6 | Inventory management | Not started |

The administrator console is the only role with working screens. The
requestor and personnel shells route correctly and are guarded by role,
but resolve to placeholders.

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

### Against the emulator suite (recommended for development)

Debug builds use the emulators **by default** — `gsuhub-dorsu` is the
project the team demos from, so reaching it from a debug build takes an
explicit `--dart-define=USE_LIVE_FIREBASE=true`. Start the emulators
first; without them, sign-in fails with a connection error.

```bash
firebase emulators:start              # auth 9099, firestore 8080, storage 9199
dart run tool/seed_emulator.dart      # realistic test data

flutter run -d edge
```

Seeded accounts all use the password `password123`:

| Email | Role |
|---|---|
| `admin@dorsu.edu.ph` | Administrator — the only role with screens |
| `faculty@dorsu.edu.ph` | Requestor |
| `personnel@dorsu.edu.ph` | Maintenance personnel |

An orange **EMULATOR** ribbon marks the UI whenever the app is pointed at
the local suite, so seeded data is never mistaken for the live project.
The emulator database is in-memory — re-run the seed script after every
restart.

On Windows, `firebase emulators:start` can fail with *"port taken"* even
when nothing is listening. Windows reserves shifting TCP ranges at boot;
check with `netsh interface ipv4 show excludedportrange protocol=tcp`. An
elevated `net stop winnat` / `net start winnat` frees them.

### Against the live project

```bash
flutter run -d edge --dart-define=USE_LIVE_FIREBASE=true   # debug build
flutter build web                                          # release: live by default
```

### Tests

```bash
flutter analyze
flutter test                          # Dart unit and widget tests
dart format --set-exit-if-changed .

npm install && npm test               # Firestore security rules
```

The rules tests run under Node rather than `flutter test`: the Firebase
plugins need a platform channel the Dart test VM does not provide.

## First administrator account

Security rules allow creating a `users` document only to an existing
administrator, which is deliberate — it stops any account promoting
itself. That means the **first** administrator cannot be created through
the app, and on the Spark plan there is no Cloud Function to do it.

Create it once by hand in the Firebase Console:

1. **Authentication → Add user** — institutional email and a temporary
   password. Copy the generated UID.
2. **Firestore → `users` → Add document** with the document ID set to
   exactly that UID.
3. Fields: `role: "admin"`, `isActive: true`, plus `email`, `fullName`,
   `createdAt`.
4. Sign in and change the password immediately.

Every account after that is provisioned by an administrator through the
app, so the audit log records who created whom.

## Project structure

```
lib/
  core/          config, constants, enums, error types, Result,
                 abstract service interfaces, routing, shared widgets.
                 No shell-specific or Firebase-specific code.
  core/services/ the only place Firebase SDKs are imported, alongside
  data/          repositories. UI talks to repositories, never Firebase.
  shells/        one router outlet per role, presentation only.
  features/      feature modules, built per WBS objective.
firebase/        Firestore security rules and composite indexes.
test/            unit, widget and rules tests.
tool/            developer scripts, including the emulator seeder.
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
| [`docs/data_dictionary.md`](docs/data_dictionary.md) | Every collection, field, type and constraint |
| [`docs/firebase_setup.md`](docs/firebase_setup.md) | Console configuration |
| [`docs/emulator_setup.md`](docs/emulator_setup.md) | Local emulator suite |
| [`docs/git_workflow.md`](docs/git_workflow.md) | Branches, commit conventions, PR process |

## Contributing

See [`docs/git_workflow.md`](docs/git_workflow.md). Branch from `main` as
`feature/<wbs-id>-<short-description>`, e.g. `feature/2b-work-orders`, and
open a pull request. `main` stays buildable.
