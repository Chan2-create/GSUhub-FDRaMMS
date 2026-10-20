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

Both were resolved by Chris for Objective 4.B (see §18): the formula's
weights, and the administrator rates in review.

`Env` distinguishes development/production via `dart.vm.product` (set
automatically by the build tooling) plus an optional
`--dart-define=IS_PRODUCTION` override.

## 6b. Firebase wiring (Objective 1.C)

> Since Objective 1 the data is in Supabase (§21). The start-up result,
> the emulator default and the call guard below still hold, for Auth;
> the transactions moved into database functions.

The Firebase project `gsuhub-dorsu` is live (Spark plan, `asia-southeast1`).
Details and the console checklist are in `docs/firebase_setup.md`; the
local workflow is in `docs/local_setup.md`. Decisions worth recording:

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

> Since Objective 1, `firebase_storage` is gone (photos are in
> Supabase Storage) and `cloud_firestore` stays for its types only (§21).

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
   manuscript §3.4 ("merge, dismiss, or retain"). Since 4.C a
   `submitted` report may also go straight to `merged`: a duplicate is
   often spotted the moment it arrives (see §18).
2. Both `ReportStatus.forReview` and `WorkOrderStatus.forReview` allow a
   transition back to `inProgress` — a rework loop for an incomplete
   accomplishment report. The manuscript never states whether rework is
   possible. **Flagged for confirmation.**

`PriorityLevel.fromScore` thresholds are copied verbatim from manuscript
Table 3.5.

## 9. Firestore collections and indexes (carried forward)

> Since Objective 1 these are Postgres tables (§21,
> docs/data_dictionary.md).

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
opens the Ratings screen (§17).

## 17. Objective 3.C: post-service feedback and rating

**Numbering.** The prompt briefs number feedback and rating 3.C; the
report form built earlier under "3.C" is the same objective's submission
step, already merged. No brief was written for this one, so it was built
from the manuscript (§1.5, §1.7, §3.4 requestor capabilities), the 1.B
`feedback` model, and Chris's export of the Ratings frame (Figma
`169:1797`, `Mobile app SS/Group 32.png`).

**Three ratings, as the manuscript asks.** §1.5 and §1.7 rate the service
on response time, service quality and overall satisfaction, and 1.B
stores the three separately. The frame draws one star row. Chris chose
three rows in the drawn style; submitting waits for all three, since
none can be guessed from the others. The word under each row is Chris's
scale: Poor, Fair, Good, Very Good, Excellent (the frame shows "Very
Good" at four). Comments are optional, up to 1,000 characters.

**One rating per report, filed under the report's id.** `feedback/{id}`
uses the report's id, so "has this been rated?" is one document read —
which a requestor may make before the document exists (`resource ==
null`, as for report ids in 3.C) — and a second rating is an update the
rules refuse. 1.B's `submit` checked for an earlier rating with a list
query only administrators may run; `FeedbackRepository.rate` replaces it.

**Rating closes the report.** The lifecycle ends "completion, and
feedback evaluation" (§1.7), and nothing in the console moves a report
to `closed`. Chris chose: rating it closes it. `rate` runs one
transaction — the rating, the report's move from `completed` to
`closed`, its timeline entry, and an audit entry — and is idempotent
like `submit`. Skip leaves the report completed; the detail page keeps
offering "Rate this Service", and shows the rating once given. Closing
sends no notification: the requestor just did it.

**Rules.** A requestor gets exactly one new write on a report: their own,
from `completed` to `closed`, status and `updatedAt` only, and only in
the write that creates its rating. The rating must be theirs, under the
report's id and its work order, three integers 1–5, a known set of keys
and server time, and only as the report closes. They may also write the
`closed` timeline entry in that write. Personnel still cannot read
feedback (§1.5).

**Seed.** Every closed report in the six-month history now has a rating,
and its `closed` step is the requestor's. `rep-0005` stays completed and
unrated, with its "Work completed … rate the service" notice, to try the
flow on.

**Design notes.** Colours were sampled from the export; the type is
Public Sans like the detail frame. The job card shows the work order,
the date the work was completed, the building, "room • confirmed type",
and the assigned person with their trade — initials in place of the
photo, as on the detail page. Plain additions: the hint under an
unrated row, "Rate all three to submit", the error line, the read-only
view of a rating already given, and a note when the report is not yet
completed (a stale link).

## 18. Objectives 4.A–4.C: classification, priority scoring, review and duplicates

**Scope and sources.** Chris's development plan: 4.A the keyword
classification engine, 4.B the weighted priority score, 4.C confirming
or modifying the official priority level ("before work-order
assignment", §1.5). Built from manuscript §1.5, §3.4 and Tables 3.2–3.5,
and four decisions Chris made on 2026-10-12, noted below. No Figma frame
exists for any of it; the screens are built from the console's existing
components. The engines are pure Dart in
`features/classification/domain/`: `KeywordClassifier`,
`PriorityScorer`, `DuplicateDetector`.

**4.A: classification runs on the filing phone.** There are no Cloud
Functions on the Spark plan, so the faculty app classifies a report as
it is filed and stores the damage type with `classifiedAutomatically:
true`. The rules accept a category from a requestor only when it is a
known one and marked automatic. When no keyword matches, two types tie,
or the dictionary cannot be read, the report is filed unclassified and
an administrator classifies it (§3.4). Matching is **DERIVED**: a
keyword's words in order, case ignored, punctuation as spaces, each word
allowed a longer ending, in the title and description both; the type
with the most keywords found wins. The requestor's own DAMAGE TYPE
(3.C) stays a suggestion beside it.

**4.A: the keyword editor is on the Settings page (Chris).** The
console's Settings item, disabled until now, opens a page with the
classification keywords per damage type: add, remove, discard, save. A
"Try a description" box classifies typed text with the unsaved list. A
keyword is 3–60 characters, needs a letter or digit, and belongs to one
type only, compared the way the classifier compares. Saving writes the
administrator's uid and the time; the new list classifies reports filed
afterwards and changes no filed report. With no saved document, the
manuscript's Table 3.3 list is in use and the page says it is not saved
yet. The same fallback applies to all three `config/*` documents, so a
live project works before anyone saves them; any other read failure is
shown as one.

**4.B: the formula's weights (Chris).** The §3.4 formula (0.40 / 0.30 /
0.20 / 0.10) over Table 3.2 (3 / 4 / 2 / 3); **Table 3.2 in the
manuscript needs correcting to match.** Score = Σ weight × rating ÷ Σ
weight, so another scheme would stay on Table 3.5's 1.00–4.00 scale,
rounded to two decimals before banding (2.5000000000000004 is 2.50,
High, as on paper).

**4.B: the administrator rates all four, in review (Chris).** On the
report page, with the score and recommended level updating as they rate.
Frequency is pre-filled from how many reports of the same damage type
were filed at the same facility in the last 30 days, this one included:
2, 3 and 5 reports suggest Moderate, High and Very High (**DERIVED**,
held in `config/prioritization`). It counts every report filed, merged
duplicates and rejected reports included. The count is one aggregate
query on the existing (facility, category, submitted) index.

**4.C: the official priority is set before assignment.** The review
panel shows the keywords found, the requestor's suggestion and urgency,
the four ratings with their weights and §3.4 meanings, the score with
its formula and bands, and the official level. That level follows the
recommendation until the administrator picks another; a different level
is saved as their change, and the audit entry says so ("official
priority CRITICAL, raised from the recommended HIGH (score 3.10)"). The
type, ratings, score and both levels are saved in one transaction with
the audit entry, and may be revised until a work order is raised; after
that the panel is gone and the summary card remains. Assignment now
refuses a report without a confirmed official priority, and the work
order takes the official priority. In the Task Assignment queue, such a
report's button reads "Review type and priority" and opens its page.

**4.C: duplicate detection (added by Chris).** Two reports are flagged
when both are open and unmerged, an administrator has not kept them
separate, they are at the same place (the same facility, or the same
stated location), they were filed within 72 hours of each other, and
they share a damage type — or their wording is at least half alike and
shares at least two key words. This combination of §3.4's five factors
is **DERIVED**. Wording is the share of the shorter text's key words the
other uses. Common words, words under three letters and each report's
own location words are left out, so "Room 101" in two descriptions does
not make two jobs in that room alike. The flags are computed in the
console over the reports it already holds, with no extra reads: a mark
in the reports table, and a Possible duplicates card on the report page.
**Merge**, confirmed in a dialog, closes the report still awaiting
review as a duplicate of the other (the later one, when both are); its
requestor is told, as in 2.B, and the parent's work order carries the
job. **Keep separate** records the ruling on both reports
(`dismissedDuplicateIds`), so the pair is not flagged again. A merge is
refused unless the duplicate is awaiting review with no work order and
the parent is open and not itself merged.

**`submitted → merged`.** A duplicate is often spotted on arrival, but
the rules require every timeline entry to match the report's final
status, so one transaction cannot write "under review" and then
"merged". The lifecycle allows the direct move instead.

**Accessibility fix found while testing (outside 4.A–4.C).** Each
page's route draws a modal barrier, and a barrier drops from the
semantics tree everything painted before it in the same container. In
the console that was the whole sidebar and top bar; in the faculty app,
the header and offline banner. Screen readers could not reach them. The
page area in both shells is now a semantics container of its own; a test
for each shell covers it.

**Report page layout.** Below 1000 pixels the two-column layout stacked
its columns while still wrapped in `Expanded`, inside a scrolling page,
which fails. The columns are no longer wrapped there, and the
`IntrinsicHeight` around the wide layout, which changed nothing visible,
is gone.

**Seed.** Reviewed reports carry ratings that produce their official
priority. Only reports whose text holds a Table 3.3 keyword are marked
as classified automatically. `rep-0007` (approved before 4.C, no
official priority) and `rep-0008` (unclassified) wait for review in Task
Assignment. `rep-ana-0002`, Ana's report of the same fan as `rep-0001`,
is flagged as its duplicate. `rep-0002` and `rep-0007` (plumbing at the
same building) are seeded as already kept separate. The duplicate
threshold is 0.5, and the frequency window and bands are in
`config/prioritization`.

**Not built.** The weights, bands and duplicate settings have no editor
(Chris chose the keyword editor only); they are edited in the
documents. Merging is one pair at a time. A merged duplicate is closed,
not attached to the parent's work order.

## 19. Objectives 5.A–5.C: the maintenance personnel app

**Scope and sources.** Chris's development plan: 5.A the personnel
dashboard, task list and work-order detail; 5.B status updates and the
accomplishment report; 5.C QR and barcode scanning for material and tool
usage. Built from the Figma export's personnel frames (Group 47
dashboard and Group 39 Tasks, manuscript Fig 24; Group 41 My Work Orders
and Group 42 work-order detail, Fig 25; Group 43 materials), manuscript
§3.4, and four decisions Chris made on 2026-10-12, noted below. The
older personnel passes in the export (Frame, iPhone 13&14, image 4/5,
Html→Body) are not used. The scan result page and the console's
work-order page have no frame; they are built from the existing cards
and flagged in the code.

**One mobile sign-in (Chris).** Personnel sign in on the same page as
faculty and staff; the role decides where they land, and a personnel
account reaching a faculty page (or the reverse) is sent home. The
separate personnel login route is gone. CREATE ACCOUNT stays, for
faculty and staff only, with a line under it saying GSU creates
personnel accounts. The wording on the page no longer says "faculty".

**The shell.** The faculty app's header and bottom bar became shared
widgets (`shells/mobile/`), which both apps now use. The personnel tabs
are Home, Tasks, the gold **+**, Materials and Profile; the work-order
pages count as Home, and the bell opens Alerts. Profile is the faculty
app's (Sign out only).

**Tasks: the administrator adds them (Chris).** Assigning a report now
also creates the work order's first task: the report's title, its
location as the details, due on the scheduled date or at once. The
technician is told of it. The console gained a page per work order
(the number on the board and in the table links to it) where the
administrator adds more tasks, with a due date, or deletes one not yet
done; the technician is told of each new one. Technicians tick tasks off
and upload proof photos; they cannot add, rename or reassign one. The
first task ticked or proof uploaded on pending work starts it, as Start
work does. `activeTaskCount` still counts open work orders, as in 2.B;
tasks do not change it.

**Today's to-do (DERIVED).** The open tasks of open work orders that are
due today, overdue or undated, then the tasks finished today. Coming up
is the open tasks due after today. Overdue is due before today and not
done.

**Status moves.** Personnel may start their work (pending → in
progress) and submit it (in progress → for review), nothing else;
sign-off and send-back are the administrator's. Every move — from the
board, a task, the report or the review — goes through one shared step
(`WorkOrderMove`) that moves the linked reports with it, writes their
timeline entries, tells the requestor, releases the technicians' counts
on completion and writes the audit entry, all in the same transaction.

**The accomplishment report.** Completion notes (up to 2000 characters)
and 1–5 photos of the finished work, filed with Mark Complete after a
confirmation that lists what comes off stock and any tasks still open.
One transaction files the report, takes each recorded material off
stock with a consumption entry in the inventory ledger, clears the
recorded list and moves the work order to for review. The id is
reserved before the photos upload and the transaction reads first, so a
retry after a timeout cannot file twice (as in 3.C). It is refused
unless the work is in progress and the person filing is assigned to it.

**Review.** The console's work-order page shows the report with **Approve
and sign off** (the work order and its reports complete, and the
requestor is asked to rate it, 3.C) and **Send back for rework**. A
send-back needs a note: the work order returns to in progress and the
note appears at the top of the technician's page. The technician is
told either way. A report is reviewed once; the newest is the one acted
on.

**Materials: usage now, requests later (Chris).** While the work is
open, the technician records the materials used on it, by scan or from
the list, in `work_orders/{id}/materials_used/{itemId}`. A quantity
above what is in stock is refused when recorded; stock changes only
when the report is filed. "Request Additional Materials" (Group 43)
waits for Objective 6, inventory.

**Tools.** Borrowed and returned by scan or from the list, against a
work order or none. A loan stays with the technician until returned. A
tool returned in poor condition goes to repair. Personnel see their own
loans only.

**The gold + opens the scanner (Chris).** It reads any code GSUhub
prints, QR or barcode, and looks it up as a material, then a tool, then
a room or piece of equipment (3.C's lookup). The result page offers
what fits: record the material on a work order, borrow or return the
tool, or the technician's work orders at that place. An unknown code
says so; a failed read is shown as one, not as "unknown".

**Notifications to technicians.** A new work order, a new task, work sent
back and work signed off each write a notice to the technician (type
`workOrderAssigned`, `taskAssigned`, `statusUpdate`,
`maintenanceCompleted`; related to the work order). Push on the phone
works as in 3.B, and tapping one opens the work order.

**Rules.** Personnel now list only their own work orders, tasks,
accomplishment reports and loans, and read a damage report only when it
belongs to their work. The two status moves above are the only work
order change they may make. A recorded material is the assigned
technician's own, stamped at server time, while the work is open. An
accomplishment report is filed only in the write that submits the work,
with `inventoryDeducted` true exactly when materials were used; the
rules cannot see the ledger entries themselves (known gap, as before).
A technician may ask whether a report id is taken, as a requestor may
in 3.C.

**Fixes found while testing (outside 5.A–5.C).** A `Semantics(button:
true)` without `container: true` merges into its parent, so screen
readers could not reach the task tick and the app's other custom
buttons; all of them are containers now. On the web, an error thrown
inside a Firestore transaction reached the app wrapped in a JavaScript
error and showed as "Something went wrong"; `FirestoreServiceImpl` now
rethrows the original, which also fixes the console's refusals since
2.B. The scan result page re-reads a tool after it is borrowed or
returned.

**Seed.** `personnel@` (Marcus Wright) has "Flickering Lights"
(`wo-0003`) in progress with four tasks, 4 LED bulbs recorded and the
multimeter borrowed; "Sparking Wall Outlet" (`wo-0013`, new) not yet
started with two tasks; and "Cracked Wall Near Stairwell" (`wo-0005`)
signed off. "Loose Ceiling Panel" (`wo-0009`, `structural@`) waits for
sign-off in the console.

**Not built.** Requesting materials (Objective 6). The board's columns
still move a work order to For Review or Completed without an
accomplishment report or its review. A filed report cannot be edited;
a send-back asks for a new one.

## 20. Objectives 6.A–6.C: inventory, tools, requests, QR codes and reports

**Scope and sources.** The development plan names Objective 6 only as
"inventory, tools, QR generation/scanning". Split as: 6.A materials,
6.B tools and materials requests, 6.C QR generation and inventory
reports. Built from Figma `200:4032` (manuscript Figure 15, Admin
Inventory Management, read through the Figma API for its exact styles
and icons), Figure Group 43 (the technician's materials page), manuscript
§1.5 and §3.4, and four decisions Chris made on 2026-10-13, noted below.
The console's Material Requests list, its dialogs, the work-order page's
pre-assigned card, the Facilities & Equipment page and Analytics'
inventory section have no frame; they use the console's existing cards,
tables and dialogs, and are flagged in the code.

**6.A: the Inventory Management page (Figure 15).** Four cards, the
material cards and the tool table, all read live; none of the mockup's
numbers appear. The material cards keep the design's photo, badge, name,
"category • size", quantity, edit and cart buttons. ORDER replaces the
cart on a low material. The manuscript excludes procurement (§1.5
limitations), so the cart and ORDER both **record stock received** — a
`replenishment` ledger entry — rather than placing an order. Not in the
design but needed: Add Material, a search box that searches, a category
filter, and each material's details with its stock history (§3.4
"review material usage history"), Record delivery, Record stock count
(an `adjustment` entry with a reason, either direction) and its QR
label. A material's photo is optional; without one the card shows an
icon. A new material's opening stock arrives as a ledger entry, so even
the first units are traceable.

**6.A: unit cost (Chris).** Figure 15's first card is Total Stock Value,
and §3.4's list of material fields has no price, so each material gains
an optional `unitCost` in pesos. The card sums quantity × cost and says
how many materials have no cost yet. The mockup's "+2.4% from last
month" is left out: there is no price history to compare with.
`specification` (Figure 15's "Bulk", "10ft") and `photoUrl` are also
new, both optional and DERIVED.

**6.A: low-stock alerts (DERIVED).** §1.5's "automatic low-stock alerts"
are shown live wherever the console is open, the moment a movement takes
a material to its minimum: a red count on Inventory Management in the
sidebar, the Low Stock Alerts card, the LOW STOCK badge and ORDER on the
card, and LOW STOCK on the technician's pre-assigned list. No
notification document is written: the console has no notification
centre yet, and a technician's phone cannot list the administrators to
address one to (the rules let personnel read only their own account).

**6.B: tools (Figure 15).** The table's Check Out lends a tool to an
active technician, for one of their open work orders or none, with an
optional return date (the Active Tool Loans card counts loans due today
and overdue). Check In closes the loan with the condition it came back
in; poor sends it to repair. "Locked", as drawn, marks a tool in repair.
Bringing it back, sending one to repair or retiring one is in the tool's
details, with its loan history and QR label. Add New Tool registers one;
its code defaults to `TOOL-<tool ID>`, the form the scanner already
reads. Scan QR uses the computer's camera and opens the material or
tool it reads. The rules now let an administrator create a loan for a
technician. The mockup's "Est. completion: 3 days" under Tools in Repair
has no data behind it (nothing records a repair's expected end), so the
card says how many tools there are in all.

**6.B: requests and pre-assigned materials (Chris).** The administrator
pre-assigns materials to a work order on its console page. A technician
asks for more from Group 43's page (items, quantities, a note), opened
from the work order's new Pre-assigned Materials card. The console lists
waiting requests above the materials; **Approve** (an optional note)
adds the items to the work order's pre-assigned list, **Decline** needs
a note, and the technician is told either way. Pre-assigning and
approving move no stock: §1.5 deducts "after the corresponding
accomplishment report is submitted", so stock still comes off only by
what the technician records as used. Approval is refused when the store
holds less than asked, or the work is no longer open. A request is filed
under a reserved id, so a retry cannot file it twice. The design's draft
lines say "Pending" before they are sent; the note box and the list of
what each request asked for are added, flagged.

**6.C: QR codes (Chris).** Every material, tool, room and piece of
equipment shows its code as a QR on screen and downloads it as a
printable A4 label sheet (3 × 5, a 4 cm code with its name and the code
in text), drawn with the `pdf` and `barcode_widget` packages (pure Dart).
A code may belong to one thing only, across all four kinds: one scanner
reads them all. The check runs before the save, since Firestore
transactions cannot query; two administrators saving the same new code
in the same second could both pass, acceptable at GSU's scale. New
codes default to `INV-<NAME>`, `TOOL-<ID>`, `FAC-<ID>` and `AST-<ID>`.

**6.C: Facilities & Equipment (Chris).** A new console page, beside User
Accounts in the sidebar: rooms (building, room, where it is,
coordinates, code) and the equipment in them (name, room, type, serial
number, condition, code), added, edited, deactivated and reactivated,
each with its label, and Print all labels for every active one. A room
is never deleted, so old reports keep resolving; an inactive one leaves
the report form. Until now rooms were added to Firestore by hand.

**6.C: inventory reports (Chris).** Each material's stock history in its
details. Analytics gains Most Used Materials for the chosen period:
consumption ranked by how many work orders used each material, then by
quantity (ranking quantities alone would compare rolls with bulbs). Its
Export inventory report saves a CSV of every material's stock, then
every movement in the period.

**Ledger names.** A ledger entry now carries `performedByName`, as it
already carried the item's name, so the history reads with a name for as
long as it is kept. Entries from before show the technician's name from
the personnel list, or "Not recorded".

**Seed.** Eight materials (Figure 15's five, Group 43's socket plates
and insulation tape, and floor sealant without a cost), three of them
low; five tools, the multimeter due back today; a ledger behind today's
stock (each six-month history job's materials, and an opening delivery);
four requests: two waiting (Marcus on `wo-0003`, Juan on `wo-0002`), one
declined with GSU's note, and one approved, its materials pre-assigned
to `wo-0013`.

**Fixes found while testing.** On the desktop web build, compact visual
density took all 8px of vertical padding from Figure 15's small navy
buttons, squashing them to their text; the inventory buttons now keep
standard density. ORDER's tooltip was spoken as the whole card's label;
the button now says "Order more <material>" itself.

**Not built.** Low-stock notifications as documents, and the console's
notification centre. Material photos on live need Cloud Storage, so the
Blaze plan, like every photo. Labels are a PDF to print, not sent to a
label printer.

## 21. Objective 1: data on Supabase, sign-in on Firebase

**Scope and sources.** Chris's brief of 2026-10-16: keep Firebase for
signing in only, and move every record and photo to Supabase, with no
server of our own. Firebase keeps email-and-password sign-in, password
reset emails, the administrator's "create a maintenance account" (the
second app instance, §13), and the phone's FCM token. Supabase holds the
19 tables (Postgres), the photos (Storage), the live updates (Realtime)
and one Edge Function. The repository interfaces, models, `Result` and
providers did not change: only the `*_impl.dart` files and the
`core/services` data pieces did, so no screen changed. Chris confirmed
four decisions (2026-10-16), noted below. This replaces §6b's Firestore
transactions, §7's `firebase_storage` and §9's collections; their other
points stand.

**19 tables (Chris).** One per collection, a table for each of the three
subcollections, and `app_config` for the settings documents
(docs/data_dictionary.md, "Since Objective 1"). Ids stay text: Firebase
uids are not UUIDs, and old links keep working. A geo-tag is two
`double precision` columns, not PostGIS: nothing searches by distance.
Notifications are included: the brief predates 3.B, which built them.

**Signing in: an Edge Function trades the token (Chris).** Postgres must
know who is asking. Supabase's Third-Party Auth could trust Firebase
tokens directly, but only with a `role: authenticated` custom claim set
through the Admin SDK, which in practice means Cloud Functions and the
Blaze plan, and it cannot read the Auth emulator's unsigned tokens.
Instead `supabase/functions/firebase-token-exchange` checks the Firebase
ID token against Google's keys (RS256, this project's issuer and
audience) and returns a Supabase token: `sub` is the uid, `role` and
`aud` are `authenticated`, the sign-in email is passed on, and it expires
with the Firebase token or within the hour, whichever is sooner. The
function grants nothing; it only proves who is calling. The emulator's
unsigned tokens are accepted only when `ALLOW_EMULATOR_TOKENS=true`, and
the function refuses to start with that flag on a `*.supabase.co`
project. Hosted, it signs with an ES256 key imported as the project's
signing key (same `kid`); locally, with the stack's JWT secret
(`tool/supabase_function_env.mjs` writes either).

In the app, `SupabaseSession` is the client's `accessToken` callback: it
caches the token, shares one exchange among concurrent calls, renews it a
minute early, and hands each new token to Realtime (`realtime.setAuth`),
which otherwise keeps sending the first one until it expires.

**Who may do what lives in the database.** Row level security reads the
caller's role and account status from their `users` row on every request
(`app.uid()` reads `auth.jwt()->>'sub'`), so a deactivated account is shut
out at once, without waiting for its token to expire. App accounts may
read tables and write none. Every change is a database function: a
`public.*` wrapper (security invoker, the API) calls an `app.*` function
(security definer, `search_path = ''`, not exposed) that checks the
caller, re-reads the stored state, applies the lifecycle tables (copied
from the Dart enums), and writes the change, its status history, the
reporter's notice and the audit entry in one transaction. 45 functions
replace roughly 40 Firestore transactions. Refusals carry a `PTxxx` code
(PT403 permission, PT404 not found, PT409 and PT422 a rule) and a message
written for the screen; `SupabaseErrorMapper` turns them back into the
app's `Failure` types. The matrix is in docs/data_dictionary.md, "Who may
read and change what", **derived from §3.4: verify against Development
Plan §4 when available.**

Rules that moved from the phone to the database became stricter in a few
places, each deliberate:

- A technician moves a work order in one way only: starting it
  (`set_work_order_status`, pending to in progress). Submitting work goes
  through the accomplishment report, as 5.B intended.
- Deliveries and stock counts are an administrator's.
- A report filed is the reporter's own, and only that requestor rates it,
  once, after completion.
- A material or tool code is unique across all four kinds of thing
  inside one function call. Two codes within one kind are also stopped
  by a unique index; across kinds, two administrators saving the same
  new code in the same second could still both pass (§20).
- The audit log names its actor from their account, never from the
  caller's say-so.
- `tasks.title` allows 200 characters, not 120: an assigned report's
  title becomes its first task's, and reports allow 200.

**Stock moves only through the ledger (item 1).** `inventory_transactions`
is insert-only, for the database owner too. A trigger before each insert
works out the balance from the stored quantity, refuses one below zero,
writes both balances onto the entry and moves the stock. A direct change
to `quantity_available` is refused, so no function, script or console
query can change stock without an entry. A new material starts at zero
and its opening stock arrives as an entry. `audit_logs` and
`report_status_history` are insert-only the same way.
`supabase/tests/stock_ledger.test.sql` proves each refusal.

**Photos: a private bucket and ten-year links (Chris).** One private
bucket, `photos`, holding images only, up to 10 MB each. Every path
starts with its kind and, for anything a person files, their uid
(`damage_reports/{uid}/{report}/…`), so the storage policies decide
uploads from the path alone. Reads follow who may read the record; only
an administrator deletes, and nothing is overwritten (item 2,
`supabase/tests/storage_policies.test.sql`). `SupabaseStorageService`
puts the uid into the path itself, so `StoragePaths` and the screens are
unchanged, and it stores a signed link valid for ten years, which behaves
like the Firebase download links the models already hold. Photos no
longer need the Blaze plan.

**Reading rows as documents.** `RowSnapshot` presents a row as a
`DocumentSnapshot`: `snake_case` columns as the app's field names,
timestamps as `Timestamp`, latitude and longitude as a `GeoPoint`. The
models' `fromFirestore` constructors read it unchanged. `cloud_firestore`
stays as a dependency for those types and for the test harnesses;
nothing in the app talks to Firestore.

**Live lists filter only on what never changes.** Realtime tells a
listener about a row that changes inside its filter, never about one
that leaves it. A list filtered by status would keep showing a report
after it moved on. Streams therefore filter the server side only on
columns fixed at creation (`reporter_id`, `recipient_id`, `work_order_id`)
and apply status and other filters in the app.

**Local development needs Docker (item 3).** `npx supabase start` runs
the stack (Postgres, the API, Storage, Realtime and the function) next to
the Firebase Auth emulator. The Firestore and Storage emulators are no
longer used. Debug builds use both local services, as §6b's emulator
default did; docs/local_setup.md walks through it. On a laptop with 8 GB,
start the stack without Studio and the logging services. The web reload
fix: before Firebase starts, a debug build on `localhost` records that
it uses the emulator, and anything else clears saved emulator sign-ins
from the browser. Start-up then refuses unless Auth really is attached to
the emulator, so a reload can no longer sign a local account in to the
live project. The account-provisioning helper app is checked the same
way.

**Moving the data.** `tool/migrate` reads Firestore (live, an export, or
the emulator), turns each document into a row, and loads the tables in
dependency order. A dry run reports every problem, row by row, and
commits nothing. A real run commits only when there are none and needs
`--yes`, and both refuse a database that already holds data. Stock and
ledger rows arrive exactly as they are; the run then checks that each
quantity matches its last ledger entry. `--copy-photos` moves the photos
into the new bucket and rewrites their links. docs/manual_deploy.md,
"Going live", gives the order.

**Tests.** 643 pgTAP tests in `supabase/tests`, on an empty and on a
seeded database: every policy, for each role, active and not; every
function, allowed and refused; the ledger; storage. `function_privileges`
reads the catalog, so a new function without its grants fails.
`test/unit/repositories/supabase_contract_test.dart` checks each
repository call against the migrations' function signatures (47 calls,
all 45 functions). 25 Deno tests cover the token exchange.
`test/e2e/supabase_flows_test.dart` runs three flows against a running
local stack (`SUPABASE_E2E=1`): a report with photos and a geo-tag; its
review and approval; assignment, work, materials, sign-off and rating,
checking the audit trail, the ledger and `activeTaskCount` at each step.
The old Firestore implementations moved to `test/support/firestore_backend`,
where they back the widget tests through `fake_cloud_firestore`.

**Unused repository methods (item 4).** `WorkOrderRepository.assignPersonnel`
is deleted. Nothing in the app calls the methods below; they are kept
for Chris to decide on. The general-purpose writes have no function
behind them and refuse ("changes like this go through the operation that
makes them"), since one would open a way around the rules:
`AuditLogRepository.record`, `DamageReportRepository.create` and
`update`, `InventoryRepository.recordTransaction`,
`NotificationRepository.create`, `UserRepository.create`, `update`,
`setAvailability` and `adjustActiveTaskCount`, and
`WorkOrderRepository.create` and `update`. These reads work but nothing
uses them: `AccomplishmentReportRepository.getById`,
`AuditLogRepository.getForActor`, `ConfigRepository.getPrioritization`,
`updatePrioritization`, `getDuplicateDetection` and
`updateDuplicateDetection`, `FacilityRepository.getAssetById` and
`getAssetsForFacility`, `FeedbackRepository.getById`, `getByWorkOrder`,
`getByRequestor` and `getInRange`, `InventoryRepository.watchLowStockItems`,
`getTransactionsForItem` and `getTransactionsForWorkOrder`,
`DamageReportRepository.getById`, `TaskRepository.getById`,
`ToolRepository.getToolById`, `getOpenLoansForPersonnel` and
`getLoanHistory`, `UserRepository.watchById`, `getAll` and
`getPersonnel`, and `WorkOrderRepository.getById`.

**Flagged.**

- The brief said the category screen did not exist; 4.A and 4.C's review
  panel sets it, and it moved with the rest.
- FCM keeps only each phone's token. A push to a closed app still needs
  a server to send it; notices appear in the app as before.
- The console's Kanban columns can still move a work order to For Review
  or Completed without an accomplishment report (an administrator may
  make any move the lifecycle allows); unchanged, on the still-to-do
  list.
- A free Supabase project pauses after a week without use, and must be
  resumed from the dashboard before a demo.
- **Nothing has run against a real Supabase stack yet.** This machine has
  no Docker. The SQL tests ran on PGlite (Postgres 18 in Node, where
  Supabase runs 17, with a stub of Supabase's `auth` and `storage`
  schemas, `tool/sql_tests`) and the function on Deno. `npx supabase test db`, `tool/storage_api_test.mjs`
  and the e2e flows wait for Docker. Importing the hosted signing key, and
  Supabase accepting the function's tokens with it, wait for the hosted
  project.
- Firestore and Storage keep their old data and rules until the move is
  done; locking them afterwards is Chris's decision (docs/manual_deploy.md).
