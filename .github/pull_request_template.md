## WBS objective(s)

<!-- e.g. 2.A — Admin authentication, dashboard, and main layout -->

## What changed

<!-- Brief description. Link an issue/task if one exists. -->

## Scope check

- [ ] This PR stays within its named WBS objective's scope (didn't build
      ahead into a later objective, didn't touch fields/schema if this is
      a 1.A/1.B boundary case — see `docs/architecture_decisions.md`)
- [ ] No shell imports `cloud_firestore` / `firebase_auth` /
      `firebase_storage` / `firebase_messaging` directly (goes through
      `core/services/` instead)
- [ ] No collection name literal outside `firestore_paths.dart`

## Verification

- [ ] `flutter analyze` passes clean
- [ ] `flutter test` passes
- [ ] Manually tested on: <!-- web / Android / both -->

## Screenshots (if UI changed)

<!-- Before/after, or just after for new screens -->
