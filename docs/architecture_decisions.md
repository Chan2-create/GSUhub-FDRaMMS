# Architecture Decisions

Scope: WBS Objective **1.A** — "Set up project architecture, development
environment, and version control for the web and mobile components"
(`GSUhub_WBS_Simplified`, which supersedes the earlier, more granular WBS
this project started from). This document records every non-obvious
decision made while scaffolding, and flags where a decision was made in
the absence of a source document that should normally have settled it.

This ADR was originally written for the old WBS's Objective 1.1(a)
(Admin-web-only scaffolding) and has been rewritten here to cover the
full 1.A scope: three shells, a shared service layer, and version
control. Where something below says "carried forward," it was true under
1.1(a) and remains true now.

## 0. `GSUhub_Development_Plan.md` was not available (carried forward)

Neither this objective's brief nor the previous one's ever had this file
attached, despite both citing it as authoritative for the exact folder
layout, the report-lifecycle state machine, the Firestore collection
list, composite indexes, and two "known blockers" (conflicting priority
weights; an undefined criterion-rating source). The project directory was
also empty at the very start of this work.

Per explicit instruction (twice now), this build proceeds from the
**capstone manuscript** and the **current WBS** only. The two known
blockers are still not resolved — they don't block this objective, and
`PrioritizationWeights` (§6) stays overridable rather than hardcoded
specifically so a later classification/prioritization objective can
resolve them without touching this layer.

If `GSUhub_Development_Plan.md` turns up later and disagrees with a
decision below, that document should win.

## 1. Toolchain

Three pieces of toolchain were missing on this machine and were installed
over the course of this and the prior session, all before writing or
verifying any code:

- **Flutter 3.47.4 (stable) / Dart 3.13.3** → `C:\flutter`, added to user
  `PATH`. Analytics disabled, web support enabled.
- **Git 2.55.0** → `C:\Program Files\Git`. Required by Flutter's own
  tooling (`dart format`, `flutter --version` etc. shell out to git
  internally on Windows) — without it, even `dart format .` fails.
- **Eclipse Temurin JDK 17**, **Android SDK cmdline-tools**,
  **platform-tools**, **platforms;android-35**, and
  **build-tools;35.0.0** → `C:\Android\sdk`, `ANDROID_HOME` /
  `ANDROID_SDK_ROOT` set, `flutter config --android-sdk` pointed at it.
  The machine's only pre-existing Java was an Oracle **JRE 8**, too old
  for a modern Android Gradle Plugin build (JDK 17 is required).

  **Worth flagging for the rest of the team:** the *current* Android SDK
  cmdline-tools release (revision 16111833) ships a new "Android CLI"
  (`android.exe`) that replaces `sdkmanager` — and on this machine it
  reliably **crashes with a native stack-buffer-overrun** (exit code
  `-1073740791`) on any operation touching the `platforms` package
  category, whether invoked directly or via the `sdkmanager.bat`
  compatibility shim. `platform-tools` alone installs fine through it;
  `platforms;android-35` does not. The workaround was to download an
  **older cmdline-tools release (revision 11076708)** side-by-side and
  use its classic, Java-based `sdkmanager.bat` for the platform and
  build-tools install — that one worked without issue. If a teammate's
  `flutter build apk` mysteriously can't find an Android platform after
  what looks like a successful `sdkmanager` run, this is why: check
  whether their `sdkmanager` silently crashed after printing partial
  output. The old cmdline-tools zip does **not** need to stay installed
  permanently — the platform/build-tools it wrote into `C:\Android\sdk`
  are what matter; the tool that wrote them is disposable.

- **Chrome is not installed**; **Edge** substitutes for web verification
  (`flutter run -d edge`) — both Chromium-based, and `flutter create`
  doesn't depend on either being present to generate the `web/` folder.

Project scaffolded via `flutter create --platforms=android,web` — no iOS
or desktop platform folders, per manuscript §3.2 ("Android 8.0 and above
... accessible through standard web browsers").

## 2. Three shells, one router, one backend

One Flutter project (`gsuhub`) serves all three roles. Within it, routing
is **one `GoRouter` instance, path-prefixed** (`/admin/*`, `/staff/*`,
`/personnel/*`) rather than three separate entry points with independent
routers (e.g. `main_admin.dart` / `main_staff.dart` /
`main_personnel.dart`, built via `flutter run --target=...`).

This was an explicit choice between two real options, not a default:

- **Chosen — one router, path-prefixed:** simplest to scaffold and test
  now; all three shells' routes exist in one binary, and role-based
  access (built in 2.A) restricts which prefix a signed-in user can
  reach at runtime rather than at build time.
- **Rejected — separate entry points per shell:** would keep the admin
  web build from bundling mobile-only shell code and vice versa, at the
  cost of three build targets and three router configs to keep in sync
  this early in the project. Worth revisiting if bundle size or build
  separation becomes a real problem later — nothing about the current
  structure prevents splitting `app_router.dart`'s three sections into
  separate files/routers if that becomes necessary.

Each shell (`lib/shells/admin/admin_shell.dart`,
`lib/shells/requestor/requestor_shell.dart`,
`lib/shells/personnel/personnel_shell.dart`) is currently just
`Widget build(context) => child;` — a `ShellRoute` outlet with no layout,
no nav chrome. Real layout is 2.A (admin) and the corresponding mobile
objectives (3.x, 5.x).

## 3. The Shared Backend Contract

This is the rule set that makes the three shells cohere into one system
instead of three unrelated apps that happen to share a repo. It is
enforced by structure now and must be enforced by review discipline
later, since Dart has no way to make "don't import this package here"
a compile error project-wide.

1. **No shell talks to Firebase directly.** All Firebase access goes
   through `lib/core/services/` — see §4. A shell (or a `features/`
   module) that imports `cloud_firestore`, `firebase_auth`,
   `firebase_storage`, or `firebase_messaging` is a bug, full stop.
2. **`lib/core/` is platform-agnostic.** Nothing under it may import
   anything web-only or mobile-only (`dart:io`, `dart:html`, a
   file-picker plugin, etc.). The service *interfaces* in
   `core/services/` reflect this: `StorageService.uploadFile` takes raw
   `Uint8List` bytes rather than a platform-specific file type, precisely
   so it stays callable from both the web and mobile shells.
3. **Collection path strings live in exactly one file** —
   `lib/core/constants/firestore_paths.dart`. No collection name should
   ever appear as a string literal anywhere else in the codebase.
4. **One shared lifecycle enum.** All three shells and every feature
   import the same `ReportStatus` (and `WorkOrderStatus`, `PriorityLevel`,
   `UserRole`) from `lib/core/enums/`. Never a shell-local copy, never a
   raw string standing in for a status.
5. **Shells own presentation only.** No business logic — classification,
   scoring, duplicate detection, inventory deduction, whatever — belongs
   in `shells/`. That logic lives in `lib/features/<name>/` and is called
   through the service interfaces.

A PR that violates any of these is a PR to send back for rework, not a
style nitpick — see the checklist in
`.github/pull_request_template.md`.

## 4. Service layer: abstract interfaces only

`lib/core/services/` defines four `abstract interface class`es —
`AuthService`, `FirestoreService`, `StorageService`,
`NotificationService` — with **zero implementations**. This is the
explicit line this objective was told not to cross: 1.A defines the
*contract*, concrete `Firebase*Service` implementations that actually
call Firebase are Objective 1.C's job, once 1.C has configured the actual
Firebase project to call.

Two of these interfaces needed a minimal supporting type to be
expressible at all, and both were kept deliberately thin to avoid
crossing into 1.B (data model) territory:

- `AuthService` introduces `AuthUser` (uid, email, role) — the identity
  subset routing/RBAC needs, **not** the full `users/{uid}` profile
  document. The full user model belongs to 1.B.
- `FirestoreService` is generic and collection-path-based
  (`getDocument<T>({collectionPath, documentId, fromMap})` etc.) rather
  than typed per entity, so it never needs to know what a
  `damage_reports` document looks like. `NotificationService.onMessage`
  similarly returns a loose `Map<String, dynamic>` payload rather than a
  typed notification model.

If a future edit to any of these four files ends up naming a Firestore
*field* (as opposed to a collection path) or hardcoding a concrete entity
type, that edit has drifted into 1.B and should be reconsidered.

## 5. Routing and the guard stub

`route_paths.dart` holds path constants for all three shells, each
annotated with the WBS sub-objective that owns its real screen (2.A/B/C,
3.A/B/C, 5.A/B/C). `route_guards.dart`'s `AppRouteGuard` is wired into
`GoRouter.redirect` as a single chokepoint across all three shells, but
always returns `null` — no enforcement yet. It's a class (not a bare
function) specifically so 2.A can inject an `AuthService` into it without
changing `app_router.dart`'s call site.

The root path `/` redirects to `/admin/dashboard` as a placeholder
default — arbitrary, and called out as such in the code comment. Once
2.A implements auth, root should redirect based on the signed-in user's
`UserRole` instead of always landing on the admin shell.

## 6. Config layer and the two known blockers (carried forward)

`AppConfig` holds a `PrioritizationWeights` value object defaulting to
manuscript Table 3.2 (Severity 0.40 / Safety Risk 0.30 / Frequency 0.20 /
Location Importance 0.10). `PriorityLevel` (the enum) only encodes the
**score-to-level thresholds** from Table 3.5, which the manuscript states
as fixed; the **weights** are configuration, overridable once a later
objective resolves:

- a conflicting statement elsewhere about what the weight values should
  be, and
- no stated source for who assigns the 1-4 criterion ratings that feed
  the formula, or when.

`Env` distinguishes development/production via `dart.vm.product` (set
automatically by the build tooling) plus an optional
`--dart-define=IS_PRODUCTION` override.

## 6b. Firebase wiring (Objective 1.C)

The Firebase project `gsuhub-dorsu` is live (Spark plan, `asia-southeast1`).
Details and the console checklist are in `docs/firebase_setup.md`; the
local workflow is in `docs/emulator_setup.md`. Decisions worth recording:

**Startup is a sealed result, not an exception.**
`FirebaseInitializer.initialize` never throws; it returns success (with
the four Firebase handles) or failure (with a summary and technical
detail). `main.dart` switches on it and renders `StartupErrorScreen`
rather than letting an exception escape `main`, which in Flutter means a
white screen and a cause the user cannot see.

**Emulator mode is the debug default, and visible.** 1.C first made it
opt-in, on the reasoning that a developer who forgot to start the
emulators should see diagnosable errors. That traded the wrong risk:
`gsuhub-dorsu` is the only project the team demos from, and an opt-in flag
meant a forgotten one wrote test records into it. Development builds now
use the emulators unless `--dart-define=USE_LIVE_FIREBASE=true` is passed;
release builds use the live project unless `USE_EMULATOR=true` forces the
emulators, and both flags together refuse to start. The orange EMULATOR
banner still marks the mode, and a debug build on the live project prints
a warning at startup.

**One choke point for errors.** `FirebaseCallGuard` applies timeout,
retry-on-transient-only, and `FirebaseErrorMapper` translation to every
call. A single method that forgot its own try/catch would leak Firebase
types past the service boundary and break the Shared Backend Contract; the
guard makes that impossible rather than merely discouraged. Retries are
restricted to transient codes — retrying `permission-denied` only delays
the error the user needs to see.

**`FirestoreServiceImpl.raw` is a deliberate seam.** Repositories need
Firestore's query builder and transactions; reinventing those behind the
generic interface would be a large, leaky abstraction that still could not
express everything. The raw handle is exposed to repositories only, which
keeps the boundary where it matters — shells and features talk to
repositories, never to Firestore.

**Invariants are enforced in transactions, not just documented.** 1.B
specified three; 1.C implements them:
- Accomplishment submission writes the report and all its `consumption`
  ledger entries atomically, validating every stock level before writing
  anything.
- `recordTransaction` computes the new balance from the value read *inside*
  the transaction, never from the caller's figure.
- Tool borrow/return flips status, holder and loan record together.
- `WorkOrderRepository.setStatus` re-reads the current status and rejects
  transitions the enum's table disallows, rather than trusting the caller.
- `TaskRepository.setStatus` adjusts `users.activeTaskCount` in the same
  transaction, using `FieldValue.increment` so concurrent assignments
  cannot lose a count.

**Android `minSdk` is pinned to 26**, not tracked from
`flutter.minSdkVersion`. The manuscript promises Android 8.0+ (§1.5,
§3.4); letting Flutter's rising default silently drop that would
contradict the approved scope.

**No project-specific values are committed.** The VAPID key, emulator
host/ports and environment flag all arrive via `--dart-define`. The web
service worker cannot read those, so `web/index.html` hands it the config
at runtime via `postMessage` rather than hardcoding a project id into a
committed JavaScript file.

**Rules tests are tagged `emulator` and excluded from `flutter test`.** A
suite that fails whenever an external service is not running trains people
to ignore red suites. They run deliberately against a seeded emulator.

## 7. Firebase: package set (updated in 1.C)

All five Firebase packages are now dependencies: `firebase_core` (1.A),
`cloud_firestore` (1.B, for `DocumentSnapshot`/`GeoPoint`/`Timestamp`
types), and `firebase_auth`, `firebase_storage`, `firebase_messaging`
(1.C, when their services were implemented). Each was added at the point
it was actually used rather than up front.

Credentials live in `lib/firebase_options.dart`, generated by
`flutterfire configure` at **its own default path** — 1.A had placed a
placeholder at `lib/core/config/firebase_options.dart`, which meant a
re-run of `flutterfire configure` would write a second, diverging copy.
The generated file is now the single source of truth and is gitignored,
alongside `android/app/google-services.json`. `lib/firebase_options.example.dart`
documents the shape.

Consequence worth stating plainly: **a fresh clone does not compile until
`flutterfire configure` has been run**, because `main.dart` imports the
generated file. That is the accepted trade against committing project
credentials, and it is called out at the top of `docs/firebase_setup.md`.

## 8. Report / work-order lifecycle: assumptions beyond the manuscript (carried forward)

`ReportStatus` and `WorkOrderStatus` encode explicit transition tables so
illegal jumps are compile-time-adjacent mistakes to catch, not just a
convention to remember. Two choices are **assumptions, not manuscript
facts**:

1. `ReportStatus.underReview` branches to `merged` / `rejected` /
   `archived` — taken from the duplicate-report handling options in
   manuscript §3.4 ("merge, dismiss, or retain").
2. Both `ReportStatus.forReview` and `WorkOrderStatus.forReview` allow a
   transition back to `inProgress` — a rework loop for an incomplete
   accomplishment report. The manuscript never states whether rework is
   possible. **Flagged for confirmation.**

`PriorityLevel.fromScore` thresholds are copied verbatim from manuscript
Table 3.5.

## 9. Firestore collections and indexes (carried forward)

The fifteen collection names in `firestore_paths.dart` (`users`,
`facilities`, `assets`, `damage_reports`, `work_orders`, `tasks`,
`accomplishment_reports`, `inventory_items`, `inventory_transactions`,
`tools`, `tool_loans`, `feedback`, `notifications`, `audit_logs`,
`config`) were derived from entities the manuscript explicitly describes.
**Not sourced from the missing development plan** — a one-file rename if
that document says otherwise.

`firestore.indexes.json` is intentionally **empty array**, and
`firestore.rules` / `storage.rules` are **deny-all** baselines. Real
schemas, indexes, and populated rules are Objective 1.B/1.C's job — this
objective defines *names and vocabulary* (collection path strings, status
enums, abstract service interfaces), not *structure* (field names,
document models, indexes, rules content). Writing a field name anywhere
in this codebase right now would mean this objective had crossed into
1.B; it hasn't.

## 10. UI: strictly no design decisions (carried forward)

Every route resolves to one shared `RoutePlaceholderScreen` (`Scaffold` +
centered route-name `Text`). `app_colors.dart` / `app_text_styles.dart`
hold Material-default placeholders with `// TODO: pending design
confirmation` — manuscript §3.5's figures are duplicated/mislabeled and
are being resolved separately.

## 11. Lints (carried forward)

`analysis_options.yaml` extends `package:flutter_lints/flutter.yaml` with
stricter analyzer settings (`strict-casts`, `strict-inference`,
`strict-raw-types`) plus rules for resource leaks, unnecessary
allocations, and import hygiene. Not a manuscript requirement — a
reasonable strict baseline for a 3-developer team.

## 12. Version control

`git init` was run against the existing scaffold (previously untracked
across two work sessions). Branch/commit conventions are in
`docs/git_workflow.md`; the PR checklist in
`.github/pull_request_template.md` directly enforces §3's five rules
(specifically: no direct Firebase imports in shells, no stray collection
name literals) so a violation gets caught at review time, not discovered
three features later.

## 13. Objective 2.C: accounts, analytics, export

**Creating accounts without a server.** The project is on the Spark plan,
so there are no Cloud Functions to call the Admin SDK from. Creating a
user with the client SDK signs that user in, which on the default app
would sign the administrator out. `FirebaseAccountProvisioningService`
creates the sign-in on a second, separately named Firebase app, writes the
`users` profile through the repository, and signs the second app out
again. The password is 32 random characters that nobody sees; the person
is emailed a link to set their own. If the profile write fails the new
sign-in is deleted, so no login is ever left without a profile. The
service sits beside `AuthService` rather than inside it: `AuthService` is
about the signed-in user and was not to be modified.

**No self-lockout.** An administrator cannot change their own role or
deactivate their own account. The repository refuses both inside the
transaction, and the security rules refuse them too, so a client that
skipped the repository is still stopped. A role change is also refused
for someone holding active work orders, which would otherwise be
stranded. Deactivation of such a person is allowed with a warning: someone
who has left must be deactivatable, and there is no reassignment screen
yet.

**Every account change is audited** (`created`, `updated`,
`statusChanged`) in the same transaction as the change, as 2.B's report
and work-order moves are.

**Staff status is derived.** "Busy" is read from `activeTaskCount`, which
2.B's assignment transactions maintain, not from the stored
`availability` field, which nothing kept in step with the work. Leave is
the one status work cannot reveal, so it alone is set by hand.

**Analytics is computed, not stored.** Every figure comes from the live
report and work-order feeds, for the same reason as 2.B: at one campus's
volume that is a few hundred documents, and nothing can drift from the
tables elsewhere. Each metric's definition is in
`AnalyticsSummary` and shown as its card's tooltip. Comparisons are
against the period of equal length before the selected one; the
PENDING / OVERDUE count at the start of a period is recovered from
`reviewedAt` and the work orders' dates, without a history table.

**Export is CSV.** It opens in Excel on any GSU machine and needs no new
dependency. A field starting with `=`, `+`, `-` or `@` is prefixed with an
apostrophe: report titles are typed by requestors, and unguarded they
would run as formulas when an administrator opened the file. The file
carries a UTF-8 byte-order mark so accented names survive in Excel.

**Riverpod pauses unlistened providers.** A stream provider nobody is
listening to is paused, and a bare `ref.read(provider.future)` on it then
waits forever — the cause of 2.B's `authStateProvider` finding. The export
runs from any page's top bar, so it listens to each feed while it waits.

**Design sources.** Personnel is built from node `200:4316` (manuscript
Figure 17) with full design context. Analytics is node `61:5086`; the
Figma MCP Starter plan's monthly quota ran out partway, so its KPI row
and first chart row use full context, while the second chart row, the
issues table and the range control were built from the file metadata's
exact geometry with colours sampled from the rendered frame. User
Accounts is node `89:4626`, content only: the one other User Accounts
frame, `61:5666`, contains "DOrSUMaintain" and is excluded by standing
instruction. The designs' photos, bulk-select checkboxes and chart menus
are left out because no data or action stands behind them.

## 14. Objective 3.C: the damage report form

**Numbering.** 1.A labelled the requestor routes 3.A/3.B/3.C by guess; the
WBS numbers report submission 3.C. There is no faculty and staff sign-in
yet (3.A), so a debug-only `DevSignInScreen` at `/staff/login` stands in —
emulator only, no credentials in the code. Off the web the app opens on
the requestor area, and the report form is the requestor's home until a
home screen exists. The guard now keeps other roles out of `/staff/*`,
because the rules accept reports from requestors only.

**Photos go up before the report exists.** `newReportId()` reserves an id
without writing; each photo uploads to `damage_reports/{id}/`, and the
report is then filed naming them. Photos are scaled to 1920px at JPEG
quality 80 on the device (a few hundred KB, well under the rules' 10 MB).
A file name is unique per attempt, because Storage rules refuse
overwriting and an upload can land and still fail on the way back.

**Filing is a transaction that reads first.** The call guard retries a
write that times out, and a timed-out write may already be on the server;
its retry would be an update, which requestors may not make. Reading the
id first turns that retry into a no-op, so a report can never be filed
twice. A transaction also needs the server, so the form never says
"submitted" about a write only queued on the phone. The audit entry goes
in the same transaction (§3.4 names report submissions). The rules let a
requestor `get` a missing report id for this read; a missing random id
discloses nothing.

**A security fix carried from 1.B.** The requestor `list` rule checked
the page size and nothing else, so any requestor could query every
report. It now requires `reporterId == request.auth.uid`. The create
rule also validates the submission's shape and refuses pre-set review
fields; classification and scoring fields are left to Objective 4, whose
keyword classifier may run on the submitting device.

**DAMAGE TYPE is a suggestion.** The design lets the requestor pick a
type; the manuscript has the classifier or an Administrator set the
category. The pick is stored as `requestorCategory`, beside `category`,
the way `requestorPriority` sits beside `officialPriority`, and the
admin report detail shows it as "Suggested by requestor".

**Geo-tag and map.** The tag is optional (§2.2). The map is
OpenStreetMap through `flutter_map`: no key and no billing, which the
Spark plan and the no-secrets rule need; the tile policy's User-Agent
and attribution are both met. "Tap to adjust location on map" opens a
full-screen picker, because indoors a GPS fix can be tens of metres out.

**QR lookup.** A code is tried as a facility, then as an asset whose
facility is then read; retired ones are refused. The design has no scan
button — its header button is the bell — so a scan icon sits at the
right end of the title row, by Chris's decision.

**Design source.** Figma `165:137` with full design context. Additions
where the design is silent, plain Material and listed in the 3.C report:
the scan button, the camera-or-gallery sheet, the scanner and pin-picker
screens, validation messages (a light red on navy and a dark red on gold,
since the console's red is unreadable on both), the AUTO-CAPTURE off
state, upload progress in the Submit button, and the confirmation.

## 15. Objective 3.A: faculty and staff sign-in, home and My Reports

**Scope.** Chris's 3.A brief bundles the report form with sign-in, the
home screen, My Reports and the bottom bar. The form is 3.C, already
built and merged, so 3.A builds only the rest and opens the 3.C form
from the new screens unchanged.

**One sign-in path.** `AuthService` gains `register()`, beside sign-in,
so faculty sign-up goes through the same service as everyone else. It
creates the Firebase account, runs a callback that writes the `users`
profile, and deletes the account again if the profile cannot be saved
(the pattern 2.C's provisioning uses). It leaves nobody signed in. The
create call is not retried — `FirebaseCallGuard.callOnce()` — because a
retry after a timeout would fail as "email already in use" and hide that
the account exists. The emulator-only `DevSignInScreen` is gone.

**Sign-up asks; an administrator lets in.** §1.5 limits GSUhub to
authorized faculty and staff, so a sign-up is a request.
`AccountStatus` gains `pending`: kept apart from `inactive` so an
administrator can tell a new request from someone who left, and so the
person is told "waiting for approval" rather than "deactivated". The
service refuses a pending account at sign-in with that message, given
only after the password checks out. Any valid address may sign up
(Chris's decision); approval is the gate. Passwords need eight
characters.

**The self-registration rule.** `users` creation was administrator-only.
A person may now create their own document, and only as: a requestor,
`pending`, under the email in their sign-in token, with none of the
personnel fields, a known set of keys, and server timestamps (a device
clock cannot back-date a request). The client lower-cases the address
so it matches the token. No audit entry: the rules let only active
accounts write the trail, and the administrator's approval is what is
recorded ("Approved the account request of …").

**Approval lives in 2.C's User Accounts.** The brief assumed activation
would wait for 2.C; 2.C already shipped Activate and Deactivate. A
pending row reads PENDING in amber, sorts to the top, and its menu
offers Approve and Decline (decline leaves the account `inactive`).

**Reads, not listeners.** Home and My Reports share one read of the
requestor's reports (`getByReporter`, newest first, 100 at most); live
updates are 3.B's. Pull down to read again; filing a report refreshes
it. `watchByReporter` had no limit since 1.B, which the list rule
refuses for a requestor; both queries now carry the limit the rule
allows.

**Three stages.** `ReportStatus.progress` collapses the eleven statuses
into Pending, In Progress, Completed, plus Closed (merged, rejected,
archived). The faculty app's chips, filters and counts read it, and the
admin chip palette now does too, unchanged. The home banner counts the
three stages and leaves Closed out.

**Navigation.** A `ShellRoute` holds Home, Reports, Alerts and Profile
under the header and the floating bar. The report form opens over it
with `push` (its frame has no bar), so Back returns where it came from,
and filing a report pops back and refreshes. Tabs switch with `go`; the
device's Back on a tab other than Home returns Home rather than closing
the app. A report's detail page sits under Reports.

**Design source.** Figma's MCP quota was spent, so the screens were
built from Chris's 1x PNG exports of `193:310`, `194:455`, `170:2050`
and `169:1251` (the last is My Reports, not in the brief's table), with
positions and text from the saved file metadata and colours sampled
from the PNGs. Not yet checked against the file: exact colours, font
families (Public Sans on the sign-in pages, Poppins on the rest, both
assumptions) and the icons (Material stand-ins; the SVGs were too large
to send). The banner's campus photo (`image 9`) has not been exported,
so the banner shows its navy-to-purple wash alone.

**Decisions where the design disagreed with itself or was silent.**
Status colours differ between the home screen and My Reports; Chris
chose the home screen's yellow, blue and green for both. The My Reports
frame highlights Home in the bar; the current tab is highlighted. The
home rows' coloured rules follow each report's stage. The grey squares
show the report's first photo. The greeting's second line shows the
department, or "Faculty & Staff" — accounts do not record faculty versus
staff. "Username" is relabelled Email, as on 2.A's login, and there is
no forgot-password link because the design has none. Unselected My
Reports filters are neutral, as yellow text is unreadable there. Plain
additions: field validation, the sign-in notices, the report detail
page, and the Alerts and Profile placeholders (Profile holds Sign out).

## 16. Objective 3.B: live tracking, the status timeline and notifications

**Live, not read once.** Home, My Reports and a report's detail page now
listen (`watchByReporter`, `watchById`, `watchStatusHistory`) where 3.A
read once; `getByReporter` and pull-to-refresh are gone. The providers
are `autoDispose`, so a listener closes with the last screen using it,
and they switch to an empty list on sign-out before the rules would
refuse them. A strip under the header says when the app is offline; the
last loaded data stays on screen. Not in the design.

**Status history is a subcollection.** 1.B recorded moves only in
`audit_logs`, which requestors cannot read, and a work order's moves were
logged against the work order, not its reports. Approved with the plan:
`damage_reports/{id}/status_history`, one entry per move — status, server
time, who, and a note (a rejection's reason) or the assigned person's
name and trade, which the detail page's staff card needs because a
requestor cannot read `users` or `work_orders`. A list on the report was
ruled out: Firestore cannot put server timestamps inside an array.

Every move writes its entry in the same transaction as the status, so
the timeline cannot disagree with the report. That touched filing (3.C),
`transitionStatus` and assignment (2.B), the work-order status change
(2.B), and `mergeDuplicates` (1.B, unused by any screen yet), which
became a transaction so each duplicate can be read for its reporter.
The rules make entries append-only: an administrator writes any, a
requestor only the first `submitted` entry while filing that report, and
personnel only on a report with a work order (Objective 5's need). Old
reports with no history still show their filing and current status, from
`submittedAt` and `updatedAt`.

**The timeline's words.** `ReportStatus.timelineLabel` is the single
source: Report received, Under review, Approved, Personnel assigned, Work
started, Work done, being checked, Completed, Closed, Not accepted,
Merged with an existing report, Archived.

**Official versus suggested.** The detail page shows GSU's priority only
once `officialPriority` is set, and "AWAITING REVIEW" until then — never
the requestor's urgency in its place. A damage type counts as GSU's only
once the report has been reviewed and approved (or set by hand), so the
keyword classifier's guess is not shown as a decision; Home and My
Reports use the same rule. Ended reports (rejected, merged, archived)
show a note card with the reason in place of the progress steps.

**Notifications without Cloud Functions.** 1.B left notifications to
server code, and the rules refused every client write. The project is on
the Spark plan, which has none, so the client that moves a report writes
the reporter's notification in the same transaction (`stageReportMove`
writes the history entry and the notice together, so no caller can do
one without the other). The rules hold each notice to the report's own
reporter, checked with `getAfter` against the report as the transaction
leaves it: an administrator may notify any report's reporter; a
requestor only themselves, with "Report received", while filing that
report; personnel only on a report with a work order. A recipient may
only mark their own notice read, at server time, and not unread again.

Notified moves: received, approved, assigned, work started (or resumed
after a send-back), completed (with a prompt to rate), rejected (with the
reason) and merged (naming the report it joined). Review, sign-off,
closing and archiving appear on the timeline only. The wording lives in
`ReportNotice.forMove`, which the seed script also uses.

**What Spark can and cannot do.** Without a server nothing can *push* to
a phone: sending an FCM message needs a server credential, and shipping
one inside the app would let anyone who unpacks the APK message every
user. So, on Spark:

- the Alerts list and its badge update live, from Firestore;
- while GSUhub is running — open, or in the background for as long as
  Android keeps it alive — `PushCoordinator` raises a system notification
  itself for each new notice;
- the push token is saved on sign-in, kept current when it rotates, and
  cleared and deleted on sign-out, so the next account on the phone never
  receives the last one's;
- a push that does arrive (sent from the Firebase console today, or a
  Cloud Function later) is shown in the foreground and opens its report
  when tapped, from foreground, background or a cold start.

A phone whose GSUhub has been closed hears nothing until it is opened.
Guaranteed delivery to a closed app needs the Blaze plan and a Cloud
Function that sends to `users/{uid}.fcmToken` when a notice is written.
Nothing in the app changes for that: the notices and tokens are already
there.

**Permission.** Android 13+ asks at run time. The app asks once per
sign-in while Android will still show the prompt; refused, the Alerts tab
offers Allow, and refused for good, Open settings. In-app notifications
never depend on it. `permission_handler` is pinned to 12.0.1: 13.x needs
compile SDK 37, which the build machine does not have.
`flutter_local_notifications` needs core-library desugaring, now enabled.
Neither needs more than API 24, below the project's pinned 26. One Android channel,
`report_updates`, is also FCM's default, so pushes and the app's own
notices land together.

**Alerts.** Built from Chris's PNG of `169:1459`: Today and Earlier,
unread notices pale gold with a gold edge, read ones white. Tapping one
marks it read and opens its report; the header's bell opens the tab; the
Alerts tab carries the live unread count. Not in the design: Mark all as
read, the empty state, the permission card, and the times ("2 minutes
ago" through today, the date after).

**Design source.** The one Figma call allowed for 3.B (`169:1355`) was
refused — the Starter quota was still spent — and not retried. Both
screens were built from Chris's 1x PNG exports (`Group 28.png`,
`Group 29.png` in `Desktop\Mobile app SS`), with colours sampled from the
pixels and positions from the saved file metadata. Fonts and icons are
assumptions: Public Sans, as on the 3.C form the frame matches, and
Material icons. The design draws a work order ("Work Order Details",
"WO-2023-0892", "Linked Report"); until a report is assigned the page is
the report's own, and from assignment on it reads as drawn. The staff
card shows initials and the person's trade: accounts have no photo and
no job title. The design's written updates ("Spare parts ordered",
"ADMIN FOLLOW-UP") have no source in GSUhub yet, so the timeline shows
status changes only. "Rate this Service" shows on completed reports and
says rating arrives with 3.C.
