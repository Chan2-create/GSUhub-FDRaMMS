# Git Workflow

Branch strategy, naming, and commit conventions for the three-person
GSUhub team (Estologa, Landoy, Ranque). Optimized for a small team on a
fixed academic timeline — not a full corporate gitflow.

## Branches

- **`main`** — always buildable. Nothing is pushed here directly; every
  change lands via a reviewed pull request. Tag `main` at each WBS
  objective's completion (e.g. `wbs-1a`, `wbs-2a`) so a defense demo can
  check out a known-good milestone quickly.
- **`feature/<wbs-id>-<short-description>`** — one branch per WBS
  sub-objective or a clearly separable slice of one. Examples:
  - `feature/2a-admin-auth`
  - `feature/2b-damage-report-kanban`
  - `feature/1b-firestore-schema`
- **`fix/<short-description>`** — bug fixes that aren't tied to a specific
  WBS objective (e.g. `fix/router-redirect-loop`).

Branch off the latest `main`, rebase before opening a PR if `main` has
moved, and delete the branch once merged.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), scoped to
the touched layer where it helps:

```
<type>(<scope>): <short summary>

<optional body — the why, not the what>
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. Scope is
whatever's most useful — a shell (`admin`, `staff`, `personnel`), a layer
(`core`, `services`, `routing`), or a WBS id.

Examples:

```
feat(admin): add login form and RBAC redirect (2.A)
fix(routing): correct staff shell redirect loop on sign-out
docs: record shared backend contract in architecture_decisions.md
test(core): cover ReportStatus terminal-state transitions
```

## Pull requests

- One PR per feature/fix branch, targeting `main`.
- Fill in `.github/pull_request_template.md` — in particular, name the
  WBS objective(s) the PR advances and confirm `flutter analyze` /
  `flutter test` pass locally before requesting review.
- At least one of the other two team members reviews and approves before
  merge. With three people, "the other two" is usually just one reviewer
  in practice — that's fine, but self-merging without any review is not.
- Prefer squash-merge so `main`'s history reads one commit per PR/feature.

## What NOT to commit

- `lib/core/config/firebase_options.dart` (real credentials) — gitignored;
  `firebase_options.example.dart` is the committed template.
- `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`
  — same reason.
- Build output (`build/`, `.dart_tool/`) and IDE-local files (`.idea/`,
  `*.iml`) — already covered by `.gitignore`.

## Resolving conflicts in shared files

`firestore_paths.dart`, the enums under `core/enums/`, and the service
interfaces under `core/services/` are imported by all three shells (the
"Shared Backend Contract" in `docs/architecture_decisions.md`). A change
to any of them is more likely to conflict across parallel feature
branches than a change inside `shells/<role>/` or `features/<name>/`.
When touching a shared file, keep the PR small and merge it promptly
rather than letting it sit alongside unrelated feature work.
