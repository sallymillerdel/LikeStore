# LikeStore: full setup guide

A step-by-step version of the setup and workflow in [README.md](README.md). The rules
behind it are in [MARKET_SPEC.md](MARKET_SPEC.md).

Every command runs on your **Windows PC** in **PowerShell**, from the repository
root (the folder that contains `market.json`) unless the step says otherwise.

How it fits together:

* **GitHub Pages** serves `catalog.json` and `catalog.json.sig` at
  `https://sallymillerdel.github.io/LikeStore/`.
* **GitHub Releases** in the same repo hold the actual files (`.apk`, `.zip`).
* **The store app** (`market/`, Flutter, Android + Windows) downloads the catalog,
  checks its Ed25519 signature with the public key built into it, then downloads,
  hash-checks and installs apps.
* **`scripts/publish.py`** is the only tool that changes the catalog. It uploads
  releases with `gh`, updates and signs `catalog.json`, commits and pushes.

---

## Part 0. Install the tools (once per PC)

| Tool | Why | How to check |
|---|---|---|
| **Git** | commit and push the catalog | `git --version` |
| **GitHub CLI (`gh`)** | `publish.py` uploads releases with it | `gh --version` |
| **Python 3.10+** with the `py` launcher | runs `publish.py` | `py --version` |
| Python package **`cryptography`** | Ed25519 signing | `py -c "import cryptography"` |
| **Flutter SDK** (recent stable; the project needs Dart 3.12+) | builds the store | `flutter --version` |
| **Visual Studio 2022** with the *Desktop development with C++* workload | Flutter Windows builds | `flutter doctor` |
| **JDK 17** (Eclipse Adoptium/Temurin) | Android builds and `keytool` | `java -version` |
| **Android SDK** at `D:\dev\android-sdk` | Android builds | `flutter doctor` |

Steps:

1. Install anything missing from the table.
2. Install the Python dependency:
   ```powershell
   py -m pip install cryptography
   ```
3. Log in to GitHub CLI and choose **GitHub.com → HTTPS → Login with a web browser**:
   ```powershell
   gh auth login
   gh auth status
   ```
4. Run `flutter doctor` and fix anything red for **Windows** and **Android**.
5. Where the build script looks for the JDK and SDK:
   `market\build-android.ps1` uses `JAVA_HOME` and `ANDROID_HOME` if you've set them. If not, it falls back to
   `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot` and `D:\dev\android-sdk`.
   If your JDK is somewhere else, set `JAVA_HOME` yourself:
   ```powershell
   setx JAVA_HOME "C:\Program Files\Eclipse Adoptium\jdk-17.x.x-hotspot"
   ```

> `setx` only affects **new** terminals. After any `setx`, close PowerShell and open a new one.

---

## Part 1. The GitHub repository

1. The repository `sallymillerdel/LikeStore` must be **public**. Free GitHub Pages and
   anonymous downloads from Releases (which the store relies on) both require it.
   *Settings → General → Danger Zone → Change visibility.*
2. The default branch must be **`main`**. The Pages workflow only runs on pushes to
   `main` that touch `catalog/**`.
3. Clone it to your PC if you haven't yet:
   ```powershell
   gh repo clone sallymillerdel/LikeStore
   cd LikeStore
   ```

## Part 2. Turn on GitHub Pages

1. Open the repo on GitHub → **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions** (not "Deploy from a branch").
3. You don't need to add anything else. `.github/workflows/pages.yml` is already in the repo.

---

## Part 3. Create the catalog signing key (Ed25519). **Once, ever.**

This key signs `catalog.json`. Every store you install trusts only its public key.
If you lose it or create a new one, **you'll have to rebuild and reinstall every installed store**.

1. Choose where the key lives. It **must be outside the repository** (the script refuses
   otherwise):
   ```powershell
   setx MARKET_SIGNING_KEY "$env:USERPROFILE\.likestore\catalog_ed25519.pem"
   ```
2. *(Optional)* To encrypt the key file with a passphrase, also set the following before
   running keygen. You'll need it set for every later publish too:
   ```powershell
   setx MARKET_SIGNING_KEY_PASSWORD "your-passphrase"
   ```
3. **Open a new PowerShell window**, `cd` to the repo, and check:
   ```powershell
   echo $env:MARKET_SIGNING_KEY
   ```
4. Generate the key:
   ```powershell
   py scripts/publish.py keygen
   ```
   What this does:
   * writes the private key to `%USERPROFILE%\.likestore\catalog_ed25519.pem`
   * writes the public key into `market.json` (`"publicKey"`)
   * regenerates `market/lib/src/config.g.dart` (don't edit that file by hand)
   * signs the empty catalog, creating `catalog/catalog.json.sig`

   It refuses to run if the .pem already exists, if the path is inside the repo, or if
   `market.json` already has a public key. That's a safety net, not something to work around.
5. **Back up the `.pem` file now** (password manager, encrypted USB, etc.). Never commit it.
   `.gitignore` also excludes `*.pem`.

---

## Part 4. One Android release keystore for all apps. **Once, ever.**

Android updates an app only if the new APK is signed with **the same key** as the
installed one. Right now the apps are signed with machine-local *debug* keys, and XReel's
key differs from Classly's and Whylist's. From now on, sign every app with one release keystore.

1. Create the keystore (`keytool` comes with the JDK; use the full path if it's not on PATH):
   ```powershell
   keytool -genkeypair -v -keystore "$env:USERPROFILE\.likestore\release.jks" -alias release -keyalg RSA -keysize 4096 -validity 36500
   ```
   * It asks for a **keystore password**. Choose a strong one and save it.
   * It asks for name, organization, city, etc. Any values are fine.
   * Modern `keytool` creates a PKCS12 keystore, where the **key password is the same as
     the keystore password**. Use the same password in every variable below.
2. Set the environment variables for **the store** (`market\build-android.ps1` and
   `market\android\app\build.gradle.kts` read them):
   ```powershell
   setx ANDROID_KEYSTORE "$env:USERPROFILE\.likestore\release.jks"
   setx ANDROID_KEYSTORE_PASSWORD "your-keystore-password"
   setx ANDROID_KEY_ALIAS "release"
   # ANDROID_KEY_PASSWORD is optional; it defaults to ANDROID_KEYSTORE_PASSWORD
   ```
3. Set the variables for your **Flet apps** (Classly, Whylist, XReel, Luma; `flet build apk` reads them):
   ```powershell
   setx FLET_ANDROID_SIGNING_KEY_STORE "$env:USERPROFILE\.likestore\release.jks"
   setx FLET_ANDROID_SIGNING_KEY_STORE_PASSWORD "your-keystore-password"
   setx FLET_ANDROID_SIGNING_KEY_PASSWORD "your-keystore-password"
   setx FLET_ANDROID_SIGNING_KEY_ALIAS "release"
   ```
   Note: `setx` stores these in your Windows user environment as plain text. That's fine on
   a personal PC. If you'd rather not, set them only inside your build scripts.
4. **Back up `release.jks` and its password.** If you lose them, no existing install of any
   of your Android apps can ever be updated again.
5. On phones that already have a **debug-signed** copy of an app: **uninstall it once**,
   then install the release-signed version from the store. After that, updates work normally.

---

## Part 5. Commit and push the setup

```powershell
git status          # expect: market.json, market/lib/src/config.g.dart, catalog/catalog.json, catalog/catalog.json.sig
git add -A
git commit -m "Set up LikeStore"
git push
```

Make sure no `.pem` or `.jks` file shows up in `git status`. They should live in
`%USERPROFILE%\.likestore\`, outside the repo.

Then:

1. GitHub → **Actions** tab → "Deploy catalog to Pages" should go green (about 1 minute).
2. Open `https://sallymillerdel.github.io/LikeStore/catalog.json` in a browser. You should
   see `{"schemaVersion": 1, "generatedAt": "...", "apps": []}`.
3. Check the live signature from your PC:
   ```powershell
   py scripts/publish.py verify
   ```
   With an empty catalog it should end with `verify: all good.`

---

## Part 6. Build the store and publish it into its own catalog

The store is listed in its own catalog as `com.likestore.market`, so it can update itself.

1. *(First time: optional; for later releases: required)* Set the versions in
   `market/versions.json`, one per platform, e.g. `"windows": "1.0.0+1"` and
   `"android": "1.0.0+1"`. The part before `+` is the version name (it's also part of
   the release tag). The number after `+` is the Android `versionCode`, or the build
   part of the Windows file version (at most 65535). Bump the platforms you release.
2. Build Windows (writes `incoming\com.likestore.market-win-<version>.zip` and `.json`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File market\build-windows.ps1
   ```
3. Build Android, signed with the release keystore (writes `incoming\com.likestore.market.apk`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File market\build-android.ps1
   ```
   If it says `ANDROID_KEYSTORE is not set`, you didn't open a new terminal after `setx`.
   Don't use `-DebugKey` for anything you publish. A debug-signed store can never be
   updated by a release-signed one.
4. *(Optional)* Add an icon: put a PNG named `com.likestore.market.png` into `incoming\`.
5. Dry run (changes nothing, just shows the plan):
   ```powershell
   py scripts/publish.py publish --dry-run --description "My app store"
   ```
   Check the app, platforms, versions, file sizes, release tags and certificate.
   If it says the name is unknown, add `--name "LikeStore"`.
6. Publish for real (it shows the same plan and asks `Upload and publish? [y/N]`):
   ```powershell
   py scripts/publish.py publish --description "My app store"
   ```
   What it does: creates a GitHub Release per file, updates and signs
   `catalog.json`, commits `catalog/`, pushes, and moves the files from `incoming\` to
   `archive\com.likestore.market\<version>\`.
7. Wait a few minutes, then check:
   ```powershell
   py scripts/publish.py verify --app com.likestore.market
   ```

---

## Part 7. First install on each device

### Windows

1. Open `https://github.com/sallymillerdel/LikeStore/releases`.
2. Download `com.likestore.market-win-<version>.zip`.
3. Extract it somewhere permanent, e.g. `%LocalAppData%\Programs\LikeStore`.
4. Run `LikeStore.exe`. SmartScreen may warn because the exe isn't code-signed:
   **More info → Run anyway**.
5. The store adds a Start Menu shortcut (default on; Desktop shortcut is off; both are in
   Settings). Its own later updates install into `%LocalAppData%\LikeStore\apps\`.

### Android

1. On the phone, open the Releases page above in the browser.
2. Download the store APK (`com.likestore.market-android-<version>.apk`).
3. Allow **"Install unknown apps"** for the browser when Android asks (once).
4. Install and open LikeStore.
5. When the store asks for permission to install apps, tap **Allow**. This opens the
   system screen. Turn it on for LikeStore.
6. If an app you want was installed earlier with a debug key, uninstall it first (Part 4.5).

---

## Part 8. Everyday workflow: publishing an app update

1. **Bump the version** in the app project:
   * Android: increase **versionCode** (must be strictly greater than the published one)
     **and** versionName (the release tag is `<id>-android-<versionName>`, so the same
     versionName twice fails with "Release ... already exists"). With Flet, use the
     version in `pyproject.toml` or `flet build apk --build-number N --build-version X.Y.Z`.
   * Windows: increase the version (SemVer, e.g. `1.4.0` → `1.5.0`).
2. **Build**:
   * Android: a **release-signed** APK (the FLET_… variables from Part 4).
   * Windows: the **portable ZIP build** → `<app-id>-win-<version>.zip` +
     `<app-id>-win-<version>.json` (not the installer).
3. **Copy into the app's folder** (`incoming\Classly\`, `incoming\Luma\`, `incoming\Whylist\`,
   `incoming\XReel\`; create a new folder for a new app): the `.apk`, and/or the `.zip` with
   its `.json`. Optionally add `icon.png` as the icon. Old builds may stay in the folder (they
   are skipped); other kinds of files make the script stop.
4. **Publish**, either way:
   * Tell Claude Code: *"Update Classly, I dropped the files."* Claude runs the dry run,
     shows you the plan, **waits for your yes**, publishes, then runs `verify`.
   * Or by hand:
     ```powershell
     py scripts/publish.py publish --dry-run --changelog "Bug fixes"
     py scripts/publish.py publish --changelog "Bug fixes"
     ```
     For a brand-new app add `--name "App Name" --description "..."`.
5. **Devices see the update within about 10 minutes** (Pages CDN cache). In the store, press
   **Check for updates** and then **Update**.
6. Check afterwards: `py scripts/publish.py verify --app <id>`.

### Before you publish, make sure

* You're on `main`, and `git pull` is done (the script stops if you're behind origin).
* `catalog/` has no uncommitted changes (the script stops otherwise).
* The terminal has `MARKET_SIGNING_KEY` (and the passphrase variable, if you used one).

### Other commands

```text
py scripts/publish.py list                                   show what the catalog contains
py scripts/publish.py edit <id> --name "..." --description "..." --icon icon.png
py scripts/publish.py remove <id> [android|windows]          remove an app or one platform (releases stay on GitHub)
py scripts/publish.py verify [--app <id>] [--quick]          live signature + every file's hash (--quick: sizes only)
py scripts/publish.py sync-config                            regenerate config.g.dart from market.json
py scripts/publish.py sign                                   re-sign catalog.json
```

`edit` and `remove` also accept `--dry-run` / `--yes` / `--no-push` (`remove` has no `--dry-run`).

---

## Part 9. Notes about the existing apps

* **XReel:** the Windows build calls the app `xreel`, but the APK is `com.slx.xreel`. The
  publisher will stop and ask. Either change the id in XReel's portable build to
  `com.slx.xreel`, or publish the zip once with `--app-id com.slx.xreel`. After that, the
  catalog remembers the mapping (`sourceId`).
* **Whylist** and **XReel** don't have a portable-ZIP build script yet (Classly and Luma do).
  Until they do, publish only their Android builds.
* **All Android apps** must keep using the same keystore forever (Part 4).
* **Windows apps** must keep user data in `%AppData%` / `%LocalAppData%`, never next to the
  exe. Each version is unpacked into its own folder, and old folders are deleted.

---

## Part 10. When `publish.py` says STOP

It stops **before changing anything** in these cases:

| Message (short) | What to do |
|---|---|
| `MARKET_SIGNING_KEY is not set` | Open a new terminal after `setx`, or set the variable again. |
| `points to a missing file` / `Could not load the signing key` | Wrong path, or a wrong/missing `MARKET_SIGNING_KEY_PASSWORD`. |
| key doesn't match `market.json` | You're using a different key than the one the store trusts. Find the original .pem. |
| `versionCode N is not greater than the published M` | Bump versionCode and rebuild. |
| `version X is not greater than the published Y` | Bump the Windows version and rebuild. |
| `signed with a different certificate` | The APK isn't signed with the shared keystore. Rebuild with it. |
| `SHA-256 does not match` / `entry ... is not inside the zip` | Rebuild the portable ZIP. Don't edit the .json by hand. |
| `Release ... already exists` | Bump the version (for Android, versionName too). |
| `looks like the existing app ... but has a different id` | Re-run with the `--app-id` it suggests (same app) or the other one (different app). |
| `is a new app and its name is unknown` | Re-run with `--name "App Name"`. |
| `catalog/ has uncommitted changes` / `is behind origin` | Commit/discard, or `git pull`. |
| `Don't know what to do with: ...` | Remove stray files from `incoming\`. |
| `Could not ask GitHub whether release ... exists` | Run `gh auth status`, check your internet, run `gh auth login` again. |

If the upload succeeds but `git push` fails, the script prints a warning. The commit is
local, so run `git push` yourself.

---

## Part 11. Backups checklist (keep these off this PC too)

* `%USERPROFILE%\.likestore\catalog_ed25519.pem` (+ its passphrase, if you set one)
* `%USERPROFILE%\.likestore\release.jks` + its password + alias `release`

Losing the first means rebuilding and reinstalling the store on every device. Losing the
second means you can never update any installed Android app again.

---

## Part 12. Development

```powershell
py -m unittest discover -s scripts      # publisher tests
cd market; flutter test; flutter analyze
```

* `market/lib/src/config.g.dart` is generated from `market.json`
  (`py scripts/publish.py sync-config`). It's the only place that knows the hosting URL.
* `kotlin.incremental=false` in `market/android/gradle.properties` works around a Kotlin
  cache bug that happens when the project and the pub cache are on different drives.
