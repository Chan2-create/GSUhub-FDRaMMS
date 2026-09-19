# Firebase Emulator Suite

Local Auth, Firestore and Storage, so day-to-day development never touches
the live `gsuhub-dorsu` project.

## Why bother

- **The live project stays clean.** Test reports, throwaway accounts and
  half-finished work orders never end up in the database used for the
  defense demo.
- **Spark plan quotas are finite.** Three developers iterating against
  live Firestore burn reads quickly; the emulator is free and unlimited.
- **Tests can be destructive.** The rules tests create and delete
  documents freely because nothing they touch is real.
- **It works offline.** Campus wifi is not a prerequisite for writing
  code.

## Prerequisites

```powershell
npm install -g firebase-tools
firebase login
```

```powershell
npm install     # rules-testing dependencies
```

**Java 21+ is required.** The Firestore emulator runs on the JVM, and
current `firebase-tools` refuses anything older than 21. This machine has
two JDKs by necessity:

| JDK | Used by | Path |
|---|---|---|
| 17 | Android Gradle build | `C:\Program Files\Eclipse Adoptium\jdk-17...` |
| 21 | Firebase emulators | `C:\Program Files\Eclipse Adoptium\jdk-21...` |

`JAVA_HOME` is set to **17** globally for Gradle. Point it at 21 in the
shell where you run the emulators:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"
firebase emulators:start
```

If you see *"firebase-tools no longer supports Java version before 21"*,
that is the step you missed.

## Daily workflow

**Terminal 1 — start the emulators:**

```powershell
cd "D:\Capstone System"
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"
firebase emulators:start
```

| Emulator | Port |
|---|---|
| Authentication | 9099 |
| Firestore | 8080 |
| Storage | 9199 |
| Emulator UI | 4000 |

Ports are declared in `firebase.json` and mirrored as defaults in
`lib/core/config/env.dart`. Change one and you must change the other.

**Terminal 2 — seed test data (first run, and after any reset):**

```powershell
dart run tool/seed_emulator.dart
```

**Terminal 3 — run the app against the emulators:**

```powershell
flutter run -d chrome
```

Debug builds use the emulators by default; no flag is needed. An orange
**EMULATOR** banner appears in the corner. If it is absent, the app is on
the live project — stop and check how it was launched.

## Seeded accounts

All use the password `password123`.

| Email | Role |
|---|---|
| `admin@dorsu.edu.ph` | GSU Administrator |
| `faculty@dorsu.edu.ph` | Faculty/Staff (requestor) |
| `personnel@dorsu.edu.ph` | Maintenance personnel (electrical) |
| `plumber@dorsu.edu.ph` | Maintenance personnel (plumbing) |

## Seeded data

- **4 facilities** — Engineering, Main Library, Administration, Science
- **3 assets** — aircon unit, projector, ceiling fan
- **5 inventory items** — two deliberately below their minimum threshold,
  so the low-stock alert path has something to show
- **4 tools** — one already in repair, one in poor condition
- **3 config documents** — including both conflicting prioritization
  weight schemes (see `docs/data_dictionary.md`)
- **5 damage reports** — spread across categories, statuses and
  priorities so every dashboard filter returns something

The seed script is re-runnable: every document has a fixed id, so a second
run overwrites rather than duplicating.

## Rules tests

**39 tests, all passing.** They start their own emulator, so nothing needs
to be running first:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"
npm run test:rules
```

### Why these are in Node, not `flutter test`

Firebase's Flutter plugins communicate over a platform channel, which does
not exist in the Dart-only VM that `flutter test` uses — `Firebase.initializeApp`
fails there with a `channel-error` no matter what flags are passed. Rules
genuinely cannot be exercised from `flutter test`.

`@firebase/rules-unit-testing` is what Firebase documents for this. It
runs in Node against the emulator, needs no device, and can write fixtures
with rules disabled — which is necessary, since the preconditions for a
rules test are themselves writes the rules would block.

### What they cover

The matrix in `firebase/firestore.rules`, including the cases most likely
to be wrong:

- a requestor cannot read another requestor's report, or their profile
- a requestor cannot escalate their own role or change their account status
- a requestor cannot pre-set `officialPriority` when submitting
- personnel cannot read work orders assigned to someone else, reassign one
  to themselves, or read feedback (§1.5)
- a **deactivated** account loses access despite valid credentials
- nobody — administrators included — can edit or delete an inventory
  transaction or an audit log entry
- unknown collections are denied by the catch-all

## Resetting

Emulator data is in-memory and disappears when the process stops. To reset
without restarting, use the Emulator UI at http://localhost:4000, or:

```powershell
# Ctrl+C the emulators, then:
firebase emulators:start
dart run tool/seed_emulator.dart
```

To keep data between runs:

```powershell
firebase emulators:start --export-on-exit=./.emulator-data --import=./.emulator-data
```

`.emulator-data/` is gitignored.

## Android against the emulators

An Android emulator reaches the host machine at `10.0.2.2`, not
`localhost`:

```powershell
flutter run -d <device> --dart-define=EMULATOR_HOST=10.0.2.2
```

A physical device needs the development machine's LAN IP (`ipconfig`), and
both must be on the same network.

## Troubleshooting

**"Could not connect to the GSUhub backend", emulator hint shown** — the
emulators are not running, or are on different ports than
`firebase.json` declares.

**Port already in use** — a previous emulator did not shut down cleanly:

```powershell
netstat -ano | findstr "8080 9099 9199 4000"
taskkill /PID <pid> /F
```

**Seed script says it cannot reach the emulator** — start the emulators
first. The script only ever talks to `localhost`; it cannot reach
production by design.

**Signed in but everything is `permission-denied`** — the rules read
`users/{uid}`. Either the seed did not run, or you signed in with an
account that has no seeded profile document.
