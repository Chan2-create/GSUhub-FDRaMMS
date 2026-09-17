# GSUhub

Facility Damage Reporting and Maintenance Management System for the
General Services Unit (GSU) of Davao Oriental State University (DOrSU).

A single Flutter codebase serving three role-specific clients against one
shared Firebase backend:

| Role | Platform | Shell |
|---|---|---|
| GSU Administrator | Web | `lib/shells/admin/` |
| Faculty/Staff (Requestor) | Mobile (Android) | `lib/shells/requestor/` |
| GSU Maintenance Personnel | Mobile (Android) | `lib/shells/personnel/` |

## Status

Architecture scaffolding only (WBS Objective 1.A). No feature UI exists
yet — every route resolves to a bare placeholder screen. See
[`docs/architecture_decisions.md`](docs/architecture_decisions.md) for
what's built, what's deferred, and why.

## Getting started

Requires Flutter 3.47+ and the Android SDK (platform 35, build-tools
35.0.0) for mobile builds.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d edge          # or chrome — admin web
flutter build apk --debug    # mobile
```

Firebase is not yet configured — see
`lib/core/config/firebase_options.example.dart` for what's needed before
any feature that touches Auth/Firestore/Storage/Messaging can run against
a real project (`flutterfire configure`).

## Project structure

- `lib/core/` — platform-agnostic shared code: config, constants, enums,
  error types, abstract service interfaces, routing. No shell-specific or
  Firebase-specific code lives here (see the "Shared Backend Contract" in
  `docs/architecture_decisions.md`).
- `lib/shells/` — one router outlet per role, presentation only.
- `lib/features/` — feature modules, built incrementally per WBS
  objective; currently empty scaffolding.
- `firebase/` — Security Rules (deny-all baseline) and Firestore indexes
  (empty; populated in Objective 1.B).
- `docs/` — architecture decisions and the team git workflow.

## Contributing

See [`docs/git_workflow.md`](docs/git_workflow.md) for branch naming,
commit conventions, and the PR process for this three-developer team.
