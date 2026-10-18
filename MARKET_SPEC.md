# MyMarket: Private App Store for My Own Apps

A project specification for building a personal "Google Play" that distributes only my own Android and Windows apps. It is meant to be read by Claude Code at the start of the project and used as the single source of truth.

---

## 1. Goal

I build many Android and PC apps and often need to install them on many devices. I want one launcher app (the "market") that:

1. Exists for **Android** and **Windows PC**.
2. Shows a catalog of my apps.
3. Installs an app for the first time and updates it later.
4. Learns about new versions **without the market itself being rebuilt or reinstalled**. New versions are published to a server; the market only reads a catalog from the internet.

### Desired workflow

1. I drop new app files into a local folder (`incoming/`).
2. I tell Claude Code something like: "Update Notes, I dropped the files."
3. Claude Code runs the publish script, which uploads the files and updates the catalog.
4. On any device with internet, I open the market, see "Update available", press **Update**, and the app is updated.

---

## 2. Architecture overview

Three parts:

| Part | What it is |
|---|---|
| **Hosting** | GitHub Pages serves `catalog.json` (+ signature). GitHub Releases stores the binaries (apk, zip). |
| **Market clients** | One Android app and one Windows app. Both read the catalog, compare versions, download, verify, install. |
| **Publisher tooling** | `scripts/publish.py` + `CLAUDE.md` rules. Claude Code runs the script when I ask for an update. |

Key principle: **the market clients contain no app files.** They only read the catalog. Updating an app means changing the catalog and uploading a file, nothing else.

```
MyMarket/
├── CLAUDE.md                 rules for Claude Code (publishing procedure)
├── MARKET_SPEC.md            this file
├── incoming/                 I drop new files here
├── archive/                  processed files are moved here after publishing
├── catalog/
│   ├── catalog.json          source of truth for the catalog
│   └── catalog.json.sig      Ed25519 signature of catalog.json
├── scripts/
│   └── publish.py            parse, hash, sign, upload, update catalog
├── market/                   Flutter client: Android + Windows from one codebase
└── .github/workflows/        deploys catalog/ to GitHub Pages
```

---

## 3. Hosting

### Decision

- **`catalog.json` and its signature: GitHub Pages.** Small static files, stable URL, free.
- **Binaries (apk, zip): GitHub Releases.** Up to 2 GB per file, free, stable direct links.
- The repository must be **public** (free Pages requires it, and unauthenticated downloads from Releases require it).

### URLs

- Catalog: `https://<USER>.github.io/<REPO>/catalog.json`
- Signature: `https://<USER>.github.io/<REPO>/catalog.json.sig`
- File: `https://github.com/<USER>/<REPO>/releases/download/<tag>/<filename>`

### Constraints to respect

- Do **not** use the GitHub API from the clients. Unauthenticated limit is 60 requests/hour per IP. Use only the Pages URL and direct Release download links.
- Pages sits behind a CDN with roughly a 10 minute cache. The clients should add a cache-busting query parameter (for example `?t=<unix time>`) when fetching the catalog, and the UI should offer a manual "Check for updates" button.
- Do not put binaries into the git repository itself (100 MB file limit, history bloat).
- Release tag convention: `<app-id>-<platform>-<version>`, for example `notes-android-1.5.0`.

### Alternatives (only if GitHub becomes a problem)

Cloudflare R2 (files) + Cloudflare Pages (catalog), or a VPS with nginx. The client should read the catalog base URL from a single constant/config so hosting can be swapped.

---

## 4. Catalog format

`catalog/catalog.json` is the only thing clients need. Example:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-13T12:00:00Z",
  "apps": [
    {
      "id": "my.app.notes",
      "name": "Notes",
      "description": "Short description shown in the market",
      "icon": "https://<USER>.github.io/<REPO>/icons/notes.png",
      "packages": {
        "android": {
          "package": "apk",
          "packageName": "my.app.notes",
          "versionCode": 12,
          "versionName": "1.4.0",
          "minSdk": 26,
          "signingCertSha256": "<sha256 of the signing certificate>",
          "url": "https://github.com/<USER>/<REPO>/releases/download/notes-android-1.4.0/notes-android-1.4.0.apk",
          "sha256": "<sha256 of the apk>",
          "sizeBytes": 18234567,
          "changelog": "Bug fixes"
        },
        "windows": {
          "package": "zip",
          "entry": "Notes.exe",
          "versionName": "1.4.0",
          "url": "https://github.com/<USER>/<REPO>/releases/download/notes-windows-1.4.0/notes-win-1.4.0.zip",
          "sha256": "<sha256 of the zip>",
          "sizeBytes": 45678901,
          "changelog": "Bug fixes"
        }
      }
    }
  ]
}
```

Notes:

- An app may have only one platform entry.
- Android compares `versionCode` (integer). Windows compares `versionName` using semantic versioning.
- The market itself is listed in the catalog as a normal app so it can update itself (see section 8).
- Keep `schemaVersion` so the format can evolve; clients must ignore unknown fields.

### Per-build metadata file (produced by each app's own build)

Each app's ZIP build also produces `<app-id>-win-<version>.json` next to the zip:

```json
{ "id": "<app-id>", "name": "<display name>", "platform": "windows", "package": "zip", "entry": "<entry exe name>", "versionName": "<version>", "sha256": "<sha256 of the zip>", "sizeBytes": 0 }
```

`publish.py` reads this file (and, for apks, reads package name / versionCode / versionName from the apk itself) instead of guessing from file names.

---

## 5. Android client

### Responsibilities

- Fetch and verify the catalog.
- List apps with icon, name, description, installed version, available version, and a state button: **Install / Update / Open / Up to date**.
- Download the apk with progress, verify SHA-256, install.
- Show changelog.
- "Check for updates" button and optional background check (WorkManager, periodic, for example every 6 hours, with a notification when updates exist).

### Technical points

- Detect installed version with `PackageManager.getPackageInfo(packageName)` and compare `versionCode` (`longVersionCode`) to the catalog. Declare the needed package visibility (`<queries>` entries or `QUERY_ALL_PACKAGES` only if truly needed; prefer listing the known package names in `<queries>`, generated from the catalog if practical, or use the manifest to declare them).
- Install through the **`PackageInstaller` session API** (not the deprecated `ACTION_VIEW` intent).
- Permission: `REQUEST_INSTALL_PACKAGES`. On first install the user must allow "Install unknown apps" for the market; the app should detect the missing permission and deep-link to the correct settings screen.
- Android always shows a system confirmation dialog for third-party installers. This cannot be avoided without device-owner/MDM. For updates on Android 12+ the market may call `setRequireUserAction(USER_ACTION_NOT_REQUIRED)` to reduce prompts when the market was the original installer.
- **Updates only work if the new apk is signed with the same key as the installed one.** All my apps must use one keystore. Before installing, the client may compare the apk's signing certificate hash with `signingCertSha256` from the catalog.
- Store downloads in app-specific cache storage; delete after installation.
- Verify SHA-256 before handing the file to the installer. Abort on mismatch.
- Verify the catalog signature before trusting it (see section 7).
- Handle: no internet (show last cached catalog, mark as offline), interrupted downloads (resume or restart), insufficient storage.

### Suggested stack

Kotlin + Jetpack Compose, OkHttp (or Ktor) for networking, WorkManager for background checks. Alternative: Flutter, if sharing code with the PC client is preferred.

---

## 6. Windows (PC) client

### Packaging model

PC apps are distributed to the market as **portable ZIP builds** (not installers). Reasons: no admin rights/UAC, silent updates, trivial versioning and uninstall.

The installers remain available for manual installs outside the market. Each app project has (or will get) a second build target that produces the ZIP (see section 9).

### Responsibilities

- Fetch and verify the catalog.
- List Windows apps with state button: **Install / Update / Open / Up to date**.
- Download zip, verify SHA-256, unpack, switch to the new version, create/refresh the Start Menu shortcut and repoint existing pins, launch.
- Uninstall (delete app folder, remove shortcut, optionally keep user data).
- "Check for updates" and optional check on startup.

### Install layout

```
%LocalAppData%\MyMarket\
├── installed.json                 local state: id, installed version, entry, path
├── downloads\                     temporary downloads
└── apps\
    ├── <app-id>\
    │   └── current\               the installed version (fixed name)
    └── <market-id>\
        ├── 1.0.7\                 the market itself: one folder per version
        └── 1.0.8\
```

User data must never live in these folders. Apps store data in `%AppData%` / `%LocalAppData%` under their own names, so replacing a version folder never deletes user data.

**Why `current\`:** Windows identifies a desktop app by its exe path. Start pins use it as the app ID, and taskbar pins and the icon cache are tied to it. A path with the version in it changes on every update, and the old pins go blank. A fixed `current\` folder keeps the path the same. The market cannot rename the folder it is running from, so it keeps one folder per version. After each self-update it repoints its own shortcuts and taskbar pins (see below). Its Start pin still changes ID on every self-update.

Installs from market versions before this layout used `apps\<id>\<version>\`. They move to `current\` on their next update. That update repoints taskbar pins and shortcuts. Start pins made before the move have to be re-pinned once.

### Update procedure

1. Download the zip into `downloads\` and verify SHA-256.
2. If the app is running, ask the user to close it (detect by process path under the app folder). Do not kill processes silently.
3. Unpack into a temporary folder `apps\<id>\.tmp-*\` (never over the running version).
4. Rename `current\` to `.old-*\`, then rename the unpacked folder to `current\`. If the second rename fails, rename `.old-*\` back. For the market, rename the unpacked folder to `<new-version>\` instead.
5. Set the current version in `installed.json` to the new one. If that write fails, put the old files back in `current\`.
6. Refresh the Start Menu shortcut. Then repoint every other shortcut to the same exe in an older folder of the app: the Desktop, and the pin copies under `%AppData%\Microsoft\Internet Explorer\Quick Launch\User Pinned\`. Then notify Explorer (`SHChangeNotify`) so the icon refreshes. The market also runs this repair at startup.
7. Delete `.old-*\` (and, for the market, the old version folder once the new one has started). Locked files are retried on the next market start. That start also restores `.old-*\` to `current\` if a crash happened between the two renames.
8. If anything fails before step 5, the old version stays installed.

### Technical points

- Zip-slip protection when extracting (reject entries that resolve outside the target folder).
- The ZIP may contain a single top-level folder or files at root; the client should normalize this and use the catalog's `entry` field to find the executable.
- Installed version = what `installed.json` says (and the folder exists). Compare with SemVer.
- If an app is still shipped only as an installer, a fallback is to download and run it with silent flags (`/S`, `/VERYSILENT`, `/quiet`). This brings back UAC and weaker version tracking, so treat it as a last resort.
- Unsigned executables trigger SmartScreen warnings. Code signing is recommended, but not required for the market to function.

### Suggested stack

Pick one of: Flutter desktop, .NET (WPF/Avalonia/MAUI), or Tauri/Electron. If the Android client is Flutter, using Flutter for both gives one codebase for the UI and the catalog/verification logic. The market must be able to self-update on PC (see section 8).

---

## 7. Security

The market downloads and runs code, so treat this seriously.

1. **HTTPS only** for catalog and files.
2. **SHA-256 verification** of every downloaded file against the catalog before install.
3. **Signed catalog.** `publish.py` signs `catalog.json` with an **Ed25519** private key and publishes `catalog.json.sig`. Both clients embed the **public key** and verify the signature before using the catalog. Reject catalogs with an invalid signature, and also reject catalogs whose `generatedAt` is older than the last accepted one (basic rollback protection).
4. **Android signing:** all apps use the same keystore; the client optionally checks the signing certificate hash.
5. **Secrets stay out of the repo and out of Claude's reach:**
   - The apk keystore and the Ed25519 private key live outside the project folder; `publish.py` reads their paths from environment variables (for example `MARKET_SIGNING_KEY`, `ANDROID_KEYSTORE`). Claude Code runs the signing step but must never read, print, or copy key material.
   - GitHub auth is handled by `gh auth login` (token stored by `gh`), not by files in the project.
6. The repository is public, so apps are downloadable by anyone with the link. Do not publish anything confidential.

---

## 8. Self-update of the market

The market is just another entry in the catalog (`id: "my.market"`).

- **Android:** the market can update itself through the same `PackageInstaller` flow (the system will restart it).
- **Windows:** the running exe cannot overwrite itself. Use a tiny updater step: the market downloads the new zip, launches a helper (or itself with an `--apply-update` argument) that waits for the main process to exit, swaps the version folder, and relaunches. Alternatively use a ready library such as Velopack.
- This is only needed when the market's own code changes. Adding or updating **other** apps never requires touching the market.

---

## 9. Requirements for each app (so it works with the market)

### Android apps

- Signed with the shared keystore.
- Increasing `versionCode` on every release.
- Nothing else to change.

### Windows apps (portable ZIP build)

- Self-contained: includes all runtimes/dependencies; runs on a clean machine with no installer, no admin rights, no registry writes, no services.
- A single clear entry executable.
- User data, settings and logs stored in `%AppData%` / `%LocalAppData%`, never next to the exe (migrate old data once if it was stored there).
- Output: `<app-id>-win-<version>.zip` plus `<app-id>-win-<version>.json` (metadata), with the version read from the project's single source of truth.
- Existing installer build stays untouched.

(There is a separate universal prompt for adding this ZIP build to each existing app project.)

---

## 10. Publishing tool: `scripts/publish.py`

Claude Code runs this script when I say things like "Update Notes, I dropped the files in incoming". The logic lives in the script, not in ad hoc commands, so results are identical each time.

### What it does

1. Scan `incoming/` and its app folders (`incoming/<App>/`, one per app). Identify each file:
   - `.apk`: read package name, `versionCode`, `versionName`, `minSdk` and the signing certificate SHA-256 (via `aapt2`, `apkanalyzer`, `apksigner`, or a Python APK parser).
   - `.zip` with a sibling `.json`: read id, name, entry, version from the metadata file; verify the zip hash matches.
   - Anything else or anything ambiguous: stop and ask me.

   Per app and platform, take the newest build. Skip builds that are older than the
   published version or identical to it, so old files can stay in a folder.
2. Compute SHA-256 and size.
3. Validate (see rules below). Abort on any failure.
4. Show me a short summary (app, platform, old version → new version, files) and **ask for confirmation** before uploading anything.
5. Upload via `gh release create <tag> <file>` (or `gh release upload` if the release exists).
6. Update `catalog/catalog.json` (add or update the app entry; keep other apps untouched; update `generatedAt`).
7. Sign the catalog with the Ed25519 key and write `catalog.json.sig`.
8. Commit and push the `catalog/` changes (the GitHub Actions workflow deploys Pages). Do this only after the confirmation in step 4.
9. Move processed files from `incoming/` to `archive/<app-id>/<version>/`.
10. Print a short result: what was published, the new catalog version, and the expected delay before devices see it (up to about 10 minutes because of the CDN cache).

### Validation rules (hard stops)

- Android: new `versionCode` must be **strictly greater** than the one currently in the catalog.
- Android: the apk's signing certificate must match the one already recorded for that app (a different key would make updates fail on devices).
- Windows: new version must be greater than the current one (SemVer).
- Windows: the zip hash must match the metadata file, and the entry exe must exist inside the zip.
- Release tag must not already exist.
- Required environment variables (signing key path, keystore path if needed) must be set; otherwise stop with a clear message. Never print key contents.

### Support commands (nice to have)

- `publish.py list`: show what the catalog currently contains.
- `publish.py remove <id> [platform]`: remove an app or a platform entry from the catalog (with confirmation).
- `publish.py verify`: download the live catalog, check the signature, and check that every file URL responds and matches its hash.

---

## 11. `CLAUDE.md` rules (to place in the project root)

Suggested content for the Claude Code rules file:

- This repository is a private app store. The catalog format and publishing rules are described in `MARKET_SPEC.md`.
- To publish or update an app, **always use `scripts/publish.py`**. Do not hand-edit `catalog.json` or upload releases manually.
- Files to publish are in `incoming/`. If a file is ambiguous, ask me instead of guessing.
- **Always show a summary and ask for confirmation before uploading, committing, or pushing.**
- Never read, print, copy, or commit key material (keystore, Ed25519 private key, tokens). Use environment variables only.
- Never publish a version that is not higher than the current one.
- After publishing, run `publish.py verify` and report the result honestly, including any failure.
- Do not modify the market clients while handling a publish request unless I ask.

---

## 12. GitHub Actions workflow

A workflow deploys the contents of `catalog/` (plus `icons/`) to GitHub Pages on every push to the main branch that changes those paths. Use the official `actions/upload-pages-artifact` and `actions/deploy-pages` actions. The workflow only publishes static files; it never needs access to signing keys (signing happens locally in `publish.py`).

---

## 13. One-time setup checklist (for me)

1. Create a GitHub account (if needed) and a **public** repository, for example `my-market`.
2. Install GitHub CLI (`gh`) and run `gh auth login`.
3. Enable GitHub Pages for the repository (source: GitHub Actions).
4. Generate the Ed25519 keypair outside the project folder; put the private key path in `MARKET_SIGNING_KEY`; embed the public key in both clients.
5. Make sure all Android apps use one keystore (path in `ANDROID_KEYSTORE` if the script needs it).
6. Add the ZIP build to each Windows app (separate prompt).

---

## 14. Suggested build order

1. Repository skeleton, `CLAUDE.md`, GitHub Actions workflow, empty signed catalog.
2. `publish.py` with the validation rules, tested with one real apk and one real zip.
3. Android client: catalog fetch + signature check, list, download, hash check, install, update detection.
4. Windows client: catalog fetch + signature check, list, download, hash check, unpack, switch version, launch, update detection.
5. Self-update for both clients; add the market to its own catalog.
6. Background update checks and notifications (Android), startup checks (PC).
7. Polish: icons, changelog view, uninstall, offline mode, error messages.

---

## 15. Open decisions

- Tech stack for the clients (Kotlin + Compose for Android, and for PC one of .NET / Flutter / Tauri / Electron; or Flutter for both).
- Whether to use Velopack (or similar) for the Windows self-update instead of a custom helper.
- Whether to code-sign Windows executables.
- Whether the Windows client should create Desktop/Start Menu shortcuts by default.
- Final repository name and the market's own app id.

---

### Decisions taken (October 2026)

- **Stack:** Flutter for both clients, one project in `market/` (shared UI, catalog,
  signature and download logic; Kotlin only for the Android installer and WorkManager).
- **Store identity:** name "LikeStore", app id `com.likestore.market` (Android package
  and catalog id), Windows exe `LikeStore.exe`, local folder `%LocalAppData%\LikeStore`.
- **Hosting:** repo `sallymillerdel/LikeStore`, catalog base URL in `market.json`.
- **Windows self-update:** no Velopack. Every version unpacks into its own folder, so the
  store starts the new exe with `--finish-update <pid>`. The new exe waits for the old
  process to exit and removes the old folder.
- **Code signing (Windows):** not for now (SmartScreen may warn on first run).
- **Shortcuts:** Start Menu on by default, Desktop off; both can be changed in Settings.
- **Android package visibility:** a `<queries>` launcher-intent filter makes all launchable
  apps visible, so new apps work without rebuilding the store or using `QUERY_ALL_PACKAGES`.
- **Icons:** served from `catalog/icons/<app-id>.png` (deployed with the catalog).
- **Signature file:** `catalog.json.sig` is the base64 of the raw 64-byte Ed25519 signature
  over the exact bytes of `catalog.json`. The public key is the base64 of the raw 32 bytes.

---

## 16. Known limitations (by design)

- Android always shows a system install confirmation for non-Play installers; the first install also needs the "Install unknown apps" permission.
- Updates may take up to about 10 minutes to become visible because of the Pages CDN cache.
- The public repository means the apps are downloadable by anyone who knows the link.
- Android updates fail if a new apk is signed with a different key than the installed one.
