# GSUhub Code Guide

Where each part of GSUhub is implemented. Use it to find the code behind
any feature, screen or rule. Every path is a link: in VS Code, Ctrl+click
opens the file.

GSUhub is one Flutter codebase that builds three apps:

| App | Used by | Runs on | Its pages start with | Its frame (layout) |
|---|---|---|---|---|
| Admin console | GSU administrators | Web browser | `/admin/` | [`lib/shells/admin/`](lib/shells/admin/) |
| Faculty and staff app | Faculty and staff who report damage | Android | `/staff/` | [`lib/shells/requestor/`](lib/shells/requestor/) |
| Maintenance app | GSU maintenance personnel | Android | `/personnel/` | [`lib/shells/personnel/`](lib/shells/personnel/) |

The two phone apps are one APK. The account's role decides which app
opens after sign-in.

---

## How every feature is built

Each feature folder in [`lib/features/`](lib/features/) follows the same
path from screen to database:

```
Screen                lib/features/<feature>/presentation/      what the user sees and taps
  │ calls
Controller/provider   lib/features/<feature>/presentation/      holds the state, checks the input
  │ calls
Repository            lib/features/<feature>/data/repositories/<name>_repository_impl.dart
  │ calls a database function, or reads a table
Database              supabase/migrations/                      tables, access rules, one function per write
  ✓ checked by        supabase/tests/                           a test file per group of functions
```

- **Screens never talk to the database directly.** They go through a
  repository, so the database could be swapped without touching a screen.
  The rule is stated in
  [`docs/architecture_decisions.md`](docs/architecture_decisions.md)
  ("Shared Backend Contract").
- **Every change to the data is a database function.** It checks who is
  asking and whether the change is allowed, so the same rules hold for the
  web and both phone apps.
- Inside a feature: `data/models/` holds the record types (one per table),
  `data/repositories/` holds the contract (`*_repository.dart`) and its
  Supabase implementation (`*_repository_impl.dart`), `domain/` holds pure
  logic with no screen and no database (for example the keyword
  classifier), and `presentation/` holds screens, dialogs and their
  controllers.

---

## Quick reference

| System feature | Folder | Start here |
|---|---|---|
| Login, sign-up and access control | [`lib/features/auth/`](lib/features/auth/) | [`admin_login_screen.dart`](lib/features/auth/presentation/admin_login_screen.dart), [`mobile_login_screen.dart`](lib/features/auth/presentation/mobile_login_screen.dart) |
| Dashboard | [`lib/features/dashboard/`](lib/features/dashboard/) | [`dashboard_screen.dart`](lib/features/dashboard/presentation/dashboard_screen.dart) |
| Analytics and data export | [`lib/features/analytics/`](lib/features/analytics/) | [`analytics_screen.dart`](lib/features/analytics/presentation/analytics_screen.dart) |
| User management | [`lib/features/user_management/`](lib/features/user_management/) | [`user_accounts_screen.dart`](lib/features/user_management/presentation/user_accounts_screen.dart) |
| Facility and asset (equipment) management | [`lib/features/facilities/`](lib/features/facilities/) | [`facilities_screen.dart`](lib/features/facilities/presentation/facilities_screen.dart) |
| Damage reporting | [`lib/features/damage_reports/`](lib/features/damage_reports/) | [`submit_report_screen.dart`](lib/features/damage_reports/presentation/submission/submit_report_screen.dart), [`reports_screen.dart`](lib/features/damage_reports/presentation/reports_screen.dart) |
| Classification, priority and duplicates | [`lib/features/classification/`](lib/features/classification/) | [`keyword_classifier.dart`](lib/features/classification/domain/keyword_classifier.dart), [`priority_scorer.dart`](lib/features/classification/domain/priority_scorer.dart) |
| Maintenance management (work orders) | [`lib/features/work_orders/`](lib/features/work_orders/) | [`work_orders_screen.dart`](lib/features/work_orders/presentation/work_orders_screen.dart) |
| Daily tasks | [`lib/features/tasks/`](lib/features/tasks/) | [`personnel_tasks_screen.dart`](lib/features/tasks/presentation/personnel_tasks_screen.dart) |
| Accomplishment reports and materials used | [`lib/features/accomplishment/`](lib/features/accomplishment/) | [`material_sheets.dart`](lib/features/accomplishment/presentation/material_sheets.dart) |
| Inventory (materials and stock) | [`lib/features/inventory/`](lib/features/inventory/) | [`inventory_screen.dart`](lib/features/inventory/presentation/inventory_screen.dart) |
| Tools management | [`lib/features/tools/`](lib/features/tools/) | [`tools_section.dart`](lib/features/tools/presentation/tools_section.dart) |
| QR codes (generating and scanning) | [`lib/features/qr_codes/`](lib/features/qr_codes/) | [`qr_label_actions.dart`](lib/features/qr_codes/presentation/qr_label_actions.dart), [`qr_scanner_screen.dart`](lib/features/qr_codes/presentation/qr_scanner_screen.dart) |
| Map View and geo-tagging | [`lib/features/map_view/`](lib/features/map_view/) | [`report_map_screen.dart`](lib/features/map_view/presentation/report_map_screen.dart) |
| Notifications | [`lib/features/notifications/`](lib/features/notifications/) | [`admin_notifications_screen.dart`](lib/features/notifications/presentation/admin_notifications_screen.dart), [`mobile_alerts_screen.dart`](lib/features/notifications/presentation/mobile_alerts_screen.dart) |
| Feedback and ratings | [`lib/features/feedback/`](lib/features/feedback/) | [`rate_service_screen.dart`](lib/features/feedback/presentation/rate_service_screen.dart) |
| Settings | [`lib/features/settings/`](lib/features/settings/) | [`settings_screen.dart`](lib/features/settings/presentation/settings_screen.dart) |
| Audit trail | [`lib/features/audit/`](lib/features/audit/) | [`audit_log_repository_impl.dart`](lib/features/audit/data/repositories/audit_log_repository_impl.dart) |
| Shared components | [`lib/core/widgets/`](lib/core/widgets/) | see [Shared code](#shared-code) |
| Layouts (sidebar, header, bottom bars) | [`lib/shells/`](lib/shells/) | [`admin_shell.dart`](lib/shells/admin/admin_shell.dart) |
| Every page's URL | [`lib/core/routing/`](lib/core/routing/) | [`app_router.dart`](lib/core/routing/app_router.dart) |
| Database and API | [`supabase/`](supabase/), [`lib/core/data/`](lib/core/data/), [`lib/core/services/`](lib/core/services/) | see [Database and API](#database-and-api) |

---

## Feature by feature

### Login, sign-up and access control

| What | Where |
|---|---|
| Admin login page | [`lib/features/auth/presentation/admin_login_screen.dart`](lib/features/auth/presentation/admin_login_screen.dart) |
| Phone sign-in (faculty, staff and maintenance personnel) | [`lib/features/auth/presentation/mobile_login_screen.dart`](lib/features/auth/presentation/mobile_login_screen.dart) |
| Faculty and staff sign-up (waits for approval) | [`requestor_sign_up_screen.dart`](lib/features/auth/presentation/requestor_sign_up_screen.dart), [`sign_up_controller.dart`](lib/features/auth/presentation/sign_up_controller.dart) |
| Sign-in logic and form state | [`lib/features/auth/presentation/auth_controller.dart`](lib/features/auth/presentation/auth_controller.dart) |
| Firebase Authentication (email and password) | [`lib/core/services/firebase/firebase_auth_service.dart`](lib/core/services/firebase/firebase_auth_service.dart), contract [`auth_service.dart`](lib/core/services/auth_service.dart) |
| Trading the Firebase sign-in for a database token | [`supabase/functions/firebase-token-exchange/handler.ts`](supabase/functions/firebase-token-exchange/handler.ts), [`lib/core/services/supabase/supabase_session.dart`](lib/core/services/supabase/supabase_session.dart) |
| Who may open which page (role-based access) | [`lib/core/routing/route_guards.dart`](lib/core/routing/route_guards.dart) |
| Who may read and change what in the database | [`20261016130001_access_helpers.sql`](supabase/migrations/20261016130001_access_helpers.sql), [`20261016130005_row_level_security.sql`](supabase/migrations/20261016130005_row_level_security.sql); tested in [`permission_matrix.test.sql`](supabase/tests/permission_matrix.test.sql) |
| Administrator creates accounts for others | [`firebase_account_provisioning_service.dart`](lib/core/services/firebase/firebase_account_provisioning_service.dart), database `create_account` in [`20261016145429_account_functions.sql`](supabase/migrations/20261016145429_account_functions.sql) |
| Logout (asks first) | [`lib/core/widgets/sign_out_dialog.dart`](lib/core/widgets/sign_out_dialog.dart); console menu [`admin_profile_menu.dart`](lib/shells/admin/widgets/admin_profile_menu.dart); phone [`mobile_profile_screen.dart`](lib/features/user_management/presentation/mobile_profile_screen.dart) |

### Dashboards and analytics

| What | Where |
|---|---|
| Admin dashboard (stat cards, recent reports, chart, activity) | [`dashboard_screen.dart`](lib/features/dashboard/presentation/dashboard_screen.dart), [`dashboard_providers.dart`](lib/features/dashboard/presentation/dashboard_providers.dart), [`widgets/`](lib/features/dashboard/presentation/widgets/) |
| Faculty and staff home | [`requestor_home_screen.dart`](lib/features/dashboard/presentation/requestor_home_screen.dart) |
| Maintenance personnel home | [`personnel_home_screen.dart`](lib/features/dashboard/presentation/personnel_home_screen.dart) |
| Analytics page | [`analytics_screen.dart`](lib/features/analytics/presentation/analytics_screen.dart), charts in [`widgets/`](lib/features/analytics/presentation/widgets/) |
| Export Data (CSV) | [`analytics_export.dart`](lib/features/analytics/presentation/analytics_export.dart) |
| Most used materials | [`inventory_usage.dart`](lib/features/analytics/presentation/inventory_usage.dart), [`widgets/inventory_section.dart`](lib/features/analytics/presentation/widgets/inventory_section.dart) |

### User management and profiles

| What | Where |
|---|---|
| User Accounts page (approve sign-ups, roles, activate, deactivate, delete) | [`user_accounts_screen.dart`](lib/features/user_management/presentation/user_accounts_screen.dart), [`widgets/account_dialogs.dart`](lib/features/user_management/presentation/widgets/account_dialogs.dart), [`account_controller.dart`](lib/features/user_management/presentation/account_controller.dart) |
| Maintenance Personnel directory | [`personnel_screen.dart`](lib/features/user_management/presentation/personnel_screen.dart) |
| My Profile (console) and Profile tab (phones) | [`admin_profile_screen.dart`](lib/features/user_management/presentation/admin_profile_screen.dart), [`mobile_profile_screen.dart`](lib/features/user_management/presentation/mobile_profile_screen.dart), [`widgets/profile_cards.dart`](lib/features/user_management/presentation/widgets/profile_cards.dart) |
| The account record | [`data/models/app_user.dart`](lib/features/user_management/data/models/app_user.dart), [`data/repositories/user_repository_impl.dart`](lib/features/user_management/data/repositories/user_repository_impl.dart) |
| Database | `create_account`, `register_self`, `set_account_status`, `update_account` in [`20261016145429_account_functions.sql`](supabase/migrations/20261016145429_account_functions.sql); `delete_account` in [`20261108141827_console_delete_and_archive.sql`](supabase/migrations/20261108141827_console_delete_and_archive.sql) |

### Facilities and equipment (assets)

Rooms are facilities; equipment installed in a room is an asset. Both
live in one feature.

| What | Where |
|---|---|
| Facilities & Equipment page (rooms, equipment, labels, delete) | [`lib/features/facilities/presentation/facilities_screen.dart`](lib/features/facilities/presentation/facilities_screen.dart) |
| Building and room lists for the report form | [`facility_directory.dart`](lib/features/facilities/presentation/facility_directory.dart) |
| The records | [`facility.dart`](lib/features/facilities/data/models/facility.dart), [`asset.dart`](lib/features/facilities/data/models/asset.dart), [`facility_repository_impl.dart`](lib/features/facilities/data/repositories/facility_repository_impl.dart) |
| Database | [`20261016145439_facility_functions.sql`](supabase/migrations/20261016145439_facility_functions.sql); `delete_facility`, `delete_asset` in [`20261108141827_console_delete_and_archive.sql`](supabase/migrations/20261108141827_console_delete_and_archive.sql) |

### Damage reporting

| What | Where |
|---|---|
| Report form (faculty and staff app) | [`submission/submit_report_screen.dart`](lib/features/damage_reports/presentation/submission/submit_report_screen.dart), [`submission/report_form_controller.dart`](lib/features/damage_reports/presentation/submission/report_form_controller.dart) |
| Building, room and GPS on the form | [`submission/widgets/location_card.dart`](lib/features/damage_reports/presentation/submission/widgets/location_card.dart) |
| Photo evidence | [`submission/widgets/photo_evidence_card.dart`](lib/features/damage_reports/presentation/submission/widgets/photo_evidence_card.dart); upload in [`supabase_storage_service.dart`](lib/core/services/supabase/supabase_storage_service.dart) |
| My Reports and live tracking (faculty and staff) | [`my_reports/my_reports_screen.dart`](lib/features/damage_reports/presentation/my_reports/my_reports_screen.dart), [`my_reports/my_report_detail_screen.dart`](lib/features/damage_reports/presentation/my_reports/my_report_detail_screen.dart), [`my_reports/report_timeline.dart`](lib/features/damage_reports/presentation/my_reports/report_timeline.dart) |
| Damage Reports page (admin list, filters, archive) | [`reports_screen.dart`](lib/features/damage_reports/presentation/reports_screen.dart), [`widgets/report_filter_bar.dart`](lib/features/damage_reports/presentation/widgets/report_filter_bar.dart), [`widgets/report_archive.dart`](lib/features/damage_reports/presentation/widgets/report_archive.dart) |
| One report in the console (review, approve, reject) | [`report_detail_screen.dart`](lib/features/damage_reports/presentation/report_detail_screen.dart), [`report_review_controller.dart`](lib/features/damage_reports/presentation/report_review_controller.dart) |
| The report record and its status steps | [`damage_report.dart`](lib/features/damage_reports/data/models/damage_report.dart), [`status_change.dart`](lib/features/damage_reports/data/models/status_change.dart), [`damage_report_repository_impl.dart`](lib/features/damage_reports/data/repositories/damage_report_repository_impl.dart) |
| The report lifecycle (Pending → Closed) | [`lib/core/enums/report_status.dart`](lib/core/enums/report_status.dart) |
| Database | `submit_report`, `transition_report`, `record_assessment`, `merge_duplicates`, `keep_separate` in [`20261016145448_report_functions.sql`](supabase/migrations/20261016145448_report_functions.sql); `set_report_archived` in [`20261108141827_console_delete_and_archive.sql`](supabase/migrations/20261108141827_console_delete_and_archive.sql) |

### Classification, priority and duplicates (rule-based)

| What | Where |
|---|---|
| Keyword classification (runs as a report is filed) | [`domain/keyword_classifier.dart`](lib/features/classification/domain/keyword_classifier.dart), called from [`report_form_controller.dart`](lib/features/damage_reports/presentation/submission/report_form_controller.dart) |
| Weighted priority score and its levels | [`domain/priority_scorer.dart`](lib/features/classification/domain/priority_scorer.dart) |
| Duplicate detection | [`domain/duplicate_detector.dart`](lib/features/classification/domain/duplicate_detector.dart), shown in [`possible_duplicates_card.dart`](lib/features/classification/presentation/possible_duplicates_card.dart) |
| Admin confirms the type, rates the four criteria, sets the official priority | [`report_assessment_panel.dart`](lib/features/classification/presentation/report_assessment_panel.dart) |
| The rules' saved settings | [`config_repository_impl.dart`](lib/features/classification/data/repositories/config_repository_impl.dart); database `update_config` in [`20261016145508_feedback_notification_config_functions.sql`](supabase/migrations/20261016145508_feedback_notification_config_functions.sql) and its checks in [`20261020111849_config_validation.sql`](supabase/migrations/20261020111849_config_validation.sql) |

### Maintenance management: assignment, work orders, tasks, accomplishment reports

| What | Where |
|---|---|
| Task Assignment (turn an approved report into a work order) | [`task_assignment_screen.dart`](lib/features/work_orders/presentation/task_assignment_screen.dart), [`assignment_controller.dart`](lib/features/work_orders/presentation/assignment_controller.dart) |
| Work Order Management (table and Kanban board) | [`work_orders_screen.dart`](lib/features/work_orders/presentation/work_orders_screen.dart), [`widgets/kanban_board.dart`](lib/features/work_orders/presentation/widgets/kanban_board.dart), [`work_order_controller.dart`](lib/features/work_orders/presentation/work_order_controller.dart) |
| One work order in the console (tasks, reassign, sign-off) | [`work_order_detail_screen.dart`](lib/features/work_orders/presentation/work_order_detail_screen.dart), [`work_order_detail_controller.dart`](lib/features/work_orders/presentation/work_order_detail_controller.dart) |
| The technician's work orders and one work order (start, tasks, accomplishment report) | [`personnel/my_work_orders_screen.dart`](lib/features/work_orders/presentation/personnel/my_work_orders_screen.dart), [`personnel/personnel_work_order_screen.dart`](lib/features/work_orders/presentation/personnel/personnel_work_order_screen.dart), [`personnel/personnel_work_controller.dart`](lib/features/work_orders/presentation/personnel/personnel_work_controller.dart) |
| Daily tasks (Tasks tab, ticking a task with proof) | [`lib/features/tasks/presentation/personnel_tasks_screen.dart`](lib/features/tasks/presentation/personnel_tasks_screen.dart), [`widgets/task_tiles.dart`](lib/features/tasks/presentation/widgets/task_tiles.dart), [`domain/task_day.dart`](lib/features/tasks/domain/task_day.dart) |
| Accomplishment reports and materials used on a job | [`lib/features/accomplishment/`](lib/features/accomplishment/): [`material_sheets.dart`](lib/features/accomplishment/presentation/material_sheets.dart), [`personnel_materials_screen.dart`](lib/features/accomplishment/presentation/personnel_materials_screen.dart), [`accomplishment_report_repository_impl.dart`](lib/features/accomplishment/data/repositories/accomplishment_report_repository_impl.dart) |
| The work order lifecycle (Pending → Completed) | [`lib/core/enums/work_order_status.dart`](lib/core/enums/work_order_status.dart) |
| Database | `assign_work_order`, `set_work_order_status` in [`20261016145458_work_order_functions.sql`](supabase/migrations/20261016145458_work_order_functions.sql); [`20261020111843_reassign_work_order.sql`](supabase/migrations/20261020111843_reassign_work_order.sql); the sign-off rule in [`20261020111846_work_order_signoff.sql`](supabase/migrations/20261020111846_work_order_signoff.sql); tasks in [`20261017065945_task_functions.sql`](supabase/migrations/20261017065945_task_functions.sql); `submit_accomplishment`, `review_accomplishment` in [`20261017065951_accomplishment_functions.sql`](supabase/migrations/20261017065951_accomplishment_functions.sql) |

### Inventory (materials and stock)

| What | Where |
|---|---|
| Inventory Management page (stock cards, requests, materials; hosts the tools table) | [`lib/features/inventory/presentation/inventory_screen.dart`](lib/features/inventory/presentation/inventory_screen.dart) |
| Material dialogs (add, edit, delivery, stock count, history, delete) | [`widgets/material_dialogs.dart`](lib/features/inventory/presentation/widgets/material_dialogs.dart) |
| Technicians' material requests and GSU's answers | [`personnel/material_request_screen.dart`](lib/features/inventory/presentation/personnel/material_request_screen.dart), [`widgets/request_review.dart`](lib/features/inventory/presentation/widgets/request_review.dart) |
| Low-stock alert | `lowStockCountProvider` in [`inventory_providers.dart`](lib/features/inventory/presentation/inventory_providers.dart); the administrator's notice in [`20261020111840_admin_notifications.sql`](supabase/migrations/20261020111840_admin_notifications.sql) |
| Database | [`20261017065959_inventory_functions.sql`](supabase/migrations/20261017065959_inventory_functions.sql), [`20261017065955_material_functions.sql`](supabase/migrations/20261017065955_material_functions.sql); the stock ledger that moves stock in [`20261016130009_stock_ledger.sql`](supabase/migrations/20261016130009_stock_ledger.sql); [`20261105104825_delete_material.sql`](supabase/migrations/20261105104825_delete_material.sql) |

### Tools

| What | Where |
|---|---|
| Tool Assets & Tracking table (on the Inventory page) and Scan QR | [`lib/features/tools/presentation/tools_section.dart`](lib/features/tools/presentation/tools_section.dart) |
| Tool dialogs (add, edit, check out, check in, repair, retire, details, delete) | [`widgets/tool_dialogs.dart`](lib/features/tools/presentation/widgets/tool_dialogs.dart) |
| What the tool screens read | [`tool_providers.dart`](lib/features/tools/presentation/tool_providers.dart) |
| Borrowing and returning from the maintenance app | [`tool_sheets.dart`](lib/features/tools/presentation/tool_sheets.dart) |
| The records | [`tool.dart`](lib/features/tools/data/models/tool.dart), [`tool_loan.dart`](lib/features/tools/data/models/tool_loan.dart), [`tool_repository_impl.dart`](lib/features/tools/data/repositories/tool_repository_impl.dart) |
| Database | `borrow_tool`, `return_tool`, `create_tool`, `update_tool`, `set_tool_status` in [`20261017070003_tool_functions.sql`](supabase/migrations/20261017070003_tool_functions.sql); `delete_tool` in [`20261108141827_console_delete_and_archive.sql`](supabase/migrations/20261108141827_console_delete_and_archive.sql) |

### QR codes: generating and scanning

| What | Where |
|---|---|
| A label's contents (code and two lines of text) | [`presentation/qr_label.dart`](lib/features/qr_codes/presentation/qr_label.dart) |
| Printable A4 sheet of labels (PDF) | [`presentation/qr_label_sheet.dart`](lib/features/qr_codes/presentation/qr_label_sheet.dart) |
| QR label dialog and Download | [`presentation/qr_label_actions.dart`](lib/features/qr_codes/presentation/qr_label_actions.dart) |
| The camera scanner and the three ways it opens (report form, maintenance app, console) | [`presentation/qr_scanner_screen.dart`](lib/features/qr_codes/presentation/qr_scanner_screen.dart) |
| What a scanned code is: material, tool, room or equipment | [`domain/personnel_scan_resolver.dart`](lib/features/qr_codes/domain/personnel_scan_resolver.dart) |
| A room's or equipment's code, for the report form | [`domain/qr_lookup.dart`](lib/features/qr_codes/domain/qr_lookup.dart) |
| The maintenance app's scan result (record use, borrow, return) | [`presentation/scan_result_screen.dart`](lib/features/qr_codes/presentation/scan_result_screen.dart) |

Each record's code is stored with it (`qr_code` on materials, tools,
rooms and equipment) and is unique; see
[`20261016125957_tables.sql`](supabase/migrations/20261016125957_tables.sql).

### Map View and geo-tagging

| What | Where |
|---|---|
| Map View page (admin) | [`report_map_screen.dart`](lib/features/map_view/presentation/report_map_screen.dart) |
| The map and its pins | [`report_map.dart`](lib/features/map_view/presentation/report_map.dart) |
| Which reports are on the map | [`report_map_providers.dart`](lib/features/map_view/presentation/report_map_providers.dart) |
| Map tiles, the form's geo-tag preview and the pin picker | [`widgets/geo_tag_map.dart`](lib/features/map_view/presentation/widgets/geo_tag_map.dart) |
| Reading the phone's GPS | [`lib/core/services/device/geolocator_location_service.dart`](lib/core/services/device/geolocator_location_service.dart) |
| "Campus View" preview on the Damage Reports page | [`report_side_panels.dart`](lib/features/damage_reports/presentation/widgets/report_side_panels.dart) |

### Notifications

| What | Where |
|---|---|
| Notifications page (admin) | [`admin_notifications_screen.dart`](lib/features/notifications/presentation/admin_notifications_screen.dart) |
| Alerts tab (both phone apps) | [`mobile_alerts_screen.dart`](lib/features/notifications/presentation/mobile_alerts_screen.dart) |
| Push notifications on the phone | [`push_coordinator.dart`](lib/features/notifications/presentation/push_coordinator.dart), [`fcm_notification_service.dart`](lib/core/services/firebase/fcm_notification_service.dart) |
| The wording of each notice | [`report_notice.dart`](lib/features/notifications/data/models/report_notice.dart) (faculty and staff), [`personnel_notice.dart`](lib/features/notifications/data/models/personnel_notice.dart) (maintenance) |
| Database (notices are written by the database as records change) | `app.notify` in [`20261016145419_server_helpers.sql`](supabase/migrations/20261016145419_server_helpers.sql); the administrator's notices in [`20261020111840_admin_notifications.sql`](supabase/migrations/20261020111840_admin_notifications.sql) |

### Feedback and ratings

| What | Where |
|---|---|
| Rating a finished job (three ratings; closes the report) | [`rate_service_screen.dart`](lib/features/feedback/presentation/rate_service_screen.dart), [`rating_controller.dart`](lib/features/feedback/presentation/rating_controller.dart), [`widgets/star_rating.dart`](lib/features/feedback/presentation/widgets/star_rating.dart) |
| Database | `rate_service` in [`20261016145508_feedback_notification_config_functions.sql`](supabase/migrations/20261016145508_feedback_notification_config_functions.sql) |

### Settings

| What | Where |
|---|---|
| The page and its three tabs | [`lib/features/settings/presentation/settings_screen.dart`](lib/features/settings/presentation/settings_screen.dart), [`widgets/settings_parts.dart`](lib/features/settings/presentation/widgets/settings_parts.dart) |
| Keywords tab | [`keyword_settings_section.dart`](lib/features/classification/presentation/keyword_settings_section.dart) |
| Priority scoring and Duplicate detection tabs | [`scoring_settings_section.dart`](lib/features/classification/presentation/scoring_settings_section.dart) |

### Audit trail

Every change made through a database function is recorded by `app.audit`
in [`20261016145419_server_helpers.sql`](supabase/migrations/20261016145419_server_helpers.sql).
The records can only be added to, never changed or deleted. The app's
side: [`lib/features/audit/`](lib/features/audit/).

---

## Following one damage report through the code

The flow to walk through during a demonstration, with the code at each
step.

1. **Faculty member files a report** on the phone:
   [`submit_report_screen.dart`](lib/features/damage_reports/presentation/submission/submit_report_screen.dart).
   The controller
   ([`report_form_controller.dart`](lib/features/damage_reports/presentation/submission/report_form_controller.dart))
   uploads the photos, reads the GPS, runs the keyword classifier
   ([`keyword_classifier.dart`](lib/features/classification/domain/keyword_classifier.dart)),
   and saves through
   [`damage_report_repository_impl.dart`](lib/features/damage_reports/data/repositories/damage_report_repository_impl.dart)
   to the database function `submit_report`.
2. **The administrator is notified** by the database
   ([`20261020111840_admin_notifications.sql`](supabase/migrations/20261020111840_admin_notifications.sql))
   and opens the report:
   [`report_detail_screen.dart`](lib/features/damage_reports/presentation/report_detail_screen.dart).
3. **The administrator reviews it**: confirms the damage type, rates the
   four criteria, sees the computed score
   ([`priority_scorer.dart`](lib/features/classification/domain/priority_scorer.dart)),
   sets the official priority
   ([`report_assessment_panel.dart`](lib/features/classification/presentation/report_assessment_panel.dart)),
   handles any possible duplicate, and approves or rejects.
4. **The administrator assigns it** to a technician:
   [`task_assignment_screen.dart`](lib/features/work_orders/presentation/task_assignment_screen.dart),
   database `assign_work_order`.
5. **The technician does the work** in the maintenance app:
   [`personnel_work_order_screen.dart`](lib/features/work_orders/presentation/personnel/personnel_work_order_screen.dart).
   Starts it, ticks tasks with proof photos, borrows tools
   ([`tool_sheets.dart`](lib/features/tools/presentation/tool_sheets.dart)),
   records materials
   ([`material_sheets.dart`](lib/features/accomplishment/presentation/material_sheets.dart)),
   and sends the accomplishment report.
6. **The administrator signs off**:
   [`work_order_detail_screen.dart`](lib/features/work_orders/presentation/work_order_detail_screen.dart),
   database `review_accomplishment`. The materials used are taken out of
   stock by the stock ledger
   ([`20261016130009_stock_ledger.sql`](supabase/migrations/20261016130009_stock_ledger.sql)).
7. **The faculty member follows it and rates it**:
   [`my_report_detail_screen.dart`](lib/features/damage_reports/presentation/my_reports/my_report_detail_screen.dart)
   updates live; rating it in
   [`rate_service_screen.dart`](lib/features/feedback/presentation/rate_service_screen.dart)
   closes the report.

A report with a geo-tag also appears on Map View
([`report_map_screen.dart`](lib/features/map_view/presentation/report_map_screen.dart)).

---

## Shared code

### Layouts (the frame around each app)

| What | Where |
|---|---|
| Admin console frame: sidebar, header, gold rule | [`lib/shells/admin/admin_shell.dart`](lib/shells/admin/admin_shell.dart), [`widgets/admin_sidebar.dart`](lib/shells/admin/widgets/admin_sidebar.dart), [`widgets/admin_top_bar.dart`](lib/shells/admin/widgets/admin_top_bar.dart), [`widgets/admin_nav_items.dart`](lib/shells/admin/widgets/admin_nav_items.dart) (the sidebar's items) |
| Header account menu (My Profile, Logout) | [`widgets/admin_profile_menu.dart`](lib/shells/admin/widgets/admin_profile_menu.dart) |
| Faculty and staff app frame and its four tabs | [`lib/shells/requestor/`](lib/shells/requestor/) |
| Maintenance app frame and its four tabs | [`lib/shells/personnel/personnel_shell.dart`](lib/shells/personnel/personnel_shell.dart) |
| Pieces both phone apps share: header, bottom bar, title row | [`lib/shells/mobile/`](lib/shells/mobile/) |
| Screen size: the console at 90%, the phone apps fitted to small phones | [`lib/shells/app_viewport.dart`](lib/shells/app_viewport.dart) |

### Shared widgets ([`lib/core/widgets/`](lib/core/widgets/))

| Widget | File |
|---|---|
| Tables, paging, sideways scroll on narrow screens | [`app_data_table.dart`](lib/core/widgets/app_data_table.dart), [`table_pagination.dart`](lib/core/widgets/table_pagination.dart), [`scroll_when_narrow.dart`](lib/core/widgets/scroll_when_narrow.dart) |
| Cards | [`section_card.dart`](lib/core/widgets/section_card.dart), [`stat_card.dart`](lib/core/widgets/stat_card.dart) |
| Status, priority and category chips | [`status_chip.dart`](lib/core/widgets/status_chip.dart), [`priority_chip.dart`](lib/core/widgets/priority_chip.dart), [`category_chip.dart`](lib/core/widgets/category_chip.dart) |
| Dialogs: confirm delete, confirm logout | [`confirm_delete_dialog.dart`](lib/core/widgets/confirm_delete_dialog.dart), [`sign_out_dialog.dart`](lib/core/widgets/sign_out_dialog.dart) |
| Dropdowns used in filters and forms | [`filter_select.dart`](lib/core/widgets/filter_select.dart) |
| Loading, empty and error states | [`async_value_view.dart`](lib/core/widgets/async_value_view.dart) |
| Page title row | [`page_header.dart`](lib/core/widgets/page_header.dart) |
| Category donut chart | [`category_donut.dart`](lib/core/widgets/category_donut.dart) |
| Initials avatar | [`person_avatar.dart`](lib/core/widgets/person_avatar.dart) |
| Offline banner, startup error page | [`offline_banner.dart`](lib/core/widgets/offline_banner.dart), [`startup_error_screen.dart`](lib/core/widgets/startup_error_screen.dart) |

### Colors, text styles and screen sizes

[`app_colors.dart`](lib/core/constants/app_colors.dart),
[`app_text_styles.dart`](lib/core/constants/app_text_styles.dart),
[`breakpoints.dart`](lib/core/constants/breakpoints.dart) (when the console
switches between phone, tablet and full layouts).

### Every page's URL

[`route_paths.dart`](lib/core/routing/route_paths.dart) names every URL;
[`app_router.dart`](lib/core/routing/app_router.dart) says which screen
each one opens; [`route_guards.dart`](lib/core/routing/route_guards.dart)
decides who may open it.

| Admin console | Faculty and staff app | Maintenance app |
|---|---|---|
| `/admin/login`, `/admin/dashboard`, `/admin/reports`, `/admin/reports/:id`, `/admin/task-assignment`, `/admin/work-orders`, `/admin/work-orders/:id`, `/admin/map`, `/admin/inventory`, `/admin/facilities`, `/admin/personnel`, `/admin/analytics`, `/admin/users`, `/admin/notifications`, `/admin/settings`, `/admin/profile` | `/staff/login`, `/staff/signup`, `/staff/home`, `/staff/submit`, `/staff/reports`, `/staff/reports/:id`, `/staff/reports/:id/rate`, `/staff/alerts`, `/staff/profile` | `/personnel/dashboard`, `/personnel/tasks`, `/personnel/work-orders`, `/personnel/work-orders/:id`, `/personnel/work-orders/:id/materials`, `/personnel/materials`, `/personnel/scan`, `/personnel/alerts`, `/personnel/profile` |

### Starting the app

[`lib/main.dart`](lib/main.dart) starts Firebase and the database
connection, then [`lib/app.dart`](lib/app.dart) builds the app and its
router.

---

## Database and API

GSUhub has no custom server. The backend is a **Supabase** project
(Postgres database, file storage, live updates) plus **Firebase
Authentication** for sign-in and **Firebase Cloud Messaging** for push.

| What | Where |
|---|---|
| The database, built step by step | [`supabase/migrations/`](supabase/migrations/), in date order (below) |
| Database tests (pgTAP) | [`supabase/tests/`](supabase/tests/), one file per group of functions |
| Demo data for local runs | [`supabase/seed.sql`](supabase/seed.sql), generated by [`tool/seed.dart`](tool/seed.dart) |
| Sign-in bridge (Firebase token → database token) | [`supabase/functions/firebase-token-exchange/`](supabase/functions/firebase-token-exchange/) |
| Local stack settings | [`supabase/config.toml`](supabase/config.toml); guide [`supabase/README.md`](supabase/README.md) |
| App's database connection and session | [`lib/core/services/supabase/supabase_session.dart`](lib/core/services/supabase/supabase_session.dart) |
| Base class every repository uses (calls functions, reads tables, live streams) | [`lib/core/data/supabase_repository.dart`](lib/core/data/supabase_repository.dart), rows into records: [`row_record.dart`](lib/core/data/row_record.dart) |
| Which repository and service the app uses (dependency injection) | [`lib/core/di/repository_providers.dart`](lib/core/di/repository_providers.dart), [`service_providers.dart`](lib/core/di/service_providers.dart) |
| Database errors in plain words | [`lib/core/errors/supabase_error_mapper.dart`](lib/core/errors/supabase_error_mapper.dart), [`failures.dart`](lib/core/errors/failures.dart); every call returns a [`Result`](lib/core/utils/result.dart) |
| Connection settings (URL, key, live or local) | [`lib/core/config/env.dart`](lib/core/config/env.dart), [`app_config.dart`](lib/core/config/app_config.dart) |
| Table names used in code | [`lib/core/constants/table_names.dart`](lib/core/constants/table_names.dart) |
| Photo storage | [`lib/core/services/supabase/supabase_storage_service.dart`](lib/core/services/supabase/supabase_storage_service.dart); its rules in [`20261016130014_storage_policies.sql`](supabase/migrations/20261016130014_storage_policies.sql) |
| Every table, field and permission, described | [`docs/data_dictionary.md`](docs/data_dictionary.md) |

### The migrations

| Migration | What it adds |
|---|---|
| [`20261016125957_tables.sql`](supabase/migrations/20261016125957_tables.sql) | The 19 tables |
| [`20261016130001_access_helpers.sql`](supabase/migrations/20261016130001_access_helpers.sql) | Who is asking: role and account checks |
| [`20261016130005_row_level_security.sql`](supabase/migrations/20261016130005_row_level_security.sql) | Who may read each table |
| [`20261016130009_stock_ledger.sql`](supabase/migrations/20261016130009_stock_ledger.sql) | Stock moves only through the ledger |
| [`20261016130014_storage_policies.sql`](supabase/migrations/20261016130014_storage_policies.sql) | Who may upload and read photos |
| [`20261016130018_realtime.sql`](supabase/migrations/20261016130018_realtime.sql) | Live updates |
| [`20261016145419_server_helpers.sql`](supabase/migrations/20261016145419_server_helpers.sql) | Shared pieces: status rules, audit, notices |
| [`20261016145429_account_functions.sql`](supabase/migrations/20261016145429_account_functions.sql) | Accounts |
| [`20261016145439_facility_functions.sql`](supabase/migrations/20261016145439_facility_functions.sql) | Rooms and equipment |
| [`20261016145448_report_functions.sql`](supabase/migrations/20261016145448_report_functions.sql) | Damage reports, review, duplicates |
| [`20261016145458_work_order_functions.sql`](supabase/migrations/20261016145458_work_order_functions.sql) | Work orders |
| [`20261016145508_feedback_notification_config_functions.sql`](supabase/migrations/20261016145508_feedback_notification_config_functions.sql) | Ratings, notifications, settings |
| [`20261017065945_task_functions.sql`](supabase/migrations/20261017065945_task_functions.sql) | Tasks and proof photos |
| [`20261017065951_accomplishment_functions.sql`](supabase/migrations/20261017065951_accomplishment_functions.sql) | Accomplishment reports and sign-off |
| [`20261017065955_material_functions.sql`](supabase/migrations/20261017065955_material_functions.sql) | Materials used, requested and pre-assigned |
| [`20261017065959_inventory_functions.sql`](supabase/migrations/20261017065959_inventory_functions.sql) | Materials, deliveries, stock counts |
| [`20261017070003_tool_functions.sql`](supabase/migrations/20261017070003_tool_functions.sql) | Tools and loans |
| [`20261020111840_admin_notifications.sql`](supabase/migrations/20261020111840_admin_notifications.sql) | The administrator's notices |
| [`20261020111843_reassign_work_order.sql`](supabase/migrations/20261020111843_reassign_work_order.sql) | Reassigning a work order |
| [`20261020111846_work_order_signoff.sql`](supabase/migrations/20261020111846_work_order_signoff.sql) | Completion only through the sign-off |
| [`20261020111849_config_validation.sql`](supabase/migrations/20261020111849_config_validation.sql) | Checks on the saved settings |
| [`20261020112150_task_start_audit.sql`](supabase/migrations/20261020112150_task_start_audit.sql) | Audit entry when a task starts |
| [`20261105104825_delete_material.sql`](supabase/migrations/20261105104825_delete_material.sql) | Deleting a material, keeping its history |
| [`20261108141827_console_delete_and_archive.sql`](supabase/migrations/20261108141827_console_delete_and_archive.sql) | Deleting rooms, equipment, tools and accounts; archiving reports and work orders |

---

## Tests

| What | Where | Run with |
|---|---|---|
| Unit tests (logic, repositories, models) | [`test/unit/`](test/unit/) | `flutter test` |
| Screen tests (every page, every screen size) | [`test/widget/`](test/widget/) | `flutter test` |
| Fakes and test harnesses | [`test/support/`](test/support/) | |
| End-to-end flows against the local database | [`test/e2e/`](test/e2e/) | `SUPABASE_E2E=1 flutter test test/e2e` |
| Database tests (pgTAP) | [`supabase/tests/`](supabase/tests/) | `npx supabase test db` (Docker), or without Docker: `cd tool/sql_tests; node run.mjs` |
| Sign-in bridge tests | [`supabase/functions/tests/`](supabase/functions/tests/) | see [`supabase/README.md`](supabase/README.md) (Deno) |
| Old Firestore rules (until Firestore is locked) | [`test/rules/`](test/rules/) | `npm run test:rules` |

Each manuscript requirement and the tests that prove it:
[`docs/testing.md`](docs/testing.md).

---

## Naming conventions

- **Folders** are named for the feature, in plain words:
  `damage_reports`, `work_orders`, `qr_codes`, `map_view`.
- **Screens end in `_screen.dart`**, dialogs in `_dialogs.dart`, bottom
  sheets in `_sheets.dart`, controllers in `_controller.dart`, providers
  in `_providers.dart`.
- **Which app a screen belongs to** shows in its name or folder:
  - no prefix: the admin console (`reports_screen.dart`);
  - `admin_`: the admin console, where a phone version also exists
    (`admin_login_screen.dart`, `admin_profile_screen.dart`);
  - `requestor_` or a `my_reports/` and `submission/` folder: the
    faculty and staff app;
  - `personnel_` or a `personnel/` folder: the maintenance app;
  - `mobile_`: shared by both phone apps (`mobile_login_screen.dart`,
    `mobile_alerts_screen.dart`, `mobile_profile_screen.dart`).
- **Repositories**: `<name>_repository.dart` is the contract,
  `<name>_repository_impl.dart` the Supabase implementation.
- **Migrations** are named `<date and time>_<what it adds>.sql`, and run
  in that order.

## Other folders

| Folder | Contents |
|---|---|
| [`assets/`](assets/) | Fonts, icons and images |
| [`docs/`](docs/) | Architecture decisions, data dictionary, setup, deployment, testing, demo script |
| [`docs/diagrams/`](docs/diagrams/) | System diagrams |
| [`scripts/`](scripts/) | Release builds: [`deploy_web.ps1`](scripts/deploy_web.ps1) (website), [`build_apk.ps1`](scripts/build_apk.ps1) (Android) |
| [`tool/`](tool/) | Developer tools: run everything locally, demo data, database tests without Docker, the Firestore → Supabase migration |
| [`deploy/`](deploy/) | The website's hosting settings (Vercel) |
| [`firebase/`](firebase/) | The old Firestore rules, kept until Firestore is locked |
| [`android/`](android/), [`web/`](web/) | Platform projects Flutter builds from |
