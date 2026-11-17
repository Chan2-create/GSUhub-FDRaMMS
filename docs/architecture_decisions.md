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
   `lib/core/constants/table_names.dart`. No collection name should
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

The fifteen collection names in `table_names.dart` (`users`,
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

(Historical: every route now has its screen, and the placeholder was
removed on 2026-11-12, §25.)

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
`core/services` data pieces did, so no screen changed (7.A later took
Firebase's types out of the models: §22). Chris confirmed
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
nothing in the app talks to Firestore. *Superseded in 7.A: models read a
`DataRecord`, which `RowRecord` builds from a row (§22).*

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
where they back the widget tests through `fake_cloud_firestore`. Since
Objective 7: 696 pgTAP tests, and 48 calls covering 46 functions (§22).

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
  list. *Fixed in 7.B (§22).*
- A free Supabase project pauses after a week without use, and must be
  resumed from the dashboard before a demo.
- **Nothing has run against a real Supabase stack yet.** This machine has
  no Docker. The SQL tests ran on PGlite (Postgres 18 in Node, where
  Supabase runs 17, with a stub of Supabase's `auth` and `storage`
  schemas, `tool/sql_tests`) and the function on Deno. `npx supabase test db`, `tool/storage_api_test.mjs`
  and the e2e flows wait for Docker. Importing the hosted signing key, and
  Supabase accepting the function's tokens with it, wait for the hosted
  project. *Since done (2026-10-20): every set passed on the local Docker
  stack, and on the hosted project the imported key signs the tokens
  Supabase accepts; the whole report lifecycle ran there
  (docs/manual_deploy.md, "Check it works on live").*
- Firestore and Storage keep their old data and rules until the move is
  done; locking them afterwards is Chris's decision (docs/manual_deploy.md).

## 22. Objective 7: one system, tested, ready to present

**Scope and sources.** Chris's brief of 2026-10-20: finish every
unfinished objective so the whole system is complete and running. The
manuscript and the WBS are the authority. No invented UI: Figma or the
PDFs, otherwise a plain working screen listed for the GUI pass. Open
manuscript questions are asked, or made configurable and flagged. Nothing
works around a Blaze-only feature. Only Objective 7 was unfinished:

- 7.A: join the faculty and staff app, the personnel app, the console and
  the backend into one working system;
- 7.B: functionality and usability testing, fixing what it finds;
- 7.C: documentation, deployment and the final presentation.

Checking the manuscript (§1.5, §3.4) against what was built found two
administrator requirements with nothing behind them:

- managing system notifications: the console's Notifications page was
  disabled;
- modifying assignments: work could be assigned, never reassigned.

The weights, score bands and duplicate rules had no editor either
(still-to-do item 2).

**7.A: the administrator's notifications (Figma `202:5608`).** The
Notifications page follows the frame:

- the header, with **Mark All as Read**;
- the All, Unread, Reports and System filters, and a date range;
- unread rows tinted, each row with its icon tile, a priority tag and the
  record number in bold;
- **View Older Notifications**, 50 at a time.

The bell and the sidebar open it, and the sidebar counts the unread. A
row opens what it is about: the report, the work order, Inventory, or
User Accounts.

The manuscript says the administrator manages "system notifications" but
not which events reach them. **The six events are derived** from the
frame's examples and the console's pages; confirm them with the adviser:

1. A report is submitted ("New urgent report submitted" when the
   requestor chose High or Critical).
2. A technician starts work.
3. An accomplishment report waits for sign-off.
4. A technician requests materials.
5. A sign-up waits for approval.
6. A material reaches its minimum or runs out.

Database triggers write them (`20261020111840_admin_notifications.sql`),
so no path that makes the change can skip the notice. Each goes to every
active administrator except the one who acted. They fire only for a
signed-in caller (`app.uid()`), so loading the demo data or moving the
old data does not flood the list. Five of the types are new, in
`notifications_type_check` and `NotificationType`; the low-stock notice
uses the existing `lowStockAlert`. The phones' Alerts tab knows them too.

**7.A: reassigning a work order (§3.4, "modify ... assignments").**
`reassign_work_order` is the administrator's. It hands pending or
in-progress work to one other active technician:

- the assignee, both technicians' open-work counts and the unfinished
  tasks move;
- each linked report gets a history entry ("Reassigned to …"), and its
  timeline shows the newest assignment;
- the requestor, the new technician and the former one are told;
- the audit entry says who had it.

Finished work, an account that is not an active technician, and the
technician who already has the work are refused, each with the reason.
The work order's page offers **Reassign** while the work is open. Its
dialog lists the active technicians, the matching trade first, then the
least busy. No frame exists for it, so it is a plain dialog, listed for
the GUI pass.

**7.A: Settings for the scoring and the duplicates.** Under the keyword
editor (§18), Settings gains two sections. Each shows its effect on a
sample report before saving.

- **Priority scoring**: which weights are in use, both weight sets, the
  score bands, and the Frequency window with the report counts that
  make a 2, 3 or 4.
- **Duplicate detection**: on or off; what is compared (the facility or
  asset's QR code, the stated location, the damage type); the
  description similarity; the window, in hours.

**Flagged:** both of the manuscript's weight sets are stored and
editable. Chris chose the formula's on 2026-10-12, and Table 3.2 still
needs correcting. The administrator rates all four criteria in review,
also Chris's decision (§18).

`update_config` now refuses any setting the app could not read
(`20261020111849_config_validation.sql`), so a setting saved some other
way cannot break the scoring or the classification:

- weights from 0 to 100, at least one above zero;
- ratings from 1 to 4 (Table 3.4);
- score bands between 1.00 and 4.00, falling from Critical to Low;
- a Frequency window of 1 to 365 days, with counts that rise;
- a duplicate window of 1 to 2160 hours;
- known damage types only, and keywords of 1 to 80 characters. This is
  a backstop: the keyword editor itself asks for 3 to 60.

The Settings frame (`61:5550`) shows a system information card, not
these sections, so they are plain and listed for the GUI pass.

**7.A: the dashboard links.** **View All** opens Reports, and each
recent report opens its page. The 2.A placeholders are gone.

**7.A: models free of Firebase.** This supersedes §21's "the models did
not change" and "Reading rows as documents".

- Models read a `DataRecord` (an id and its fields) with `fromRecord`,
  and write `toFields()`.
- Times are UTC `DateTime`s (`RecordConverters`, which replaces
  `FirestoreConverters`). A geo-tag is a `GeoCoordinates` (`core/data`).
- `RowRecord` turns a Postgres row into a `DataRecord`.
- `cloud_firestore` is a dev dependency, for the test harness only, which
  converts with `firestoreRecord` and `.forFirestore`.
- `firebase_initializer.dart` and `firebase_error_mapper.dart` moved to
  `core/services/firebase`. `main.dart` registers the background message
  handler through the FCM service.

Firebase is imported in `core/services` only, apart from the generated
`firebase_options.dart`.

**7.A: one command runs it all.** `tool\run_local.cmd` (untracked until
Chris decides) does the following:

1. starts the Supabase stack, or reuses it;
2. the first time, writes the token exchange's local secrets;
3. starts the Auth emulator on Java 21, in its own window;
4. adds the sign-in accounts;
5. runs the app with the stack's key.

`-Server` serves the app on a fixed port, `-Reseed` loads the demo data
again, and `-Stop` stops everything. The seed now adds ten notices for
each of the two administrators.

**7.B: the board can no longer skip the sign-off.** This was still-to-do
item 8, confirmed on live on 2026-10-20. An administrator dragged a work
order For Review → In Progress → For Review → Completed in nine
seconds, and its accomplishment report was never reviewed.

`set_work_order_status` now only starts work, Pending to In Progress, for
everyone (`20261020111846_work_order_signoff.sql`). For Review comes only
from the technician's report. Completed, or a send-back, comes only from
`review_accomplishment`.

The board follows the same rules:

- Pending's menu starts the work.
- A card waiting for sign-off opens its accomplishment report. This
  happens from its menu, or when it is dropped on Completed or In
  Progress.
- A card dropped on For Review gets a message saying how work gets there.

**7.B: other bugs found and fixed.**

- The board's date filter hid open work older than the period, so
  overdue work vanished after 30 days. The period now narrows finished
  work only.
- Two quick refusals on the board queued their messages. The newer one
  now replaces the older.
- Starting a task with a proof photo wrote no audit entry
  (`20261020112150_task_start_audit.sql`, still-to-do 20).
- The Alerts test failed between midnight and 00:45, because its "45
  minutes ago" crossed midnight. The app now reads the time from
  `package:clock`, which the tests fix.
- The record-material sheet now picks the technician's only open work
  order. Opening a sheet clears an older message that would cover it
  (still-to-do 10).
- The release check also refuses the local stack's ports, `:54321` and
  `:54322` (still-to-do 17).
- Stale text: the dashboard's 2.A tooltips (still-to-do 7) and the
  faculty Profile's note.
- The new tests caught two bugs in new code before they shipped. The
  score bands were checked in the wrong order. The review menu's item
  never fired, because a `PopupMenuItem` with no value counts as
  dismissed.

**7.B: the test plan.** docs/testing.md does three things:

- maps each requirement in §3.4 and §1.5 to the tests that prove it;
- says how to run each test set;
- gives the team's usability tasks for each role.

**7.C: the documents.**

- docs/demo_script.md: the defense walkthrough.
- docs/local_setup.md and docs/manual_deploy.md: the five new
  migrations, and the order for going live.
- docs/data_dictionary.md: the new notification types and rules.
- supabase/README.md and the README.

**Flagged.**

- Push to a phone whose app is closed still needs a server: Cloud
  Functions, on the Blaze plan. Not built, by the brief's rule (§16).
- The six notice events are derived; confirm them with the adviser.
- Map View (Figma `202:5356`) is not in the manuscript; its sidebar item
  stays disabled. (Built on 2026-11-12 from the manuscript's geo-tagging
  passages: §25.)
- The Settings frame's system information card is not a manuscript
  feature, and is not built.
- Usability testing with users, and the camera, GPS, scanning and
  notifications on real phones, are the team's (docs/testing.md).
- `docs/diagrams` (untracked): `generate.mjs` redraws the application
  architecture, deployment, and development-versus-production diagrams
  for the Supabase design. The context diagram and the data flow
  diagrams still predate Objectives 4 to 6, and the second stage (PNG
  and PDF) waits for approval.
- The 35 unused repository methods (§21) are still Chris's to decide on.

## 23. Deleting a material (2026-11-05)

Chris asked for a delete option on the Inventory page's Consumable
Materials.

**A delete that keeps the ledger.** Every ledger entry points at its
material, and the ledger is never changed or removed (§3.4
Auditability; `stock_ledger.sql`). A material that ever held stock,
which is nearly every one, cannot leave the table. So deleting marks it
deleted (`inventory_items.deleted_at`), as a room is deactivated and a
tool retired:

- the repositories never return it: not listed, not found by its id or
  its code, so it leaves the cards, the totals, the low-stock alerts,
  scans and the technicians' material lists;
- its stock history stays, and the work orders, requests and reports
  that name it read as they were written;
- the database refuses anything new on it (triggers): a ledger entry,
  an edit, a recorded use, a set-aside, a request;
- its code is free: the unique index on `qr_code` covers only the
  materials still in the inventory, so it can be re-added under the
  same label;
- the audit entry records the stock it still had. The stock is not
  written off in the ledger: a write-off would read as a stock count
  and send an out-of-stock notice for a material nobody keeps any more.

**Refused while open work counts on it**: recorded as used on pending
or in-progress work (not yet off stock), set aside for it, or on a
request waiting for review. The message names the work order or
request. Finished work does not block it.

**Where.** A **Delete** button in the material's Edit dialog (the
card's pencil) and in its details (a click on the card), each asking
first. Not on the card itself: at the console's usual width a card is
about 180 pixels wide, and a third button there would squeeze out the
quantity. No design covers it; listed for the GUI pass.

**Not built**: undoing a delete. Re-adding the material under the same
code works, but starts a new history.

Migration `20261105104825_delete_material.sql`; tests
`supabase/tests/material_delete.test.sql`,
`test/unit/repositories/inventory_deleted_test.dart` and two in
`test/widget/inventory_screen_test.dart`.

## 24. A console for every screen size, and delete everywhere (2026-11-08)

Chris asked for the admin web to fit desktop, laptop, tablet and phone
browsers, and for a delete button on everything the console lists, with
damage reports and work orders archived instead of deleted.

**Responsive layout.** The Figma frames are 1440 wide; above 1200 the
console is laid out as drawn. `core/constants/breakpoints.dart` holds the
widths:

- 1200 and up: the design's 305 px sidebar.
- 720 to 1200: the sidebar as an icon rail (76 px), names in tooltips,
  the low-stock count as a bubble.
- Below 720: the sidebar in a drawer behind a menu button in the top bar;
  pages keep a 16 px margin instead of 32.
- The top bar's card, narrower than 640, keeps the title, a page's own
  control, Export Data as an icon, and the bell; the date, the disabled
  Report New Damage and Help buttons return with the room. On a phone
  the bar is a single row (menu, title, export, bell) without the logo
  or the avatar.
- The header (2026-11-09, matched to the dashboard frame): 80 px of
  white across the whole window, the GSUhub logo over the sidebar's
  column (150 px beside the icon rail), the controls in a white card
  with a soft bottom shadow that starts where the sidebar ends, the
  section name in grey after the divider, and the avatar on its own at
  the right. The 13 px gold rule runs full width under it, and the
  sidebar starts below the rule.
- Tables keep their columns and scroll sideways inside their card when
  narrower than the columns need (`core/widgets/scroll_when_narrow.dart`,
  used by `AppDataTable` and the custom tables). The page itself never
  scrolls sideways.
- Stat rows go from four columns to two, then one; filter bars, button
  rows and legends wrap; section headers put their control under the
  title on a phone; the Analytics donut goes above its legend.
- `test/widget/responsive_console_test.dart` opens every console page at
  360, 768, 1024 and 1440 px over a full set of data and fails on any
  overflow.

**Delete.** Firestore holds no GSUhub data since Objective 1 (§21), so the
"security rules" for delete are the database's: each delete is a
security-definer function that checks the caller is an administrator,
refuses what something open depends on, and writes the audit entry; the
tests are pgTAP (`supabase/tests/console_delete_archive.test.sql`,
`material_delete.test.sql`). Every delete asks first, naming the item
(`core/widgets/confirm_delete_dialog.dart`), shows a refusal in the dialog,
and announces success; the lists are live, so the row goes at once.

| List | What delete does | Refused while |
|---|---|---|
| Consumable materials | Marks it deleted (§23) | recorded as used on open work, set aside, on a pending request |
| Tools | Marks it deleted; loans keep it; tool ID and code freed | out on loan |
| Rooms | Marks it deleted; reports keep it; code freed | open reports or work orders about it, equipment in it |
| Equipment | Marks it deleted; reports keep it; code freed | open reports about it |
| User accounts, Personnel | Removes the profile (and the person's notifications) | one's own; open work orders; a tool on loan; **any record** naming them: then deactivate instead |
| Damage reports | **Archives** it (never deleted) | not closed, merged or rejected |
| Work orders | **Archives** it (never deleted) | not completed |

Marking deleted rather than removing: every one of those rows is named
by records the manuscript keeps (§3.4 Auditability): the stock ledger,
loans, reports, work orders. Removing them would break those records or
need them removed too. A deleted row is left out of every list, picker
and scan, nothing new can happen to it (triggers refuse edits, loans,
reports against it), and its code can be reused.

Archiving sets `archived_at` and nothing else: the status (including the
manuscript's own ARCHIVED status, which is a lifecycle outcome, not this),
the timeline, the audit trail, and the requestor's and the technician's
views are unchanged. The Damage Reports list and the Work Orders board
leave archived ones out; their **Archived** filter shows them, with
Restore. Analytics still counts them: they are history.

**Accounts and Firebase.** Deleting an account removes its profile; the
sign-in admits no one without a profile (`FirebaseAuthService`), so the
person can no longer use GSUhub. The Firebase Authentication login itself
stays: removing it needs the Admin SDK on a server. Cloud Functions need
the Blaze plan, so by the brief it is not built; an administrator can
delete the login by hand in the Firebase console (Authentication → Users).

**Not given a delete, on purpose:** the audit trail and the stock ledger
(insert-only, §3.4); accomplishment reports, feedback and tool loans
(records of work done); material requests (decided records; a pending
one is declined); notifications (messages to their reader, already marked
read; auditing each removal would be noise); a work order's tasks keep
their own delete (5.A).

Migrations `20261108141827_console_delete_and_archive.sql`; tests
`supabase/tests/console_delete_archive.test.sql`,
`test/widget/console_delete_test.dart`,
`test/widget/responsive_console_test.dart`.

## 25. Map View, from the manuscript's geo-tagging passages (2026-11-12)

The sidebar's Map View item was drawn in the design (Figma `202:5356`)
and left disabled since 2.A, because the manuscript has no Map View
section. It still has none. The page is built from what the manuscript
does say a geo-tag is for, and from nothing else:

- §1.5 lists "facility damage reporting with descriptions, photo
  evidence, facility or location details, and geo-tagged coordinates" and
  "web-based monitoring and management of facility damage reports".
- Chapter II, "Geo-Tagging and Location-Based Reporting": the system
  "captures approximate device coordinates at submission, helping
  administrators and personnel pinpoint concerns across large campus
  areas or when a written description is unclear"; coordinates "are
  combined with the facility name, location description, photo evidence,
  and QR code identification so personnel can cross-check and locate
  concerns more quickly"; geo-tagging "serves only as a supplementary
  reference for verification and response".
- §1.5's limitation: the coordinates' accuracy depends on the phone's
  location services.

**What it does.** `/admin/map`
(`features/map_view/presentation/`): one pin per geo-tagged damage
report, at the coordinates stored with it at submission, on the same
OpenStreetMap tiles the faculty and staff app already shows a geo-tag on
(no API key, no billing). The reports are listed beside the map, newest
first. Choosing a pin or a row shows what the manuscript reads a geo-tag
together with: the facility (and whether it was identified by QR code),
the requestor's location description, the photo evidence, with the
status, priority and category, and **Open report** leads to the report
page, where review and assignment already happen. Open reports by
default ("for verification and response"); the **Finished reports**
filter adds the completed, closed and rejected ones. A note under the
map says, in the manuscript's terms, how far to trust a pin, and counts
the reports filed without a geo-tag (the geo-tag is optional, so they
are named rather than silently missing). Archived reports stay off the
map, as off every console list (§24). The feed is the live one behind
the reports table, so a new report's pin appears without a reload.

**What it does not do, on purpose.** No density or heat map, no building
outlines, no routes or directions, no live position of personnel, no
map of facilities or equipment, no editing of a geo-tag. None is in the
manuscript. The design's "Campus View" card on Damage Reports (Figma
`198:2968`) showed per-building density bars; it is now a still preview
of the same pins with a link to Map View, without the bars.

**No new data, no new permissions.** The coordinates have been stored
since 3.A (`damage_reports.latitude`/`longitude`), and administrators
already read every report. No migration.

**Layout.** The Figma frame was not consulted (the team's Figma quota);
the page is built from the console's shared widgets (`PageHeader`,
`SectionCard`, `AsyncValueView`, the chips) and is listed for the GUI
pass. Side by side from 1000 px, the reports under the map below that.

**Removed with it.** `core/routing/route_placeholder_screen.dart`, the
bare screen every route once resolved to (§10): Map View was its last
user.

Tests: `test/widget/map_view_test.dart`,
`test/unit/map_view/report_map_data_test.dart`,
`test/widget/admin_shell_test.dart` (the sidebar item),
`test/widget/responsive_console_test.dart` (360, 768, 1024, 1440).

## 26. The phone apps keep their design on every phone (2026-11-12)

The mobile screens were drawn at 390 px wide, with sizes and type fixed
to that width. On a real phone 360 wide with the system font size one
step up (about 115%), the sign-in page read as zoomed in: the card's
contents had 230 px instead of the design's 260, so LOGIN TO DASHBOARD
wrapped onto two lines, the email hint was cut, and the note and the
subtitle ran a line longer each. The same squeeze reached every page: at
320 the bottom bar's "Materials" broke in two and building names broke
mid-word, and at 130% text the home screens' tiles overflowed.

One place fixes it for both phone apps, `shells/app_viewport.dart` (renamed from `shells/mobile/phone_viewport.dart` in §28),
set around the app in `app.dart`:

- **Width.** On a phone narrower than 390, a `/staff/*` or
  `/personnel/*` page is laid out at 390 and scaled down to fit. The page
  is told the design's measurements throughout (window, notch and gesture
  areas, keyboard), so every screen keeps the proportions it was drawn
  with. At 390 or wider nothing is scaled.
- **Text size.** On those pages the phone's font-size setting cannot make
  text larger than drawn; smaller is honoured. The fixed-height cards,
  tiles and buttons have no room for larger text. This is a trade: a
  reader who has set a large system font gets the design's sizes, not
  larger ones. Making every screen reflow for large text is the
  alternative, and is not done.
- **The console is untouched.** `/admin/*` has its own layout for every
  width (§24) and follows the browser's text size.

The wrapper keeps the same widgets around the app on every page (a scale
of 1 where nothing is fitted), so moving between a phone page and the
console, or turning the phone, does not rebuild the open page.

Fixed alongside:

- The sign-in and sign-up buttons' labels stay on one line whatever the
  room (`AuthButton`).
- A recent report with no photo shows a faint picture mark instead of an
  empty square (faculty and staff home).
- The console's report page, on a phone: a History entry's time goes
  under the entry instead of beside it, where a long stamp left the
  entry no room. (This was the test that failed at some times of day.)

Checked in a browser with the real fonts at 360x811 (the phone it was
found on), 320x640 and 412x915, at 115% and 130% system text: both apps,
every page, no overflow. Tests: `test/widget/app_viewport_test.dart`.

## 27. Every phone size, sign-in that fits, and the dead dropdowns (2026-11-13)

**The Building and Room dropdowns that could not be pressed.** In the
faculty and staff report form they are disabled while there is nothing
to choose. On the live system the only registered room had been deleted
(§24), so the form showed two greyed boxes that ignored every press, and
because a report needs a registered room, no report could be filed at
all. Nothing covered or blocked the controls. Three changes:

- A select that cannot open says why when it is pressed: the buildings
  are still loading, could not be loaded, none are registered, the
  building has not been chosen yet, or the building has no rooms.
- With no room registered the form says so in words under the selects,
  with **Check again**, rather than leaving it to a greyed box.
- Deleting the only active room warns the administrator, in the
  confirmation, that faculty and staff cannot file a report until
  another is added (Facilities & Equipment).

The data is the administrator's to restore: rooms are added in
Facilities & Equipment. A chosen value may now take two lines in the
form's half-width selects, where "Engineering Building" was cut short.

**Sign-in and sign-up fit the screen.** As drawn they are 905 and 1046
px tall, more than most phones, so both scrolled. `MobileAuthLayout`
now fits the page to the phone in two steps: the vertical spacing
(`AuthGap`s, the card's padding, the mark) tightens to no less than 35%
of the design's; then, only if needed, the page is scaled to no less
than 85%. It measures itself after layout (height is linear in the
spacing, so one measurement solves it) and re-fits when an error line
appears. With the keyboard up the fit is left alone and the page
scrolls, so the focused field comes into view instead of the page
shrinking. A phone too short even for the tightest fit scrolls, as
before.

**The console at 320 px.** Four places ran off a 320-wide screen and
now stack or wrap there: the four rating buttons under each criterion
and the confirm button in a report's review panel; a damage type above
its keywords in Settings; the photo button in the material dialog. Every
form dropdown fills its width, so a long choice is cut with an ellipsis
rather than pushing past the field (the personnel dialog's
Specialization). The Reassign dialog's list shrinks on a short phone.

**How it is checked now.** `test/support/app_fonts.dart` loads the
app's real fonts into a test; without it a test draws every letter as a
square about twice as wide, so "does it fit" was measured wrong (the
cause of the test that failed at some times of day, §26). With them:

- `test/widget/responsive_phone_test.dart`: both phone apps, every
  page, at 320x568, 360x640, 375x667, 390x844, 430x932 and a tablet.
- `test/widget/responsive_console_test.dart`: every console page at
  320, 360, 375, 390, 430, 768, 1024 and 1440.
- `test/widget/auth_fit_test.dart`: sign-in and sign-up need no
  scrolling on seven phone sizes, and the keyboard case.

And in a browser against the local demo data, which reaches states the
tests' sample data does not: the console's pages at 320, 375, 390 and
430, eight of its dialogs at 320x640, and the two dropdowns opened and
chosen from at phone and desktop sizes.

## 28. The console at 90%, the account menu, and the profile pages (2026-11-13)

**The console's size.** At the Figma sizes the console read as zoomed in
on a laptop: a 305 px sidebar and an 80 px header leave little of a
1536 px screen for the work. The reference the team supplied was the
same screen with everything nine tenths the size (the sidebar 343 px
against 381 on a 125% display). `shells/app_viewport.dart` (the phone
apps' `PhoneViewport` of §26, renamed and widened) now draws the console
that way itself: on a window 720 wide or more, every `/admin/*` page is
laid out in a window 1/0.9 times larger and scaled to fit, so each page
is the same design at 90% with more of it on screen. One constant,
`AppViewport.consoleScale`, sets it. A phone-width window keeps the
console's phone layout at full size, where the type is already small.

This is a uniform scale, on purpose: the reference is exactly that, and
retuning every size, padding and type style by hand would have been
hundreds of edits for the same picture. The breakpoints (§24) are
unchanged; they now see the larger layout window, so the full sidebar
arrives at a 1080 px window instead of 1200.

**The account menu.** The header's gold circle (Figma `196:743`) is the
account menu: who is signed in, **My Profile**, and **Logout**, which
asks first (`core/widgets/sign_out_dialog.dart`, shared with the phone).
It opens under the circle, with a ring on hover. The sidebar footer no
longer has a logout button; it still says who is signed in. On a phone
the circle is in the top bar, since the sidebar is a drawer there.
There is no Account Settings entry: the system has no account settings
to open. Sign-out itself is unchanged.

**My Profile** (`/admin/profile`) and the **Profile tab** of both phone
apps share `user_management/presentation/widgets/profile_cards.dart`: a
header card (initials on gold, name, email, role, account status), then
Contact, Work (maintenance personnel only: specialization, availability,
open work orders) and Account. The phone's Logout also asks first. What
the pages do not have, because the system does not: a photo (`users`
has no photo field), an assigned building or room (accounts are not
tied to one), and an Edit Profile button (the manuscript gives account
management to the GSU administrator, §1.5; the page says who to ask).

No design draws the menu, My Profile or the Profile tab; they are built
from shared widgets and listed for the GUI pass.

Tests: `test/widget/app_viewport_test.dart` (the scale),
`test/widget/admin_shell_test.dart` (the menu, at every width),
`test/widget/profile_test.dart`, and the two responsive sweeps.

## 29. Settings in tabs (2026-11-14)

The Settings page had grown into one page about five screens long:
the keywords card at part of the width with the try box beside it, then
priority scoring and duplicate detection at full width, each ending in
its own save button with its own name, sixteen number boxes in four rows,
switches a screen's width from their labels, and wording written for the
team ("manuscript §3.4, Table 3.3"). Rearranged, with what the settings
do and how they are stored unchanged:

- **Three tabs**, Keywords, Priority scoring and Duplicate detection:
  one topic on screen at a time, each in a column no wider than reads
  well (`SettingsTab.maxWidth`). Every tab stays built while another is
  open, so nothing typed is lost by looking at another, and a tab with
  edits that are not saved carries a gold dot.
- **One save bar**, the same on every tab
  (`settings/presentation/widgets/settings_parts.dart`): where the
  settings stand (unsaved, saved, or the defaults still in use), then
  Discard changes and Save changes.
- **Keywords.** The box for a new keyword opens on Add keyword, after
  the last chip, instead of an empty box under each of the seven damage
  types.
- **Priority scoring.** The worked example first, then three named
  groups: Weights (only the set in use is shown; the other is kept and
  shows when chosen), Priority levels, Frequency.
- **Duplicate detection.** The switch with what turning it off does;
  tick boxes before their labels under "Compare on"; the slider with
  its value beside it; the window as a small box marked in hours.
- **Plain wording.** The manuscript's section and table numbers are out
  of what the administrator reads. The two weight sets are "Formula
  weights" and "Table weights".

The second set of weights is still there only because the manuscript's
Table 3.2 disagrees with its formula (§22). Once the table is corrected
the choice can go, and the Weights group becomes four boxes.

Tests: `test/widget/settings_screen_test.dart` (the tabs, the dot, the
save bar, and every tab at 320 and 768 wide with the real fonts).

## 30. The project reorganized for finding things (2026-11-14)

The team asked for a folder structure where any feature can be found
quickly during the defense, with a README and a code guide. The project
was already arranged by feature (`lib/features/<feature>/` with `data`,
`domain` and `presentation`), so it was not rebuilt. What made features
hard to find was fixed: three features were scattered across other
features' folders, one folder name was ambiguous, and several shared
files were named for one app. Nothing in what the system does changed:
no screen, rule, database function, table or migration.

**Moved and renamed** (every move a `git mv`, so each file's history
follows it; every import was recomputed from the file's new place):

| Was | Now | Why |
|---|---|---|
| `lib/features/reporting/` | `lib/features/damage_reports/` | "reporting" could be read as report generation (that is Analytics) |
| `reporting/presentation/map/` (3 files), `reporting/presentation/submission/widgets/geo_tag_map.dart` | `lib/features/map_view/presentation/` | Map View and geo-tagging had no folder of their own |
| `lib/features/qr_labels/` (3 files), `lib/features/scanning/` (2 files), `reporting/presentation/submission/qr_scanner_screen.dart`, `facilities/presentation/qr_lookup.dart` | `lib/features/qr_codes/` (`domain/`, `presentation/`) | QR generation and scanning were spread over four folders |
| `inventory/presentation/widgets/tool_dialogs.dart` | `lib/features/tools/presentation/widgets/tool_dialogs.dart` | The tools' screens lived in the inventory feature |
| `auth/presentation/login_screen.dart` (`LoginScreen`) | `admin_login_screen.dart` (`AdminLoginScreen`) | Pairs with the phone sign-in |
| `auth/presentation/requestor_login_screen.dart` (`RequestorLoginScreen`) | `mobile_login_screen.dart` (`MobileLoginScreen`) | Maintenance personnel sign in there too |
| `auth/presentation/widgets/requestor_auth_layout.dart` (`RequestorAuthLayout`) | `mobile_auth_layout.dart` (`MobileAuthLayout`) | Laid out the shared sign-in |
| `user_management/presentation/requestor_profile_screen.dart` (`RequestorProfileScreen`) | `mobile_profile_screen.dart` (`MobileProfileScreen`) | Both phone apps' Profile tab |
| `notifications/presentation/alerts_screen.dart` (`AlertsScreen`) | `mobile_alerts_screen.dart` (`MobileAlertsScreen`) | Both phone apps' Alerts tab |
| `shells/requestor/requestor_title_row.dart` (`RequestorTitleRow`) | `shells/mobile/mobile_title_row.dart` (`MobileTitleRow`) | Used by pages of both phone apps |
| `core/constants/firestore_paths.dart` (`FirestorePaths`) | `core/constants/table_names.dart` (`TableNames`) | The names are the Supabase tables'; the old name dated from before Objective 1 |
| `test/support/firestore_backend/features/reporting/` | `.../features/damage_reports/` | Mirrors the feature's new name |
| `test/widget_test.dart` | `test/widget/app_test.dart` | The template's name, for the app-level tests |
| `test/widget/login_screen_test.dart` | `test/widget/admin_login_screen_test.dart` | Follows its screen |
| `test/unit/facilities/qr_lookup_test.dart`, `test/unit/personnel/scan_resolver_test.dart` | `test/unit/qr_codes/` | Follow the QR code |
| `test/unit/presentation/report_map_data_test.dart` | `test/unit/map_view/` | Follows Map View |

**Code moved between files**, unchanged otherwise:

- The console's "Tool Assets & Tracking" table (`_ToolsSection`,
  `_ToolTable`, `_TableFooter`) left
  `inventory/presentation/inventory_screen.dart` for
  `tools/presentation/tools_section.dart`, as the public `ToolsSection`;
  the Inventory page still shows it in the same place.
- `allToolsProvider`, `toolProvider`, `openLoansProvider` and
  `toolLoanHistoryProvider` left `inventory/presentation/inventory_providers.dart`
  for `tools/presentation/tool_providers.dart`.
- `consoleScanLauncherProvider` left the inventory screen for
  `qr_codes/presentation/qr_scanner_screen.dart`, beside the other two
  scan launchers.

**Corrected:** doc comments that described a shared file as one app's
own (the title row, the phone sign-in, the Alerts tab, the scan
resolver); the Alerts tab's also still said it reads Firestore.

**Removed, then put back:** the `cupertino_icons` dependency. Nothing in
GSUhub's own code uses it (the app draws Material icons only), but with
it gone the release builds warned that the compiled app still refers to
its font, from code in Flutter or a package rather than ours. It went
back in, unchanged, rather than risk icons drawn as empty boxes. No
files were deleted by the reorganization.

**Written:** the README, rewritten around what a reader needs (overview,
technologies, structure, setup, running the console, backend and phone
apps, the database connection, the main modules), and `CODE_GUIDE.md`, a
feature-by-feature map from each screen to its controller, repository,
database function and tests.

**Left as it was, on purpose:**

- Tests stay arranged by kind (`unit/`, `widget/`, `e2e/`), with
  `docs/testing.md` mapping each requirement to its tests.
- Rooms and equipment stay one feature (`facilities/`): equipment
  belongs to a room, and one page manages both.
- Maintenance management stays three features (`work_orders/`,
  `tasks/`, `accomplishment/`), each with its own tables; the code guide
  groups them.
- Screens are not split into `admin/` and `mobile/` subfolders: the file
  names say which app (the naming conventions in `CODE_GUIDE.md`), and
  the split would have moved a hundred more files for the same answer.
- `scripts/` and `tool/` keep their names and contents: the team runs
  `.\scripts\deploy_web.ps1` and `tool\run_local.cmd` as they are.
- Kept although rarely used: `tool/migrate/` (the Firestore → Supabase
  migration, documented and tested, never needed because the live
  Firestore held no data), `firebase/` and `test/rules/` (the Firestore
  rules, until Firestore is locked), and `docs/diagrams/`, untouched.

## 31. Sessions end after 30 minutes of inactivity (2026-11-14)

*The limit is 15 minutes since 2026-11-15 (§37); the design below is
unchanged.*

**The brief (Chris, 2026-11-14).** Sign people out after 30 minutes
without activity, on the web console and on both phone apps alike.
Activity is mouse movement, clicks and keys on the web, taps and other
touches on the phone, and moving between pages. Warn at 28 minutes with
a countdown; any interaction during the warning resets it; at 30 minutes
end the session and show the sign-in page. And: "handled securely by the
backend, not just through frontend timers." Never sign out someone who
is using the app.

**Two clocks, and the database's is the one that counts.** A timer in
the app can warn and sign out politely, but a client that ignores its
timer (a tampered build, a browser tab with scripts paused) would keep a
working token. So the database decides, in the one place every policy
and every function already pass through:

- The token exchange now copies Firebase's `auth_time` — when the
  password was last typed — into the Supabase token. A fresh sign-in is
  activity in itself, which is how an idle account comes back without
  any record having to change first.
- `app.user_activity` (schema `app`, not exposed by the API) holds when
  each account last did something. The app records it through
  `touch_session` while it is being used, at most once a minute
  (`SessionPolicy.touchInterval`): one small upsert per active user per
  minute, not a write on every request.
- `app.active_role()` requires activity, or a sign-in, within
  `app.inactivity_limit()` (30 minutes), besides an active account. Past
  it the caller is nobody: reads see no rows, Realtime delivers nothing,
  and `require_active` / `require_admin` refuse with a new code,
  **PT401**, whose message says the session ended. `touch_session`
  checks the same thing first, so touching late revives nothing.
- A token without `auth_time` and an account with no record count as
  alive. Only the exchange can mint tokens, and it has always set the
  claim since this change; the tests' own tokens set `sub` alone.

Why not simply shorten the token's life to 30 minutes: the app renews a
token a minute before it expires whether or not the person is active,
and a token minted at minute 29 of activity would be good for 30 more
idle minutes. The activity record is exact to the minute.

Why RLS stays silent (no rows) rather than raising PT401 too: policies
are also evaluated by Realtime for every change it considers delivering,
and an exception there is noise at best. The functions raise; the app's
own timer is what the person normally meets; and the first function call
or `touch_session` after an idle gap surfaces PT401 if the timer somehow
did not fire.

**In the app** (`lib/core/session/`):

- `InactivityMonitor` keeps the time of the last activity and compares
  it with the wall clock every second — not by counting ticks, so a
  laptop closed for an hour or a phone app left in the background wakes
  to a session that has ended. Phases: active, warning (28:00 on), expired.
- `SessionActivityListener` wraps the whole app, outside the router: a
  translucent `Listener` for presses, drags, mouse movement and scrolling,
  a `HardwareKeyboard` handler for keys, the router's delegate for page
  changes, and `AppLifecycleListener.onResume` so a phone app checks the
  clock the moment it returns to the foreground. It consumes nothing.
- `SessionWarningOverlay` draws the warning and its countdown over the
  page, in the tree rather than as a dialog route: it sits above the
  router, so it shows over any page and over any dialog a page has open,
  and it needs no Navigator. The brief counts mouse movement as activity,
  so the warning disappears the moment the person does anything; its
  buttons ("Stay signed in", "Sign out now") say so in words.
- `SessionWatch` ties them together: starts and stops the monitor with
  the sign-in, throttles the touches, and on expiry retires the phone's
  push token, signs out through the same `AuthController`, and sends the
  person to their area's sign-in page with the page remembered
  (`AppRouteGuard.signedOutLocationFor`), so signing in again returns
  them to where they were. The sign-in page shows a neutral notice
  (`LoginState.sessionNotice`): "You were signed out after 30 minutes of
  inactivity." A PT401 from any call, caught by the Supabase call guard's
  new `onFailure` hook, ends the session the same way.
- `SessionPolicy` holds the numbers; a unit test reads the migration and
  checks they match the database's.

**Deploying it, in this order:** the Edge Function first
(`npx supabase functions deploy firebase-token-exchange`), then the
migration (`npx supabase db push`). The other way round, a person whose
last recorded activity is older than 30 minutes could not sign back in
until the function was issuing `auth_time`, because nothing would prove
their sign-in was fresh.

Tests: `supabase/tests/session_inactivity.test.sql` (25), the exchange's
`auth_time` tests, `test/unit/core/inactivity_monitor_test.dart`,
`test/unit/core/session_backend_test.dart`, and
`test/widget/session_expiry_test.dart` (the warning and the countdown,
any tap, mouse movement or key clearing it, the sign-out and the notice
on the phone and in the console, a phone waking past the limit, the
database's refusal, the once-a-minute touch, and returning to the page
after signing in again).

## 32. The header as one bar, and the account button (2026-11-15)

**The direction (Chris, 2026-11-15).** The Figma stays the visual
reference: no redesign, a refinement. "Formal, professional, clean,
organized"; keep the sidebar, the logo, the purple, gold and white;
remove decoration that does not earn its place. Two concrete items came
with it: the header's inset white card, which read as a second bar
floating inside the first, and the plain gold circle, which did not read
as a button.

**One bar.** `AdminTopBar` (§24) drew the design's controls in a white
card with its own shadow, inside the white header, with the avatar
outside it. The card is gone: the header is one 64 px white bar (was 80
with the card's inset), the logo over the sidebar's column, a hairline,
the page's name in the title weight, the date, and at the right Export
Data, Report New Damage, the bell, Help, a hairline and the account
button. The 13 px gold rule still runs under it, full width, and the
sidebar still starts beneath the rule. What the page's name used to
share with the date at the right of the card now sits at the left, where
a title belongs. Narrower windows drop the date (below 940 px of header)
and the disabled Report New Damage (below 820), then fall back to the
compact row (title, a page's control, Export as an icon, the bell) as
before; the phone's bar is unchanged.

**The account button.** The gold circle now carries the signed-in
person's initials (the generic figure until the profile is read), with a
chevron that says it opens and a tinted pill under the pointer. The menu
gained the person's avatar and a role pill in its heading, and a
**Settings** entry, which opens the system's Settings page the sidebar
also opens. There is still no *Account* Settings: the system has none
(§28). Logout still asks first; sign-out is unchanged.

**Also fixed on the way.** The shell's phone drawer was sized with
`AdminSidebar.width.clamp(0, width - 56)`, which throws for a window
narrower than 56 px. Headless Edge reports such a width for a frame
while resizing, and the console threw an `ArgumentError` on every frame
until the size settled. The drawer is now `(width - 56).clamp(0,
AdminSidebar.width)`.

Checked in Edge at 1440, 1280, 1024, 900, 768 and 390 px, the account
button under the pointer and the menu open (screenshots), and by
`test/widget/admin_shell_test.dart` and
`test/widget/responsive_console_test.dart`.

## 33. Inventory Management in tabs (2026-11-15)

The first of five refinements under the direction in §32 (Chris,
2026-11-15: the Figma stays the reference; refine, do not redesign; one
commit each). The Inventory page stacked Figure 15's two halves and the
material requests on one scroll: the four summary cards, then Material
Requests (only when there were any), then Consumable Materials, then
Tool Assets & Tracking, about three screens on a laptop and far more on
a phone. The tools table was out of sight below every material card.

- **Three tabs under the cards**, Materials, Requests and Tools, one on
  screen at a time. Each tab holds exactly the section it held before,
  heading, controls and all: Consumable Materials with its search,
  category filter and Add Material; Material Requests with Approve,
  Decline and Show recently decided; Tool Assets & Tracking with Scan QR,
  Add New Tool, the table and its pages. Nothing moved between them and
  no button changed. The cards stay above the tabs, since they sum the
  whole store.
- **The Requests tab counts what waits** for review in a gold pill, so
  the administrator sees there is something to decide without opening
  it. The section used to hide itself when there was nothing; the tab is
  always there, and says when nothing has been requested yet.
- **Every tab stays built** while another is open, so a search, a
  category filter or the table's page survives a look at another tab;
  only the open one is laid out, painted and reachable by the keyboard
  (`ConsoleTabPages`).
- **The address can name the tab**: `/admin/inventory?tab=requests`
  opens on Requests, which is where the *Materials requested* notice now
  leads (`RoutePaths.adminInventoryTab`); a low-stock notice still opens
  the page as it opens by default, on Materials. An unknown name opens
  Materials.
- **One tab component for the console.** Settings' tab row and pages
  (§29) moved from the Settings screen to
  `lib/core/widgets/console_tabs.dart` (`ConsoleTabBar`,
  `ConsoleTabPages`), gained the count pill, and are what both pages use.
  Settings looks and behaves as it did, including the gold dot for
  unsaved edits.

Checked by `test/widget/inventory_screen_test.dart` (the tabs, the count,
what was typed surviving a switch, `?tab=`, the notice landing on
Requests, and every earlier test on the tab its subject now lives on),
`console_delete_test.dart`, `settings_screen_test.dart` and the page at
every width in `responsive_console_test.dart`, and by rendering the page
at 1440 and 390 px with the real fonts.

## 34. One menu per table row, and the emergency card gone (2026-11-15)

The second refinement under §32's direction.

**The reports table's row.** The design (`196:1371`) ends each row with
View and four icons: assign, edit, merge, delete. Two of the four were
never functions of the console. Editing a submitted report is not an
administrator's function (a report is a record; corrections go through
GSU), and merging duplicates has repository support from 1.B but no
objective that surfaces it. So every row carried two greyed-out icons
whose tooltips explained why they did nothing, next to an assign icon
that was grey on most rows too. The row now ends in **View** and one
**⋮ menu**:

- **Assign**, offered when the report is approved and has no work order.
  Enabled when the damage type and official priority are confirmed; until
  then the entry is there but disabled, with the reason under it, since
  the repository would refuse (§18). Rows in any other state do not list
  it: the way to assignment runs through the report's page.
- **Archive**, or **Restore from archive**: the console's delete for a
  report (§24). Disabled with the reason on a report that is not closed,
  merged or rejected.
- Edit and merge are gone. If merging is ever brought into scope it goes
  here, as an entry, not as an icon on every row.

**The work orders table's row.** It had no actions at all: the number
was a link, and the board's cards had the moves and Archive in their
menus. The row now ends in the same View and ⋮ as the reports table,
and the menu offers what the board's card menu offers in that column
(§22): *Move to In Progress* for pending work, *Review the
accomplishment report* for work waiting for sign-off, and Archive or
Restore for completed work, through the same controller and the same
confirmations. Work in progress has no move, as on the board, and the
entry says archiving waits for completion.

**One pair of widgets** draws both (`lib/core/widgets/row_menu.dart`):
`RowViewButton`, the design's olive View; `RowMenuButton`, the ⋮, whose
tooltip names the row ("Actions for #REP-12") so screen readers and
tests can tell one row's menu from another's; and `RowMenuEntry`, a menu
line with the reason in a caption when the row cannot do it now. The
Actions column narrowed from 190 to 120 px.

**The emergency card.** "Need urgent assistance?" with Dispatch
Emergency Team (`198:2991`) was drawn as designed with the button
disabled, since emergency dispatch appears nowhere in the manuscript's
requirements: no recipient, channel or record for it exists. A
disabled call-to-action in the brand's amber, on every visit, read as
something broken. The card is removed; the Campus View map has the row
to itself. Its icon and two text styles went with it. Should emergency
dispatch ever be specified, the card is one commit away in the history.

Tests: `test/widget/reports_screen_test.dart` (the menu's entries and
reasons by status; no emergency card), `work_orders_screen_test.dart`
(the table's menu moves through the repository; reasons by status),
`console_delete_test.dart` (archive and restore through the menu) and
both pages at every width in `responsive_console_test.dart`.

## 35. The dashboard's chart: open reports by priority (2026-11-15)

The third refinement under §32's direction.

**What was there.** "Monthly Report Volume by Building" (`196:781`)
compared this month's reports with last month's, per building, five
bars. The design's numbers were illustrative; the real ones were zero
on nearly every bar, because a campus unit files a handful of reports a
month and the chart split them by building and then by month. A chart
that reads 0 on every visit is decoration, and the first thing on the
dashboard below the table.

**What is there.** "Open Reports by Priority": one bar per level,
Critical first, in the level's own colour, the colour its chip carries
in every table. The bars are scaled against the busiest level. The
solid part of a bar is the reports whose level an administrator has
confirmed; the pale part still carries the system's recommendation or
the requestor's own choice, which the manuscript has confirmed before
work-order assignment (§1.5, §18). So the chart answers the two
questions the dashboard is opened for: how much is open, and how much
of it still waits for a decision. The card's key says what solid and
pale mean; each bar reads to a screen reader as "High: 3 open reports,
1 awaiting confirmation".

**Where the numbers come from.** The same live stream as the stat
cards (`reportsStreamProvider`, every row of `damage_reports`, not a
page of it), counted in `openReportsByPriorityProvider`: open statuses
only, by `effectivePriority`, split on `isPriorityConfirmed`. The four
totals add up to the Damage Reports page's TOTAL OPEN, and move the
moment a report does. It is not a database aggregate, for one reason:
the level in force is the administrator's decision, falling back to the
recommendation and then to the requestor's choice, and the model
resolves that in one place; an SQL `coalesce` would be a second copy of
the rule. Nothing on the card is a constant: with no open report it
says so instead of drawing four empty tracks.

`building_volume_chart.dart` is gone; `priority_chart.dart` replaces
it. Tests: `test/widget/dashboard_populated_test.dart` (the counts by
level from a fixture with one confirmed and two recommended levels and
one completed report, the key, and the card at 360 px) and
`dashboard_screen_test.dart` (the empty state).

## 36. One page header, one rhythm, one button (2026-11-15)

The fourth and fifth refinements under §32's direction, in one commit
because they edit the same lines: how each console page opens, and the
spacing, type and buttons around it.

**One header.** Thirteen pages opened thirteen ways: a `PageHeader`
with a title column and an action (Damage Reports, Personnel, Map
View, Notifications, My Profile), a bare title and subtitle (Work Order
Management, Task Assignment, User Accounts, Settings), a title with no
subtitle (Analytics), a `Wrap` of its own (Facilities & Equipment), and
no title at all (Dashboard, Inventory Management), with the gap under
the title anywhere from 20 to 48 px and the subtitle 4 or 12 px below
the name. `PageHeader` now takes the page's name, one line of purpose
and an optional action, and every page uses it: the name in the title
style, the purpose line under it, the action at the right (under the
title on a phone), and the first block of the page at
`PageHeader.gapBelow` (24 px) on every page. Dashboard and Inventory
Management gained a name and a purpose line like the rest; Analytics
gained its purpose line; the two subtitles that ended without a full
stop end with one.

**One rhythm.** Every page's scroll padding is the gutter on all four
sides (32 px, 16 on a phone); the dashboard's 25/24/48/48 and the
inventory and notifications pages' 1.5× vertical padding are gone.
Stat-card rows gap at 24 px on every page (the dashboard's was 18, the
work orders' 16); a row of stat cards is followed by 32 px; the table
and the map on Damage Reports are 32 apart (were 48); the dashboard's
chart card sits 32 under the row above it (was 16, a grid gap). Inside
a block, nothing moved.

**One button.** The pages' primary actions were four hand-made
buttons: Create Report (padding 24/12, 16 px label), Add Personnel (the
same in another style constant), Print all labels (outlined, 20/14),
Mark All as Read (outlined, 24/13, its own text style).
`PageActionButton` draws all four: navy, square corners, the design's
16 px label, filled or outlined, with or without an icon. Buttons inside
pages that are a design's own (Figure 15's inventory buttons, the
sign-in page, the save bar) are untouched: the pass is about the page's
head, not about every button in the system.

Not changed, on purpose: the top bar still names the page as well, as
the Figma frames do (every page frame carries both); the phone apps
share none of this and are not touched.

Tests: `test/widget/admin_shell_test.dart` (the page name now appears
three times on the dashboard: sidebar, bar, page),
`admin_notifications_test.dart` (the subtitle's wording), and every
page at every width in `responsive_console_test.dart`; the thirteen
pages rendered with the real fonts at 1440 px and two at 390 px.

## 37. The session limit is 15 minutes (2026-11-15)

Chris's brief of 2026-11-15 shortens the inactivity limit of §31 from
30 minutes to 15, with the same behaviour otherwise: the warning and its
two-minute countdown now show at 13 minutes, any interaction during the
warning resets the clock, and at 15 minutes the session ends and the
person lands on the sign-in page with the reason. Nothing counts as
activity that is not the person doing something; an app left open does
not keep itself signed in (§31's listener and the database's record of
activity are what they were).

The number lives in two places and the change touches exactly those:
`app.inactivity_limit()` and the words of `app.require_session()`'s
refusal, replaced by `20261115093218_session_inactivity_15_minutes.sql`;
and `SessionPolicy.inactivityLimit`, whose unit test reads the migration
to keep the two equal. The token exchange carries no limit, so it is not
redeployed for this; `supabase db push` is what puts the 15 minutes on
the server, and until it runs the server still allows 30 while the app
signs out at 15, which is safe in that direction. The pgTAP test's
boundaries moved with the limit (14 minutes alive, 15 minutes and a
second not).

Tests: `supabase/tests/session_inactivity.test.sql`,
`test/unit/core/inactivity_monitor_test.dart`,
`test/unit/core/session_backend_test.dart`,
`test/widget/session_expiry_test.dart`, all now written against the
policy's constants rather than the number.

## 38. The sign-in page's photograph and card (2026-11-15)

Chris's brief of 2026-11-15, part 5: the console's sign-in page looked
plain, the white box flat, the photograph "too zoomed in".

**The photograph.** It is square, 474 × 474: the graduates' monument,
sky above, plants below. Drawn with `BoxFit.cover` on a wide page it
showed its top third at three times its size, which is the zoom Chris
saw, and the softness with it. Now the whole photograph is drawn, as
taken, as large as the page allows, its edges fading into the same
picture stretched to fill and blurred behind it, under the same indigo
wash: the page is still full-bleed, with no seam. Nothing is cropped, the monument is whole, and the upscaling is
under two to one on a laptop. The brief asked for the image's aspect
ratio to be kept and cropping avoided; this is the only way to do both
with a square photograph on a wide page. A larger photograph would
still look better than this one can.

**The card.** It was drawn at 80% opacity as a whole, type included.
Now only its fill is translucent (94%), with a hairline of white, a
soft long shadow and a short one, and a 4 px gold rule along its top
that draws in from the left as the card settles. The card fades in and
rises 16 px after the page; the photograph fades in first. The fields
tint faintly under the pointer and their border still animates to the
focus colour; the button lifts a little under the pointer and swaps
its label for the spinner with a short cross-fade.

**Motion that respects the setting.** Every one of these is a
`TweenAnimationBuilder` or an implicit animation: declarative, so
nothing is left pending in tests, and all of them read
`MediaQuery.disableAnimationsOf`, which on the web follows the
browser's reduced-motion preference. With it on, the page appears as it
ends up, and the photograph stands still.

Tests: `test/widget/admin_login_screen_test.dart` (unchanged: the
form, validation, errors and the reset dialog still pass through the
animated card), `app_viewport_test.dart`, `session_expiry_test.dart`;
rendered with the real fonts at 1440, 1024 and 390 px.

## 39. Starting, loading and touching, on the phone (2026-11-15)

Parts 2, 3 and 4 of the same brief: the phone apps' launch, their
loading states, their transitions and their buttons' response, without
redesigning them.

**The logo at launch** (`lib/core/widgets/launch_splash.dart`). From
the first frame until the session is known, Firebase is restoring the
sign-in and the router holds still; that gap was a blank page on both
the phone and the web. The GSUhub logo now fades in and settles over
it, stays at least as long as its own entrance (900 ms), and fades out
(350 ms) the moment the session is known, into the page the person was
headed for. It is a real loading state, not a timer: with the session
already known it is gone after one entrance; while Firebase is slow it
stays, and nothing behind it takes a tap. Tickers, not timers, so it
settles in tests. Under reduced motion the logo appears and goes
without scaling. The page under it keeps its place in the tree
when the logo leaves: a first version returned the page on its own once
the logo had gone, which moved it, and Flutter rebuilt every page and
listener under it (`report_detail_test` counted three listeners where
two belong; `launch_splash_test` now checks the page is built once).

**Skeletons in place of spinners** (`skeleton.dart`, and the
`loading:` slot of `AsyncValueView`). A list that loaded behind a
spinner was a blank area that jumped to its full height when the data
landed. Now the eleven phone screens that load lists or records show
the shape of what is coming, in grey, with a soft sheen moving across
it: three cards where cards will be, four lines where a paragraph will
be, the tiles and cards of the technician's home. Nothing is shown
that is not loading; a screen whose data is already in hand draws it
at once, as before. Drawn with the framework alone, one ticker per
skeleton, still under reduced motion, and one thing to a screen reader
("Loading"). The console keeps its spinners: its tables are read on a
wired connection and its loading states were never the complaint.

**Transitions.** Each platform keeps its own page transition. On
Android that already is Material 3's fade-forwards, with the predictive
back gesture on top, so it is not overridden: naming fade-forwards
directly would only lose the gesture's preview. What changed is reduced
motion. The framework's transitions ignore that setting, so
`ReducedMotionTransitions` (`lib/core/widgets/`) wraps each
platform's default: the same transition and durations as before, and
under reduced motion the new page is simply there.

**One gutter on the phone.** Every phone page now keeps 16 px from the
screen's edges. The faculty home kept the frame's own offsets (9 and 11
at the edges, then 3, 13 and 2 more per block), so its cards' edges sat
a few pixels apart, and My Reports alone used 24. The home also has one
vertical rhythm now: 16 between blocks, 8 within.

**Starting on Android.** With the phone in dark mode, the native launch
window and the window behind Flutter while it starts were black
(`?android:colorBackground` under the night theme), and then the white
logo screen appeared. Both are white now
(`android/app/src/main/res/drawable-v21/launch_background.xml`,
`values-night/styles.xml`); the app has no dark theme. On Android 12
and later the system's own splash, the launcher icon, comes first and
is Android's to draw.

**Touch.** `PressScale` shrinks a control to 97% while a finger is on
it, before the ripple has spread, and lets go on release or cancel. It
is a listener, not a gesture, so the button underneath still gets its
tap. On the sign-in and sign-up buttons, the home tiles, the gold +
and Submit Report. Nothing moves under reduced motion.

**Submitting a report** already showed its progress (the upload count
and "Submitting…" across the button); it is unchanged.

Not done, on purpose: no new package, no Lottie, no shimmer library;
no spinner shown where data is already there; the phone's spacing and
type are as the design has them, and only the pieces above changed.

Tests: `test/widget/launch_splash_test.dart`, `skeleton_test.dart`,
`press_scale_test.dart`, `reduced_motion_transitions_test.dart`, and
every phone test that boots the app, which
now waits through the logo.

## 40. The app icon is the GSUhub gear (2026-11-16)

The installed app still carried Flutter's default icon, and so did the
web console's install icons (the tab icon was already the gear). Both
now show the gear mark from the GSUhub logo, on white.

**Why the gear and not the whole logo.** The logo is a wordmark: the
gear "d", then "GSUhub". At launcher size, about 48 dp, the word would
be a few pixels tall and unreadable, and Android prints the app's name,
GSUhub, under the icon anyway. The gear is the part that survives being
small, and it is what the tab icon already shows.

**Android.** An adaptive icon for Android 8 and later
(`mipmap-anydpi-v26/ic_launcher.xml`): a white back layer
(`values/ic_launcher_background.xml`) and the gear on a transparent
front layer (`mipmap-*/ic_launcher_foreground.png`), which the phone
masks to its own shape, circle, squircle or rounded square. The gear is
drawn about 50 dp across on the 108 dp layer, inside the 66 dp that is
sure to show, with room around it as launcher logos have. Older phones
get the classic `ic_launcher.png`: the gear on a white tile with rounded
corners.

**Web.** `web/icons/`: `Icon-192` and `Icon-512` (the gear on a white
tile), the two maskable ones (white to the edges, the gear inside the
middle 80 % the browser keeps) and `apple-touch-icon` (white to the
edges, since iOS rounds the corners itself and fills transparency with
black). The manifest already had GSUhub's name, colours and description.

**How they are made.** `scripts/generate_app_icons.ps1` finds the gear
in `assets/images/gsuhub_logo.png` (its first run of drawn columns) and
draws every size from it, with Windows' own imaging, so nothing is added
to the project. The gear in that file is only 141 px wide, so the
largest sizes are drawn up from it and are a little soft. Exporting the
logo larger from the Figma file (1024 px, say) and running the script
with `-Logo` on that file would make them sharp.

Not done: a monochrome layer for Android 13's themed icons. Phones that
theme their icons show GSUhub's in its own colours.

## 41. A tool changes hands only when the technician scans it (2026-11-16)

Until now the console's **Check Out** lent a tool on the spot and
**Check In** closed the loan, whether or not the tool had moved. The
brief of 2026-11-16 asks the opposite: the administrator starts the
transaction, and nothing changes until the technician scans the tool's
QR code in GSUhub and confirms.

**Requests are their own table.** `tool_requests` holds both kinds, a
checkout (`checkOut`) and a return (`checkIn`): the tool, its code and
QR code as they were (kept after the tool is deleted), the technician,
the administrator who asked, when, the collect time, the expected
return, the purpose and message, and how it ended (`pending`,
`confirmed`, `cancelled`, `expired`) with the times. `tool_loans` keeps
its meaning, a tool in someone's hands; a confirmed checkout opens a
loan and a confirmed return closes one. Putting pending checkouts into
`tool_loans` would have made every loan query ask "but was it really
lent?". At most one request waits per tool (a unique partial index).

**The statuses people read** are the brief's table, worked out from the
request and the clock (`ToolRequest.statusAt`): Check-Out is Pending
Confirmation, Borrowed or Cancelled (or Expired, when nobody collected
it); Check-In is Awaiting Return, Overdue once the return time passes,
or Returned. Overdue and Expired show the moment the time passes; the
database's sweep (below) only adds the notices and the record.

**The tool is reserved while a checkout waits.** `ToolStatus.reserved`
(the RESERVED badge) means "asked for, not yet collected": no one else
can borrow it, it cannot go to repair or be deleted, and cancelling or
lapsing puts it back to available. A tool asked back stays Borrowed:
it is still in the technician's hands.

**Who may do what, in the database** (`20261116015224_tool_requests.sql`):

| Function | Who | Refuses |
|---|---|---|
| `request_tool_checkout` | administrator | an inactive or non-technician account, no purpose, a return before the collect time, a tool not available (reserved, out, in repair, retired, deleted) |
| `confirm_tool_checkout` | the technician it names (`PT403` for anyone else) | a second confirmation, a cancelled or lapsed request, a code that is not this tool's |
| `request_tool_return` | administrator | a returned loan, a time already past, a second request for the same loan |
| `confirm_tool_return` | the technician holding it | anyone else, a code that is not this tool's |
| `cancel_tool_request` | administrator | a request already closed |
| `borrow_tool_by_scan` | a technician, for themselves | a tool reserved (for them: "confirm that request instead"), a code that is not this tool's |

The scanned code is compared with the tool's own QR code
(`app.require_scanned_tool`), trimmed and ignoring case, and the refusal
says which tool was scanned instead. Every step writes an audit entry
("Received Hammer Drill (TL-0006), confirmed by scanning it").

**Scanning is required everywhere, not only for the console's
requests.** A technician who borrows on their own also scans the tool
(`borrow_tool_by_scan`), and returns by scanning it (`confirm_tool_return`,
which also closes a waiting return request). The phone's "pick a tool
from the list" is gone: it would have been the one way to borrow a tool
without having it. The old `borrow_tool` and `return_tool` stay in the
database but refuse, with a message to reload the console or update
GSUhub, so a phone still on 1.2.0 cannot lend a tool unscanned.

**Notifications**, eight new types:

| To | When | `type` |
|---|---|---|
| The technician | a checkout is asked of them | `toolCheckoutRequested` |
| | a return is asked | `toolReturnRequested` |
| | within the hour before the return is due | `toolReturnDue` |
| | a request cancelled, or a checkout lapsed | `toolRequestCancelled` |
| | the return time passed | `toolOverdue` |
| Every administrator | a checkout confirmed | `toolCheckoutConfirmed` |
| | a return confirmed (saying so when late) | `toolReturned` |
| | a checkout still uncollected an hour after its collect time | `toolCheckoutPending` |
| | the return time passed | `toolOverdue` |
| | a request cancelled, or a checkout lapsed | `toolRequestCancelled` |

On the console they open the Tools tab; on the phone, Materials & Tools.

**The sweep.** `app.sweep_tool_requests()` runs every five minutes from
pg_cron (installed by the migration where the server has it; the PGlite
tests call it directly). It lapses checkouts not collected by
`expires_at` (24 hours after the collect time, or the expected return
if sooner, but never less than an hour from when it was asked), and
sends the reminders above, each once. It writes its audit entries as
"GSUhub", since no one is signed in. Only the database can run it.

**On screen.** Console, Tools tab: the Check Out form (tool, technician,
collect on, expected back by, purpose, instructions, work order) and the
Check In form (the tool and who has it, return by, message); a "Waiting
for a Technician" panel above the table listing what is pending, with
Cancel; the tab's count; the row's RESERVED badge with "to collect"
under the name, or Awaiting Return / Overdue in place of Check In; a
REQUESTS section in the tool's details. Phone, Materials & Tools: a
"From GSU" section with each request and **Scan to confirm** / **Scan
to return**; scanning the tool from the gold button opens the same
confirmation. Confirming always shows the tool and the request first.

**Not done, and why.** If a technician's account is deactivated while
they hold a tool, no one can close that loan: the brief says only the
technician confirms a return, and there is no administrator override.
That needs a decision (for instance, an administrator's "recovered
without a scan", written to the audit log). Overdue is for a return
request's deadline; a loan's expected return from the checkout shows
as "due today" on the stock card but sends no notice until GSU asks
for the tool back.

Tests: `supabase/tests/tool_requests.test.sql` (43, the brief's eight
scenarios among them), `tool_functions.test.sql`;
`unit/models/tool_request_test.dart`,
`unit/repositories/inventory_management_test.dart` (requests),
`unit/repositories/personnel_work_test.dart`,
`widget/inventory_screen_test.dart` (check out and check in),
`widget/personnel_app_test.dart` (tool requests from GSU).

## 42. Saved changes show without a reload, and a review keeps what the requestor chose (2026-11-16)

The brief of 2026-11-16 reported two things about Damage Reports: the
console "sometimes behaves as if it has lost its internet connection",
with changes that only appear after a hard refresh; and the
classification and priority a requestor chooses must stay theirs when an
administrator reviews the report.

### What was actually wrong

Nothing failed to save. The live project's API log for 2026-11-16,
08:13 to 08:21 UTC, shows one administrator saving a classification six
times, moving a report's status six times and archiving five times.
Every call was answered `204`. None of it appeared on the page, and at
08:21:14 the page was reloaded.

The cause was in how every screen learned of a change. Each list and
each open record was a `SupabaseClient.stream()`: a first read, then
rows patched from Realtime events. Nothing read again after a save; the
page waited for the event. That stream ends for good in three ordinary
situations, and nothing reopened it:

| When | What the old stream did |
|---|---|
| **Signing out**, including the automatic one after 15 idle minutes (§37) | The app closes every Realtime channel at sign-out. Each stream closed with its channel. The providers holding them are kept for the life of the page, so after signing back in **in the same tab** every list already loaded still showed its old rows, and listened to nothing. This is what the log shows: the console, loaded at 07:37 and then left, signed in again at 08:13, and that sign-in read no report list at all |
| The server ending a channel (a token it found expired) | The same: closed, never reopened |
| **One failed read** when the channel rejoined | The stream closed itself ("no need to keep the realtime connection open") |

Two more faults came with it. A dropped socket was reported to the page
as `Cannot reach the server. Check your internet connection`, which is
the "lost its connection" the brief describes, on a working connection.
And a page patched from events depends on what each event carries and
on the order they arrive in; a read does not.

The 15-minute session limit shipped on 2026-11-15, which is why this
went from rare to daily.

### What changed

**Every live view is a query that is read again** when it may have
changed, never a list patched from events (`lib/core/data/live_sync.dart`,
`LiveSync`). It is read again:

- when a change is announced on the app's **one** Realtime channel (all
  of `public`, row level security deciding what reaches whom; it was one
  channel per list and per open record);
- **after every change the app itself makes**: a repository's function
  call returns only once the views on screen have been read again
  (`SupabaseRepository._settled`), so "saved" is said over a page that
  already shows it, with Realtime in any state at all;
- when the channel comes back, a few seconds after it joins (the server
  answers a join before its change stream is running, found against the
  local stack), on sign-in, when the connection returns, and when the
  tab or the app comes back to the front;
- on a timer, every 20 seconds, but only while the channel is down.

A channel that fails or is closed is replaced, at a growing interval,
for as long as someone is signed in; it is kept for ten seconds after
the last view goes, so a page replacing its views does not leave and
join again. A read that fails for a passing
reason keeps the rows on screen and is tried again; the offline banner,
which probes the API itself, is what says the connection is gone. Pages
out of sight read nothing until they are looked at again.

**Everything read for one sign-in is dropped at the next.** Every
repository provider watches `sessionScopeProvider` (the signed-in
account's id), so a sign-out or sign-in rebuilds every provider that
reads through one. This is also what keeps one account's lists out of
the next account's session on a shared computer.

**The report page answers every action** (`report_detail_screen.dart`,
`report_assessment_panel.dart`): the pressed button shows a spinner and
none can be pressed again until the database answers; "Review started",
"Report approved", "Report rejected" or "Classification and priority
saved" appears only then; a failure says why, leaves the page as the
database has it, and offers **Try again**. Nothing is shown as changed
before the database confirms it.

### The requestor's choices and the official values

The columns were already apart, and the brief's four names map onto
them:

| The brief | Column | Written by |
|---|---|---|
| Initial Classification | `requestor_category` | the requestor, at filing; never again |
| Initial Priority | `requestor_priority` | the requestor, at filing; never again |
| Official Classification | `category`, once an administrator has decided (`DamageReport.officialCategory`) | the review |
| Official Priority | `official_priority` | the review |
| System recommendation | `recommended_priority`, `priority_score` (§18's formula, unchanged) | the review, from the four ratings |

Before the review, `category` may hold the keyword classifier's match;
it is shown as "the keywords suggest", never as official.

What the migration `20261116115436_report_review_trail.sql` adds:

- **A trigger keeps the requestor's two values as filed.** No function
  changed them before; now none can, whoever writes one later.
- **`record_assessment` takes a reason** (optional, at most 500
  characters) and records the whole decision in its audit entry: what
  the requestor chose, the classification and official priority from
  and to, whether it was the first review, the reason, with the
  administrator's name and the time the trail always had.
- **A review is not saved over a newer one.** The console sends the
  report's `updated_at` as its page last read it; if the report has
  changed since, the save is refused with "Ana Reyes changed this report
  after you opened it here. The latest details are shown now: check
  them, then save again", and the page shows those details.
- **The same review sent twice is one decision**: nothing is written,
  and it succeeds. The six identical saves in the log would now be one
  audit entry.

On screen, the console's report page has one card with three groups:
**Requestor's submission** (initial classification and priority, marked
"Requestor-selected"), **Administrator's review** (official values,
"Administrator-confirmed", how they differ from the requestor's, or
"Awaiting administrative review"), and **System recommendation**
(the level and score). The history lists each review with what it
changed. The faculty and staff app's report page gains a "GSU's review"
card under "What you reported", from the same rule
(`DamageReport.officialCategory`), so the phone and the console agree.

### Deploying it

The database first, then the apps. The new console and phone app send
`reason` and `expected_updated_at`, which only the new function
accepts; the old console and the 1.2.0 app keep working against the new
function, which treats both as optional.

    npx supabase db push --remote --dry-run
    npx supabase db push --remote

### Not done

- A status move still relies on the lifecycle for conflicts (a move the
  report's current status does not allow is refused, by name), not on
  the version check.
- Reviews by two administrators with unsaved ratings: when the other's
  review arrives, the form is replaced by the saved values. Nothing is
  overwritten in the database, but the unsaved ratings are gone without
  a notice.
- The administrator's "recent activity" and the audit log page are still
  read once and on request, not live.
- One mistake of this change was caught by an existing test and is worth
  knowing about: the migrations' closing line, a grant on every function
  in `app`, would have handed the scheduler's `app.sweep_tool_requests`
  (§41) back to signed-in users. This migration grants its own two
  functions only; `tool_requests.test.sql` and
  `report_review_trail.test.sql` both check the sweep stays closed.
- `test/e2e/supabase_flows_test.dart` had stopped passing when the
  session limit shipped (§31): its tokens carried no `auth_time`, so
  seeded accounts counted as idle. It carries one now.

Tests: `unit/core/live_sync_test.dart` (24), `unit/core/live_wiring_test.dart`
(the sign-out and sign-in of the log, through the app's own providers),
`unit/repositories/live_views_test.dart` (6),
`unit/repositories/classification_review_test.dart`,
`unit/models/model_validation_test.dart`,
`widget/admin_report_detail_test.dart`, `widget/report_detail_test.dart`,
`supabase/tests/report_review_trail.test.sql` (29), and against the
local stack `e2e/live_views_e2e_test.dart` (3).
