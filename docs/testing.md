# Testing GSUhub

Objective 7.B: *conduct functionality and usability testing; identify and
fix bugs.* This document says what is tested, how, and where each
requirement of the manuscript (§1.5 and §3.4, "Requirements
Specification") is proven. The manuscript evaluates the system against
the ISO/IEC 25010 characteristics (functional suitability, performance
efficiency, usability, reliability, security, compatibility,
maintainability, portability); the automated tests cover what a machine
can check, and the usability checklist at the end is for the team's
sessions with real users.

## The test sets

| Set | Where | How to run | Last run |
|---|---|---|---|
| App: unit and widget | `test/unit`, `test/widget` | `flutter test --exclude-tags e2e` | 769 passed (2026-11-05) |
| App: end to end | `test/e2e` | local stack running, then `$env:SUPABASE_E2E='1'; flutter test test/e2e` | 3 passed |
| Database (pgTAP) | `supabase/tests` | `npx supabase test db` (Docker), or `cd tool/sql_tests; node run.mjs` and `node run.mjs --seed` (PGlite, no Docker) | 716 passed (2026-11-05), on Postgres 17 and in PGlite, empty and seeded |
| Photos (real uploads) | `tool/storage_api_test.mjs` | local stack running, `node tool/storage_api_test.mjs` | 14 checks passed |
| Token exchange | `supabase/functions/tests` | see `supabase/README.md` (Deno) | 25 passed |
| Data move | `tool/migrate/migrate.test.mjs` | `cd tool/migrate; npm test` | 8 passed |
| Release builds | `scripts/check_release_output.ps1` | after a release build: `-WebDir build\web` or `-Apk <file>` | passes |
| Static checks | the whole project | `flutter analyze`, `dart format --set-exit-if-changed lib test tool` | clean |

**The end-to-end flows** file a report with photos and a geo-tag, have an
administrator approve it while the requestor's screen watches it change,
then assign it, have the technician work it and submit the
accomplishment report, sign it off, and rate it — checking the audit
trail, the stock ledger and the technician's open-work count on the way.
Run them on a warm, idle machine. Flow 2 waits up to 30 seconds for
Realtime to bring the approval to the requestor's open stream, and it
has timed out in two situations: straight after `npx supabase db reset`,
while Realtime restarts, and while a release build was compiling beside
the Docker stack (2 of 9 runs on 2026-10-21). On an idle machine it
passed 5 runs out of 5. A screen opened in the same moment that its
report changes could miss that one update the same way, so it is worth
watching for in the usability sessions.

**Two backends in the tests.** The widget tests run the real screens
against an in-memory backend (`test/support/firestore_backend`, the
Firestore repositories the app used before Objective 1). What the
database itself does — who may read and change what, every function's
checks, the ledger, the notices — is proven by the pgTAP tests, and
`test/unit/repositories/supabase_contract_test.dart` checks that every
call the app makes names a database function that exists, with the
parameters it takes. The e2e flows join the two: the app's real
repositories against the real stack.

## Requirements and the tests that prove them

### Faculty and staff (mobile)

| Requirement (manuscript §3.4) | Tests |
|---|---|
| Register and log in | `widget/requestor_auth_test.dart`, `unit/presentation/sign_up_controller_test.dart`; `account_functions.test.sql` (signing up files a pending profile under the signed-in email); the token exchange's tests |
| Submit a report with description, photos, location and geo-tag | `widget/submit_report_screen_test.dart`, `unit/presentation/report_form_controller_test.dart`, `unit/repositories/report_submission_test.dart`; `report_functions.test.sql`; `storage_policies.test.sql`, `tool/storage_api_test.mjs`; e2e flow 1 |
| Scan a QR code to fill in the facility or asset | `unit/facilities/qr_lookup_test.dart`, `widget/submit_report_screen_test.dart` |
| See the classified damage type and the priority | `widget/report_detail_test.dart`, `unit/presentation/report_pills_test.dart` |
| Track the status in real time | `widget/report_detail_test.dart`, `unit/presentation/report_timeline_test.dart`; e2e flow 2 (the approval reaches the requestor's open stream) |
| Notifications for acknowledgment, assignment, status and completion | `widget/alerts_test.dart`, `widget/push_test.dart`, `unit/notifications/report_notice_test.dart`; `report_functions.test.sql`, `work_order_functions.test.sql`. A phone with the app fully closed: **blocked**, see below |
| See earlier reports and their history | `widget/requestor_app_test.dart`, `unit/presentation/my_reports_test.dart`, `unit/repositories/my_reports_query_test.dart` |
| Rate the service | `widget/rate_service_test.dart`, `unit/repositories/rating_test.dart`; `feedback_notification_config.test.sql`; e2e flow 3 |

### GSU administrator (web)

| Requirement | Tests |
|---|---|
| Log in with an administrator account | `widget/login_screen_test.dart`, `unit/routing/route_guard_test.dart`, `unit/core/app_router_test.dart` |
| View and manage every report | `widget/reports_screen_test.dart`, `widget/admin_report_detail_test.dart`, `widget/dashboard_screen_test.dart`, `widget/dashboard_links_test.dart` |
| See the classification and the system's priority | `unit/classification/keyword_classifier_test.dart`, `unit/classification/priority_scorer_test.dart`, `widget/admin_report_detail_test.dart` |
| Change priorities and assignments | `widget/admin_report_detail_test.dart` (the official priority); `reassign_work_order.test.sql`, `widget/work_order_detail_test.dart` (reassigning, 7.A) |
| Detect, review, merge or dismiss duplicates | `unit/classification/duplicate_detector_test.dart`, `unit/repositories/classification_review_test.dart`; `report_functions.test.sql` |
| Assign by specialization and workload | `widget/task_assignment_test.dart`; `work_order_functions.test.sql` |
| Monitor progress and update work-order statuses | `widget/work_orders_screen_test.dart`, `widget/work_order_detail_test.dart` (the board cannot skip the sign-off, 7.B); `work_order_functions.test.sql`, `accomplishment_functions.test.sql` |
| Accomplishment reports and maintenance summaries | `widget/analytics_screen_test.dart`, `unit/presentation/analytics_export_test.dart`, `unit/presentation/analytics_summary_test.dart`, `widget/analytics_inventory_test.dart` |
| Accounts, roles, permissions, notifications, inventory, QR codes | `widget/user_accounts_screen_test.dart`, `unit/repositories/user_accounts_test.dart`; `account_functions.test.sql`; `widget/admin_notifications_test.dart`, `admin_notifications.test.sql` (7.A); `widget/inventory_screen_test.dart`, `inventory_functions.test.sql`; `widget/facilities_screen_test.dart`, `facility_functions.test.sql` |
| Delete a material, keeping its history (2026-11-05) | `material_delete.test.sql` (refused while open work counts on it; nothing new happens to it; its code is free), `unit/repositories/inventory_deleted_test.dart`, `widget/inventory_screen_test.dart` |
| Priority weights and duplicate rules (configurable, flagged) | `widget/settings_screen_test.dart`; `feedback_notification_config.test.sql` (the database refuses what the console would) |

### Maintenance personnel (mobile)

| Requirement | Tests |
|---|---|
| Log in | `unit/routing/route_guard_test.dart` (one sign-in page for the phone; a technician's role opens the personnel app), `widget/personnel_app_test.dart` |
| Notified of work and tasks assigned | `work_order_functions.test.sql`, `task_functions.test.sql`, `reassign_work_order.test.sql`; `widget/work_order_detail_test.dart` |
| See assigned work orders and the day's tasks | `widget/personnel_app_test.dart`, `unit/personnel/task_day_test.dart` |
| Scan a QR code to reach a room or asset and its work | `unit/personnel/scan_resolver_test.dart`, `widget/personnel_app_test.dart` |
| Update task and work-order status | `unit/repositories/personnel_work_test.dart`; `task_functions.test.sql`, `work_order_functions.test.sql` |
| Completion notes and photos | `widget/personnel_app_test.dart`; `accomplishment_functions.test.sql`; e2e flow 3 |
| Request and monitor materials | `widget/material_requests_test.dart`; `material_functions.test.sql` |
| See accomplishment reports | `widget/personnel_app_test.dart` (the filed report and where its review stands, 7.B) |
| Scan materials to record their use | `widget/personnel_app_test.dart`; `material_functions.test.sql` |

### Across the system (§1.5 core functionalities, non-functional requirements)

| Requirement | Tests |
|---|---|
| Stock deducted only after the accomplishment report, and only through the ledger | `stock_ledger.test.sql`, `accomplishment_functions.test.sql`, `unit/repositories/inventory_management_test.dart`; e2e flow 3 |
| Tool borrowing, return, condition and accountability | `tool_functions.test.sql`, `widget/personnel_app_test.dart`, `widget/inventory_screen_test.dart` |
| Automatic low-stock alerts | `widget/inventory_screen_test.dart` (on screen); `admin_notifications.test.sql` (the notice) |
| Security: authentication and role-based access | `permission_matrix.test.sql` (every role, every table), `function_privileges.test.sql`, `storage_policies.test.sql`, the token exchange's tests, `unit/routing/route_guard_test.dart` |
| Auditability | the audit assertions in every `*_functions.test.sql` |
| Reliability: a refused change leaves nothing half-done | the refusal tests in `report_functions.test.sql` and `accomplishment_functions.test.sql` (a refused call changes nothing; a repeated one deducts nothing twice); `stock_ledger.test.sql` (the ledger and the audit trail cannot be edited) |
| Portability: Android 8.0 and up | `minSdk 26` (`android/app/build.gradle.kts`); a phone test is the team's (below) |

## What cannot be proven here

- **Push to a phone with the app fully closed** needs a server to send it:
  Cloud Functions, on the Blaze plan. Not built, by the brief's rule
  against workarounds for Blaze-only features. The Alerts tab and its
  badge update live, and the app shows a notification itself while it
  is open or recently in the background.
- **A real phone**: the camera, GPS, QR scanning and notifications on an
  Android 8.0+ device. The APK builds (`scripts/build_apk.ps1`); trying
  it on phones is the team's.
- **Real users**: below.

## Usability testing (the team's)

Run each task with two or three people per role, on the deployed console
and an installed APK. Note whether they finish it unaided, how long it
takes, and where they hesitate. Then have them rate the system on the
characteristics the manuscript evaluates (ISO/IEC 25010: functional
suitability, performance efficiency, usability, reliability, security,
compatibility, maintainability, portability). The manuscript names the
characteristics but not a questionnaire; preparing one, and having the
adviser approve it, is the team's.

**Faculty and staff**

1. Sign up, then sign in once an administrator has approved the account.
2. Report a damaged item: a photo, the room by scanning its QR label, a
   description, and the urgency.
3. Find the report again and say what is happening to it now.
4. When the work is done, rate it.

**Maintenance personnel**

1. Sign in and say what today's tasks are.
2. Start a work order, tick off a task with a proof photo.
3. Scan a material's label and record using two of them.
4. Borrow a tool by scanning it, and return it.
5. Submit the accomplishment report with notes and photos.

**Administrator**

1. Find the newest report, review it (damage type, the four ratings,
   the official priority) and approve it.
2. Assign it to the right technician; later, hand it to another one.
3. From the notifications, open the work waiting for sign-off, and sign
   it off or send it back.
4. Record a delivery for a material that is low, and print its label.
5. Approve a pending sign-up.
6. Export the month's report data.

Findings go to the issue list; the GUI pass (after Objective 7) takes the
look-and-feel ones.
