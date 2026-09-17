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

**Emulator mode is opt-in, and visible.** 1.A had
`useFirestoreEmulator: Env.isDevelopment`, which would silently route
every debug build at emulators. Now it requires
`--dart-define=USE_EMULATOR=true`, and when active the app shows an orange
EMULATOR banner. Both failure modes this prevents are bad: trusting
seeded test data as real, and writing test records into the live project
during a demo.

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
