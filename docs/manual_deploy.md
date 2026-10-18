# Deployment and debugging

How the admin console reaches Vercel and the Android APK is built, both
against the **live** projects — Firebase `gsuhub-dorsu` for sign-in and
push, Supabase for the data and photos (Objective 1) — how the hosted
Supabase project is set up and the data moved to it ("Going live"), and
how to find and fix bugs found there. This is deployment tooling, not a WBS
objective.

- **Web: automatic.** Every push to `main` builds the console and
  publishes it to Vercel (GitHub Actions; see "Automatic web deploys").
  `scripts\deploy_web.ps1` is still there for a deploy by hand.
- **Android: by hand.** Build an APK for each major update with
  `scripts\build_apk.ps1`, after raising the version
  (see "Before each APK build").

Debug builds still default to the Auth emulator and the local Supabase
stack (see `docs/local_setup.md`). Only release builds — the workflow's
and the two scripts' — talk to the live projects. They read
`SUPABASE_URL` and `SUPABASE_ANON_KEY` from the environment, or from the
repository secrets of the same names, and stop if either is missing.

All commands run in PowerShell from the repo root, `D:\Capstone System`.

---

## The two commands

```powershell
.\scripts\deploy_web.ps1      # build the admin console and deploy it to Vercel by hand
.\scripts\build_apk.ps1       # build the release APKs
```

| Option | Effect |
|---|---|
| `deploy_web.ps1 -Clean` | `flutter clean` first |
| `deploy_web.ps1 -Preview` | deploy a preview URL instead of production |
| `deploy_web.ps1 -SkipDeploy` | build and check only, upload nothing |
| `build_apk.ps1 -Universal` | one APK for every phone instead of one per CPU type |
| `build_apk.ps1 -Clean` | `flutter clean` first |

Both scripts stop at the first failing step and say which one. Both end
(as does the automatic web deploy) with a **release check** (`scripts\check_release_output.ps1`) that fails
the build if it still points at the emulators: `127.0.0.1`, `10.0.2.2`,
an emulator port (`:8080`, `:9099`, `:9199`), or `localhost` outside the
few places Flutter and Firebase use it themselves. It also confirms the
live project id was compiled in.

---

## Automatic web deploys

`.github/workflows/deploy-web.yml` runs on every push to `main`, and on
demand from the repo's **Actions** tab (**Deploy web → Run workflow**).
On a Windows runner it:

1. writes `lib/firebase_options.dart` from a secret (the file is
   gitignored);
2. builds the console with Flutter 3.47.4 for live Firebase;
3. adds `deploy/vercel.json` and runs the same release check as the
   scripts — a build that still points at the emulators stops here and
   is never published;
4. publishes it to the Vercel project as production
   (**https://gsuhub-dorsu.vercel.app**).

The repo is not connected to Vercel; this workflow is the only thing that
deploys. A deploy takes roughly 10 minutes. Each run's log is under the
repo's **Actions** tab; a failed run is marked with a red ✗ on the commit
and GitHub emails you.

### First time: the Vercel project

The workflow publishes to an existing Vercel project; it does not create
one. Create it once from this computer: run `.\scripts\deploy_web.ps1`
and answer the link questions (see "One-time setup → Vercel" below). That
also writes `.vercel\project.json` (gitignored), where two of the
secrets come from.

### The secrets to add

Add each one in GitHub: the repo → **Settings → Secrets and variables →
Actions → New repository secret**. The name must match exactly. None of
them is ever committed; the workflow reads them at run time and GitHub
hides them in logs.

1. **`VERCEL_TOKEN`** — lets the workflow deploy as you.
   https://vercel.com/account/tokens → **Create Token**. Name it
   `github-actions-gsuhub`, scope your personal projects
   (`christianvillemasucolranque-gmailcom's projects`), and pick an
   expiration. Copy it straight away; Vercel shows it once. When it
   expires, deploys fail until you create a new one and replace the
   secret.
2. **`VERCEL_ORG_ID`** — which Vercel account owns the project. The
   `"orgId"` value in `.vercel\project.json`
   (`Get-Content .vercel\project.json`). Also on Vercel: your team's
   **Settings → General → Team ID**.
3. **`VERCEL_PROJECT_ID`** — which project to deploy to. The
   `"projectId"` value in the same file (starts with `prj_`). Also on
   Vercel: the project → **Settings → General → Project ID**.
4. **`FIREBASE_OPTIONS_DART`** — the Firebase configuration. The whole
   content of your local `lib\firebase_options.dart`, pasted as is. To
   copy it: `Get-Content lib\firebase_options.dart -Raw | Set-Clipboard`.
   If you ever re-run `flutterfire configure`, update this secret too.

5. **`SUPABASE_URL`** — the hosted Supabase project, `https://<ref>.supabase.co`
   (Project Settings → API).
6. **`SUPABASE_ANON_KEY`** — its publishable key (or the legacy anon key)
   from the same page. Public by design, but kept out of the repo. **Never
   the service-role or secret key.**

Once all six exist, push to `main` (or use **Run workflow**) and watch
the run in the **Actions** tab. A missing secret stops the first step
with a message naming it.

The "Going live" checklist below still applies: in particular, the Vercel
domain must be an authorised domain, or sign-in on the site fails.

---

## One-time setup

### Vercel

1. Sign in once: `vercel login` (already done on this machine).
2. Run `.\scripts\deploy_web.ps1`. The first deploy asks Vercel's link
   questions. The wording varies a little between CLI versions; answer:

   | Question | Answer |
   |---|---|
   | Set up and deploy "…\build\web"? | **Y** |
   | Which scope should contain your project? | your personal scope (`christianvillemasucolranque-gmailcom's projects`) |
   | Link to existing project? | **N** |
   | What's your project's name? | **gsuhub-dorsu** |
   | In which directory is your code located? | **./** |
   | Want to modify these settings? | **N** (no framework, no build command — the site is already built) |

   The project name becomes the address, **https://gsuhub-dorsu.vercel.app**.
   If Vercel says the name is taken, use `gsuhub-dorsu-admin` and put that
   domain in Firebase instead (below). The Hobby plan is free.
3. The script saves the link in `.vercel\` at the repo root (gitignored),
   so later deploys ask nothing.

Production deploys are public. Preview deploys (`-Preview`) sit behind
Vercel's login by default, and Firebase sign-in will not work on them
until their domain is authorised, so test on the production address.

### Release signing (Android)

An APK must be signed with the same key for every update. Create the key
once and **keep it outside the repo**.

1. Create the keystore. It asks for a password (twice) and a few name
   questions; answer them however you like, then `yes`:

   ```powershell
   New-Item -ItemType Directory -Force "$env:USERPROFILE\keys" | Out-Null
   keytool -genkeypair -v -keystore "$env:USERPROFILE\keys\gsuhub-release.jks" `
     -keyalg RSA -keysize 2048 -validity 10000 -alias gsuhub
   ```

   This makes a PKCS12 keystore, which uses one password for the store
   and the key.

2. Copy `android\key.properties.example` to `android\key.properties`
   (gitignored) and fill it in, with forward slashes in the path:

   ```properties
   storeFile=C:/Users/chris/keys/gsuhub-release.jks
   storePassword=<the password>
   keyAlias=gsuhub
   keyPassword=<the same password>
   ```

3. **Back up now.** Put `gsuhub-release.jks` and its password somewhere
   outside this computer — a password manager, or a private drive. If the
   key is lost, nobody can update an installed GSUhub again; every phone
   would have to uninstall it (losing its sign-in) and install a new one.

4. Add the key's fingerprint to Firebase. Print it:

   ```powershell
   keytool -list -v -keystore "$env:USERPROFILE\keys\gsuhub-release.jks" -alias gsuhub
   ```

   Copy the `SHA1:` and `SHA256:` lines into **Firebase Console → Project
   settings → General → Your apps → Android (com.dorsu.gsuhub) → Add
   fingerprint**. GSUhub signs in with email and password, which works
   without it, but Google sign-in, phone sign-in and App Check need it.
   `build_apk.ps1` also prints the certificate of each build, to check it
   was signed with this key.

`build_apk.ps1` refuses to build without `android\key.properties`: an APK
signed with the debug key cannot later be updated by a properly signed
one. (`flutter run --release` still works without it, using the debug
key, for local testing only.)

---

## Which APK to share

`build_apk.ps1` builds one APK per CPU type into
`build\app\outputs\flutter-apk\`, and prints each one's path and size.
Sizes from the 1.0.0+1 build:

| File | Size | For |
|---|---|---|
| `app-arm64-v8a-release.apk` | ~29 MB | **almost every phone** from the last several years — share this one |
| `app-armeabi-v7a-release.apk` | ~25 MB | older or low-end 32-bit phones |
| `app-x86_64-release.apk` | ~32 MB | PC emulators only |

If you are not sure what a tester's phone is, run
`.\scripts\build_apk.ps1 -Universal` and share the single
`app-release.apk`, which works everywhere but is larger.

### Before each APK build

The version lives in one line of `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

The part before `+` is the version people see (in Android's app info).
The number after it is the **build number**, which Android compares:
it refuses to install a lower build number over a higher one.

Before every APK you share:

1. Open `pubspec.yaml` and raise the version line:
   - **always** add 1 to the build number: `1.0.0+1` → `1.0.0+2`;
   - for a **major update**, also raise the visible version and keep
     counting the build number: `1.0.0+2` → `1.1.0+3`. (Use
     `1.0.1+N` for a fix-only update, `2.0.0+N` for a big redesign.)
   - never lower the build number, even when the visible version goes up.
2. Run `.\scripts\build_apk.ps1`. Its first line prints the version it
   is building, e.g. `Building GSUhub 1.1.0+3`; check it is the new one.
3. Install it over the old one (`adb install -r …`) or share the APK.
4. Commit the `pubspec.yaml` change with the release, so the next build
   starts from the right number.

The web console uses the same number but needs nothing from you: it
shows whatever `main` has.

---

## Debugging

### The installed APK

1. On the phone: **Settings → About phone**, tap **Build number** seven
   times. Then **Settings → System → Developer options → USB debugging**
   on.
2. Connect it by USB and accept the "Allow USB debugging?" prompt.
3. Check it is seen: `adb devices` should list it as `device` (not
   `unauthorized`).
4. Install or update in place, keeping its data and sign-in:

   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
   ```

5. Watch its errors live while you use it:

   ```powershell
   adb logcat -c                          # clear old logs
   adb logcat -s flutter AndroidRuntime   # Dart errors and prints, plus native crashes
   ```

   `flutter logs` does much the same. Release builds print errors
   briefly, without a full stack trace. For the full one, reproduce the
   bug in a debug build (`flutter run`) against the emulators.

### The web console

- **Browser console:** F12 → Console. Every error the app hits appears
  there. Reload with **Ctrl+Shift+R** after a deploy to be sure the new
  build is loaded.
- **Vercel:** `vercel logs gsuhub-dorsu.vercel.app` shows the
  deployment's request log, useful for 404s. The app itself runs in the
  browser, so its errors are in the console, not here. `vercel ls` lists
  past deployments; `vercel rollback` returns production to the previous
  one if a deploy breaks it.

### The bug-fix loop

1. Reproduce the bug on live and read the error (console or logcat).
2. Fix it in the code, on a `fix/<short-description>` branch.
3. Check it locally: `flutter test`, and `flutter run` against the
   emulators (`tool\run_local.cmd`).
4. Try the fix on live before merging, if you want to:
   - web: `.\scripts\deploy_web.ps1 -Preview` gives a preview address
     (add it to Firebase's authorised domains to sign in there), or
     `.\scripts\deploy_web.ps1` deploys to production directly;
   - Android: raise the build number in `pubspec.yaml`,
     `.\scripts\build_apk.ps1`, then
     `adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
5. Commit, open a pull request and merge it. The merge is a push to
   `main`, so the web console redeploys by itself; reload the site with
   Ctrl+Shift+R once the run in the **Actions** tab is green.

---

## Going live

Do these in order, in the Firebase and Supabase dashboards and your own
terminal. Nothing here is automated, and nothing here should be done
for you by anyone else: you sign in to each service yourself.

### 1. Firebase: sign-in

1. **Authorise the Vercel domain.** Authentication → Settings →
   Authorized domains → Add domain → `gsuhub-dorsu.vercel.app`. Without
   it, sign-in on the deployed console fails.
2. **Enable Email/Password** in Authentication → Sign-in method.

### 2. Supabase: the data (Objective 1)

1. **Create the project** at https://supabase.com/dashboard → New
   project. Pick the region nearest the campus (Southeast Asia,
   Singapore). Keep the database password somewhere safe: it is not
   shown again. Note the project's **reference** (the
   `https://<ref>.supabase.co` in Project Settings → API).

   Then check that the **Data API** is on and exposes the `public`
   schema: `https://supabase.com/dashboard/project/<ref>/integrations/data_api/settings`.
   The app reads and writes only through it. "Automatically expose new
   tables" can stay off: the migrations grant exactly what the app needs.
2. **Apply the schema** from your terminal, signed in to the Supabase CLI
   yourself:

   ```powershell
   npx supabase login
   npx supabase link --project-ref <ref>     # asks for the database password
   npx supabase db push --dry-run            # lists the 17 migrations it would apply
   npx supabase db push                      # the migrations; never the demo data
   ```

   `link` connects through Supabase's connection pooler, which works on
   IPv4; the free plan's direct database address is IPv6 only.
   `db push` applies `supabase/migrations` only. Never add
   `--include-seed`. **Never run
   `supabase db reset` or the seed against the hosted project**: the
   demo data's accounts and reports are for testing.
3. **Turn off Supabase's own sign-up.** Authentication → Providers →
   Email → disable "Allow new users to sign up". People sign in with
   Firebase; nobody should get a Supabase account.
4. **Give the token exchange its signing key.** The Edge Function signs
   the tokens the database trusts, so the project must trust its key:

   ```powershell
   npx supabase gen signing-key --algorithm ES256 | Out-File -Encoding utf8 supabase\signing_keys.json
   ```

   It prints a private JSON Web Key with a `kid`; this saves it to
   `supabase/signing_keys.json`, which git ignores. Never commit it.
   Keep a copy somewhere safe outside the repository: Supabase never
   shows it again.

   Then, in Project Settings → **JWT Keys** → JWT Signing Keys
   ([Supabase's signing keys guide](https://supabase.com/docs/guides/auth/signing-keys)):

   1. If the page offers **Migrate JWT secret**, do that first.
   2. **Create standby key** → import a private key → paste the whole
      JSON object from `supabase/signing_keys.json` (the `{ … }`, with
      its `kid`).
   3. **Rotate keys**, so the imported key is the one in use. A standby
      key is not trusted yet: until the rotation, every request the app
      makes is refused. Changing a key's state is throttled for about
      five minutes, so the button may wait.
   4. **Never revoke** the imported key, nor the legacy JWT secret now
      under "Previously used": tokens and links already signed with it
      would stop working.
5. **Set the function's secrets and deploy it:**

   ```powershell
   node tool/supabase_function_env.mjs --hosted supabase\signing_keys.json
   npx supabase secrets set --env-file supabase\functions\.env.hosted
   Remove-Item supabase\functions\.env.hosted
   npx supabase functions deploy firebase-token-exchange --no-verify-jwt --use-api
   ```

   `--use-api` bundles the function on Supabase's servers, so Docker is
   not needed. The helper writes the two secrets (`FIREBASE_PROJECT_ID`,
   `TOKEN_SIGNING_KEY`) to a git-ignored file for `secrets set` to send:
   Windows PowerShell strips the quotes out of JSON typed on the command
   line.

   **Never set `ALLOW_EMULATOR_TOKENS` on the hosted project.** The
   function refuses to run if it is set there: the emulator's tokens
   are unsigned, and would let anyone in.
6. **Add the GitHub secrets the builds read** (see "The secrets to add"):
   `SUPABASE_URL` (`https://<ref>.supabase.co`) and `SUPABASE_ANON_KEY`
   (Project Settings → API Keys: the **publishable** key,
   `sb_publishable_…`). The legacy `anon` key works too, but Supabase
   retires the legacy keys at the end of 2026. **Never the service-role
   or secret key**: it skips every access rule, and the app refuses to
   start with it.

### 3. Move the existing data

Everything already in Firestore moves once, with
`tool/migrate/migrate.mjs`, into the empty database.

1. In the Firebase Console → Project settings → Service accounts,
   **Generate new private key**. Save it outside the repo. It reads all
   of Firestore: delete it from the console when the move is done.
2. Look first. A dry run reads Firestore, loads everything into the
   database inside a transaction, lists every row that would fail, and
   rolls it all back:

   ```powershell
   cd tool\migrate
   npm install
   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\the-key.json"
   $env:SUPABASE_DB_URL = "<Connect → Session pooler connection string, with the password filled in>"
   node migrate.mjs --dry-run --db $env:SUPABASE_DB_URL --ca C:\path\to\prod-ca-2021.crt
   ```

   Use the **Session pooler** string (port 5432, host
   `aws-…pooler.supabase.com`, user `postgres.<ref>`): the direct
   connection is IPv6 only on the free plan, and most home and campus
   networks are IPv4. The certificate is Project Settings → Database →
   SSL Configuration → Download certificate. The connection is verified against it; it is
   never accepted blind, because it carries the database password.

   Lines starting `!` must be fixed in Firestore first. Lines starting
   `?` are stock balances Firestore's own history disagrees with: they
   are copied as they are, and listed so you can count those materials.
3. Move it, with the photos:

   ```powershell
   $env:SUPABASE_URL = "https://<ref>.supabase.co"
   $env:SUPABASE_SERVICE_ROLE_KEY = "<Project Settings → API Keys → a secret key, sb_secret_…>"   # this terminal only
   node migrate.mjs --db $env:SUPABASE_DB_URL --ca C:\path\to\prod-ca-2021.crt --copy-photos --yes
   ```

   It writes nothing unless every row goes in. Close the terminal
   afterwards: the service-role key must not linger.
4. If Firestore was empty, **create the first administrator** instead:
   Authentication → Users → **Add user** in Firebase, copy the UID, then
   in Supabase's SQL Editor:

   ```sql
   insert into public.users (id, full_name, email, role, account_status, department)
   values ('<the UID>', '<full name>', '<the email, lower-case>', 'admin', 'active',
           'General Services Unit');
   ```

   Every other account is created from **User Accounts** in the console,
   or by signing up in the app and being approved there.
5. **Add the rooms, materials, tools** (if they did not come across) in
   the console: **Facilities & Equipment** first (the report form needs
   a building and room), then **Inventory Management**. Print the labels
   from each one's QR icon.
6. **Settings** need no copying: while a settings document is missing,
   the app uses the manuscript's values. Press **Save keywords** in
   Settings once to store the keyword list.

### 4. Afterwards

- **Lock Firestore and Storage.** Once the data is moved and the app on
  live shows it, nothing should read or write Firestore again. Deploy
  rules that deny everything, so the old data cannot be read through
  the old project. That is a deliberate step for you to take; until
  then, the rules in `firebase/` stay as they are. Never deploy the
  console's "test mode" rules: they let anyone read and write
  everything.
- **Photos no longer need Blaze.** They are in Supabase Storage (1 GB on
  the free plan), not Firebase Storage.
- **Push to a closed app still needs a server.** The Alerts tab and its
  badge update live, and the app shows a notification itself while it
  is open or recently in the background. A phone with GSUhub fully
  closed hears nothing until something sends the push
  (docs/architecture_decisions.md §16).
- **A free Supabase project pauses after a week without use.** Before a
  demo or the defense, open the dashboard and restore it if it is
  paused, then sign in once to check.
