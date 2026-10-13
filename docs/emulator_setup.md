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
| `elena.cruz@dorsu.edu.ph` | GSU Administrator (a second one) |
| `faculty@dorsu.edu.ph` | Faculty/Staff (requestor) |
| `ana.gomez@dorsu.edu.ph` | Faculty/Staff |
| `paolo.garcia@dorsu.edu.ph` | Faculty/Staff |
| `grace.lim@dorsu.edu.ph` | Faculty/Staff — **deactivated**, cannot sign in |
| `liza.tan@dorsu.edu.ph` | Faculty/Staff — signed up, **awaiting approval**; approve it from User Accounts |
| `personnel@dorsu.edu.ph` | Maintenance personnel (electrical) |
| `plumber@dorsu.edu.ph` | Maintenance personnel (plumbing) |
| `structural@dorsu.edu.ph` | Maintenance personnel (structural) |
| `carpenter@dorsu.edu.ph` | Maintenance personnel (carpentry) — on leave |
| `general@dorsu.edu.ph` | Maintenance personnel (general maintenance) |
| `aircon@dorsu.edu.ph` | Maintenance personnel (air conditioning) — **deactivated** |

## Seeded data

- **10 facilities** — rooms across Engineering, Main Library,
  Administration, Science and the Gymnasium, so the report form's
  Building and Room selects have real choices. Each carries a QR value
  `FAC-<ID IN CAPITALS>`, e.g. `FAC-FAC-ENGINEERING-203`.
- **3 assets** — aircon unit, projector, ceiling fan (QR `AST-…`)
- **8 materials** — Figure 15's five and Group 43's, with sizes and unit
  costs (the floor sealant has none, so Total Stock Value has one to
  leave out); three are below their minimum, so the low-stock alerts have
  something to show. Their ledger is seeded too: each history job's
  materials and an opening delivery, ending at today's stock.
- **5 tools** — one in repair, one in poor condition, the multimeter out
  with `personnel@` and due back today
- **4 material requests** — two waiting (Marcus on `wo-0003`, Juan on
  `wo-0002`), one declined with GSU's note, one approved, its materials
  pre-assigned to `wo-0013`
- **3 config documents** — Table 3.3's keywords, both prioritization
  weight schemes with the formula's in use, and the duplicate settings
  (see `docs/data_dictionary.md`)
- **Damage reports and work orders** — spread across categories,
  statuses and priorities, plus six months of resolved history for
  Analytics. All are `faculty@`'s except two filed by `ana.gomez@`, so
  My Reports can be seen leaving someone else's report out. Between them
  the current reports reach every status, including one waiting for
  sign-off, one rejected with a reason, one merged and one archived, and
  every report has its status history (3.B). Reviewed reports carry the
  four ratings and score behind their official priority (4.B).
- **31 notifications** — one for each move a reporter is told of, on the
  current reports; those older than two days are already read, so Alerts
  shows both states.
- **Ratings** — every closed report in the six-month history has one,
  and was closed by it (3.C). `rep-0005`, "Cracked Wall Near Stairwell",
  is completed and not yet rated, to try rating on.
- **Personnel work (5.A–5.C)** — 9 tasks across the open work orders,
  4 LED bulbs recorded on `wo-0003`, the multimeter borrowed by
  `personnel@`, two accomplishment reports (one signed off, one waiting
  for sign-off) and 6 notices to technicians.

## The personnel app (Objectives 5.A–5.C)

Sign in on the mobile sign-in page (in a browser,
`http://localhost:<port>/#/staff/login`) as `personnel@dorsu.edu.ph`
(Marcus Wright, electrical). It lands on the personnel dashboard.

- **Home** shows today's tasks, the counts and the open work orders.
  "Sparking Wall Outlet" (`wo-0013`) is new and not started; tick its
  first task, or open it and press **Start work**, and it moves to in
  progress (the requestor's report and timeline follow).
- **Finish a job.** Open "Flickering Lights" (`wo-0003`, in progress):
  it has four tasks, 4 LED bulbs recorded and the multimeter borrowed.
  Record or change materials, return the multimeter, then add a photo
  and completion notes and press **Mark Complete**. The confirmation
  lists what comes off stock. After submitting, the work waits for
  sign-off and the LED stock has dropped.
- **Sign off** in the console as `admin@`: Work Orders → the work
  order's number opens its page. "Loose Ceiling Panel" (`wo-0009`) is
  waiting already. **Approve and sign off** completes it; **Send back for
  rework** asks for a note, which the technician sees at the top of the
  work order. The same page adds tasks; the technician is told.
- **Scan** with the gold **+**. On a phone, show a code for a seeded
  value from any QR or barcode generator: `INV-INV-LED-BULB` (a
  material), `TOOL-TL-0912` (the multimeter) or a room's `FAC-…`. In a
  browser without a camera, go to
  `http://localhost:<port>/#/personnel/scan?code=TOOL-TL-0912` instead.
- **Materials** lists what you have recorded per open work order and the
  tools you have.

## Classification, priority and duplicates (Objectives 4.A–4.C)

Sign in to the console as `admin@`.

- **Review a report.** Task Assignment lists "Clogged Drain in
  Laboratory 2" (`rep-0007`) and "Ceiling Stain Spreading" (`rep-0008`)
  with **Review type and priority** instead of Assign: neither has an
  official priority yet. Open one. The **Classification and priority**
  panel shows the keywords found ("clogged drain" → Plumbing; none for
  the stain, so pick a type), a Frequency rating filled in from similar
  reports at the building, and the score as you rate Severity, Safety
  risk and Location importance. The official priority follows the
  recommendation until you pick another. Confirm, and the report can be
  assigned.
- **Duplicates.** The reports table marks `#REP-0001` and
  `#REP-ANA-0002`: Ana reported the same fan in Room 101. Open either:
  **Possible duplicates** gives the reasons, and offers **Merge** (the
  one still awaiting review is closed into the other, and its requestor
  told) or **Keep separate**. `rep-0002` and `rep-0007`, plumbing at the
  same building, were already kept separate and are not flagged.
- **Keywords.** **Settings** lists the keywords per damage type. Type a
  description into **Try a description**, add a keyword, and watch the
  result change before you save. Saved keywords classify reports filed
  from then on, on the phone, as they are submitted: file a report
  whose description says "short circuit" and it arrives classified as
  Electrical.

## Inventory, tools and QR codes (Objectives 6.A–6.C)

Sign in to the console as `admin@` and open **Inventory Management**
(its red count is the materials low on stock).

- **Materials.** PVC pipe, white paint and insulation tape show LOW STOCK
  and **ORDER**: press it, record a delivery, and the alert clears. Click
  a card for its details and stock history (each use links to its work
  order), a stock count, and its QR label. **Add Material** adds one with
  its opening stock.
- **Requests.** Material Requests lists Marcus's and Juan's. **Approve**
  puts the items on the work order's pre-assigned list and tells the
  technician; **Decline** asks why. Stock does not move until the
  technician's report is filed.
- **Tools.** **Check Out** the Fiber Optic Cleaver to a technician; the
  multimeter shows **Check In**. Click a tool for its loans, repair and
  retire, and its label. **Scan QR** uses the computer's camera.
- **Facilities & Equipment** (sidebar, under System) lists every room and
  piece of equipment with its code. Add, edit, deactivate; each row's QR
  icon shows its label, and **Print all labels** saves an A4 sheet to cut.
- **Analytics** ends with Most Used Materials for the chosen period, and
  **Export inventory report** (a CSV of stock and movements).
- On the phone, as `personnel@`: "Sparking Wall Outlet" shows the
  materials GSU pre-assigned; **Request Materials** opens Group 43's page,
  with "Flickering Lights"'s request history (one waiting, one declined).

## The faculty and staff app (Objectives 3.A, 3.B and 3.C)

Off the web the app opens on the faculty and staff sign-in. In a browser
the app is the admin console; go to `http://localhost:<port>/#/staff/login`
for the faculty side (sign out of the console first — one browser holds
one session).

- **Sign in** as `faculty@dorsu.edu.ph` to reach Home, My Reports and the
  report form (the gold **+**).
- **Watch a report move.** Open a report on the faculty side, then in
  the console (another browser profile, or a private window) Start
  review, Approve or assign it. The faculty page, its timeline, the
  Alerts list and the unread badge update without a reload.
- **Rate a finished job.** Open "Cracked Wall Near Stairwell" (completed)
  and tap Rate this Service, or its "Work completed" alert. Give all three
  ratings and submit: the report closes, "Closed" joins its timeline, and
  the rating shows at the bottom of the report. Skip leaves it completed.
- **Sign up** from CREATE ACCOUNT. The new account is `pending`: signing
  in says it awaits approval. Approve it from the console's User Accounts
  (⋮ → Approve), then it signs in. `liza.tan@dorsu.edu.ph` is a seeded
  request to try this on.
- Firebase shows its own "Running in emulator mode" bar along the bottom
  of the page in a browser; it covers the bottom bar's labels and is not
  part of the app.
- In a browser, don't reload a page while signed in on the faculty side:
  Firebase restores the session against the live Auth service before the
  app points it at the emulator, and later sign-ins in that tab fail.
  Open a new tab instead.

Push on a phone (3.B): with GSUhub open or in the background, a report's
move raises a system notification on the phone itself. Nothing reaches
a phone whose GSUhub is closed — that needs a Cloud Function on the
Blaze plan (docs/architecture_decisions.md §16). To try a real push,
send a test message from the Firebase console to the token saved on the
account, with data `reportId`, `recipientId` and `notificationId`.

To test QR lookup on a phone, show a QR code for a seeded value (e.g.
`FAC-FAC-ENGINEERING-203`, or `AST-ASSET-AIRCON-01` for equipment) from
any QR generator. Photos land in the Storage emulator under
`damage_reports/<report id>/`; the map tiles come from OpenStreetMap, so
the map needs internet even when everything else is local.

The seed script is re-runnable: every document has a fixed id, so a second
run overwrites rather than duplicating.

## Rules tests

**135 tests, all passing.** They start their own emulator, so nothing needs
to be running first (stop `firebase emulators:start` first: both want
port 8080):

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
- personnel work (5.A–5.C): personnel list only their own work orders,
  tasks, accomplishment reports and tool loans, and read a report only
  when it is their work; they may only start and submit work, tick tasks
  and add proof; materials are recorded by the assigned technician, at
  server time, only while the work is open; an accomplishment report is
  filed only in the write that submits the work, says truly whether stock
  was deducted, and only an administrator reviews it
- inventory (6.A–6.C): a technician requests materials only for their own
  open work, pending and unreviewed, and lists only their own requests;
  only an administrator reviews one, once, with a reason to decline;
  pre-assigned materials are the administrator's to set and the assigned
  technician's to read; an administrator checks tools out to technicians
  only; only an administrator adds materials and rooms
- a **deactivated** account loses access despite valid credentials
- self-registration (3.A): a person may create only their own profile,
  only as a `pending` requestor under their own email with server time;
  a pending account reads nothing but its own profile until approved
- a requestor lists their own reports only, at most 100 at a time
- status history (3.B) is append-only: a requestor reads only their own
  reports' and writes only the first entry while filing; nobody edits or
  deletes one
- notifications (3.B): each reaches only the report's own reporter; a
  requestor creates none for anyone else, reads only their own, and may
  change nothing but marking one read
- rating (3.C): a requestor rates only their own completed report, once,
  three ratings 1–5, and only in the write that closes it; closing it is
  the one change they may make to their report
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
