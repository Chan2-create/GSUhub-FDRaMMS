# Deployment and debugging

How the admin console reaches Vercel and the Android APK is built, both
against the **live** Firebase project (`gsuhub-dorsu`), and how to find
and fix bugs found there. This is deployment tooling, not a WBS
objective.

- **Web: automatic.** Every push to `main` builds the console and
  publishes it to Vercel (GitHub Actions; see "Automatic web deploys").
  `scripts\deploy_web.ps1` is still there for a deploy by hand.
- **Android: by hand.** Build an APK for each major update with
  `scripts\build_apk.ps1`, after raising the version
  (see "Before each APK build").

Debug builds still default to the emulators (see
`docs/emulator_setup.md`). Only release builds — the workflow's and the
two scripts' — talk to live Firebase.

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

Once all four exist, push to `main` (or use **Run workflow**) and watch
the run in the **Actions** tab. A missing secret stops the first step
with a message naming it.

The Firebase checklist below still applies: in particular, the Vercel
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

## Live Firebase checklist

Do these in order, in the Firebase Console and your own terminal. Nothing
here is automated.

1. **Authorise the Vercel domain.** Authentication → Settings →
   Authorized domains → Add domain → `gsuhub-dorsu.vercel.app`. Without
   it, sign-in on the deployed console fails.

2. **Deploy the security rules and indexes.** Never use the console's
   "test mode" rules: they let anyone read and write everything.
   1. Run the rules tests against the emulator first (they need Java 21):
      ```powershell
      $env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"
      npm run test:rules
      ```
   2. Sign in to the Firebase CLI yourself: `firebase login`.
   3. Deploy Firestore's rules and indexes:
      ```powershell
      firebase deploy --only firestore:rules,firestore:indexes
      ```
      Use `npm run deploy:all-rules` (which also deploys Storage's rules)
      only once Storage is enabled — on the Spark plan there is no bucket
      to deploy them to, and the command fails.

3. **Create the first administrator.** Once, by hand; no password lives
   in the repo.
   1. Authentication → Sign-in method → enable **Email/Password**.
   2. Authentication → Users → **Add user** with the administrator's
      email and a strong password. Copy the new **User UID**.
   3. Firestore Database → `users` → **Add document**, Document ID = that
      UID, with these fields:

      | Field | Type | Value |
      |---|---|---|
      | `fullName` | string | the administrator's name |
      | `email` | string | the same email, lower-case |
      | `role` | string | `admin` |
      | `accountStatus` | string | `active` |
      | `department` | string | `General Services Unit` |
      | `contactNumber` | null | |
      | `specialization` | null | |
      | `availability` | null | |
      | `activeTaskCount` | number | `0` |
      | `fcmToken` | null | |
      | `createdAt` | timestamp | now |
      | `updatedAt` | timestamp | now |

   4. Sign in to the console with it. Every other account is created
      from **User Accounts** in the console, or by signing up in the app
      and being approved there.

4. **Add the facilities and configuration — not the demo data.** Never
   run `tool\seed_emulator.dart` against production; it only talks to
   the emulators anyway, and its accounts and reports are for testing.
   - **Facilities** are needed before anyone can file a report (the form
     picks a building and room). There is no screen for them yet, so add
     the campus's real rooms in Firestore → `facilities` → Add document,
     one per room:

     | Field | Type | Example |
     |---|---|---|
     | `name` | string | `Engineering Building` |
     | `buildingName` | string | `Engineering Building` |
     | `roomIdentifier` | string | `Room 203` |
     | `locationDescription` | string or null | `2nd floor, east wing` |
     | `coordinates` | geopoint or null | |
     | `qrCode` | string | the value its QR sticker encodes, unique per room, e.g. `FAC-ENG-203` |
     | `isActive` | boolean | `true` |
     | `createdAt`, `updatedAt` | timestamp | now |

   - **Configuration** (`config/prioritization`,
     `config/classification_rules`, `config/duplicate_detection`) is not
     read by any screen yet; Objective 4 uses it. Copy it from
     `tool\seed_emulator.dart` (`_seedConfig`) when that work begins.

5. **Cloud Storage needs the Blaze plan.** The project's bucket
   (`gsuhub-dorsu.firebasestorage.app`) is the newer kind that Firebase
   only provides on Blaze. On Spark, **photo upload fails on live** — and
   the report form requires at least one photo, so **faculty cannot file
   reports on live until the project is on Blaze.** Do not work around
   this by putting images in Firestore as base64. Blaze is pay-as-you-go
   with a free allowance that covers a capstone's use; set a budget alert
   when you switch.

6. **Push to a closed app needs Cloud Functions, also Blaze-only.** On
   Spark, the Alerts tab and its badge update live, and the app shows a
   notification itself while it is open or recently in the background.
   A phone with GSUhub fully closed hears nothing until a Cloud Function
   sends the push (docs/architecture_decisions.md §16).
