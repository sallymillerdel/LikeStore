# LikeStore

A private app store for my own Android and Windows apps (spec: [MARKET_SPEC.md](MARKET_SPEC.md)).

| Part | Where |
|---|---|
| Store client (Android + Windows, Flutter) | [`market/`](market) |
| Publisher | [`scripts/publish.py`](scripts/publish.py) |
| Catalog (signed, served by GitHub Pages) | [`catalog/`](catalog) |
| Pages deploy | [`.github/workflows/pages.yml`](.github/workflows/pages.yml) |
| Rules for Claude Code | [`CLAUDE.md`](CLAUDE.md) |
| Detailed setup guide | [`SETUP.md`](SETUP.md) |

The store reads `https://sallymillerdel.github.io/LikeStore/catalog.json`, checks its
Ed25519 signature, and downloads files from this repo's GitHub Releases. Publishing a
new app version never requires rebuilding the store.

---

## One-time setup

### 1. Turn on GitHub Pages

Repo **Settings → Pages → Build and deployment → Source: GitHub Actions**.

### 2. Create the catalog signing key

The key must live outside the repo. In PowerShell:

```powershell
setx MARKET_SIGNING_KEY "$env:USERPROFILE\.likestore\catalog_ed25519.pem"
```

Open a **new** terminal (so the variable is visible), then:

```powershell
py scripts/publish.py keygen
```

This writes the private key, puts the public key into `market.json` and
`market/lib/src/config.g.dart`, and signs the empty catalog. **Back up the .pem file.**
If you lose it, every installed store has to be rebuilt and reinstalled.

### 3. Create one Android release keystore for all apps

Android only updates an app if the new APK has the same signature as the installed one.
At the moment every APK is signed with a machine-local **debug** key, and XReel's
debug key is different from Classly's and Whylist's. Create one release keystore and
use it for every app from now on:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\.likestore\release.jks" -alias release -keyalg RSA -keysize 4096 -validity 36500
```

Then set these (with `setx`, or in your build scripts):

| Variable | Used by |
|---|---|
| `ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`release`) | the store (`market/build-android.ps1`) |
| `FLET_ANDROID_SIGNING_KEY_STORE`, `FLET_ANDROID_SIGNING_KEY_STORE_PASSWORD`, `FLET_ANDROID_SIGNING_KEY_PASSWORD`, `FLET_ANDROID_SIGNING_KEY_ALIAS` | `flet build apk` (Classly, Whylist, XReel, Luma) |

Back up the keystore and its password. On phones that already have a debug-signed copy
of an app, uninstall it once before installing the release-signed one from the store.

### 4. Commit and push

```powershell
git add -A
git commit -m "Set up LikeStore"
git push
```

The workflow deploys `catalog/` to Pages. Check it at
`https://sallymillerdel.github.io/LikeStore/catalog.json`.

### 5. Build the store and publish it into its own catalog

```powershell
powershell -ExecutionPolicy Bypass -File market\build-windows.ps1
powershell -ExecutionPolicy Bypass -File market\build-android.ps1
py scripts/publish.py publish --dry-run --description "My app store"
py scripts/publish.py publish
```

### 6. First install on each device

* **Windows:** run `LikeStore-Setup-<version>.exe` (no admin rights needed). Build it with
  `powershell -ExecutionPolicy Bypass -File market\build-installer.ps1` (needs Inno Setup 6:
  `winget install JRSoftware.InnoSetup`); it lands in `dist\`. It installs into
  `%LocalAppData%\LikeStore\apps\com.likestore.market\<version>\`, the same place the
  store's self-updates go, adds a Start Menu shortcut and an entry in *Installed apps*.
  Uninstalling removes the store but keeps apps installed through it and its settings.
  Without the installer: extract `com.likestore.market-win-<version>.zip` from the
  Releases page somewhere permanent and run `LikeStore.exe`.
* **Android:** open the Releases page on the phone, download the store APK, and allow
  "Install unknown apps" for the browser once. Inside the store, tap **Allow** when it asks
  to install apps.

---

## Everyday workflow

1. Build the app. For Windows, use its portable build: `<id>-win-<version>.zip` and `.json`.
   For Android, bump `versionCode` and build a release-signed APK.
2. Copy the files into the app's folder: `incoming/Classly/`, `incoming/Luma/`,
   `incoming/Whylist/` or `incoming/XReel/` (a new app just needs a new folder). The
   Windows `.zip` needs its `.json` next to it. Optionally add `icon.png` as the icon.
3. Tell Claude Code: *"Update the apps."* The script checks every folder, takes the newest
   build of each app and platform, and skips what's already published or older, so you can
   leave old files in a folder. Claude runs the dry run, shows you the plan, and publishes
   once you confirm. Published files move to `archive/<app-id>/<version>/`. To do it by hand:

   ```powershell
   py scripts/publish.py publish --dry-run --changelog "Bug fixes"
   py scripts/publish.py publish --changelog "Bug fixes"
   py scripts/publish.py publish --dry-run --folder Classly   # just one app
   ```

   `--changelog` applies to every build in the run, so use `--folder` when the apps need
   different changelogs. The `changelog` field in a zip's `.json` is used otherwise.

4. Devices see the update within about 10 minutes (Pages CDN cache). Press **Update**.

Other commands:

```text
py scripts/publish.py list                         what the catalog contains
py scripts/publish.py edit <id> --description ".." --icon icon.png
py scripts/publish.py remove <id> [android|windows]
py scripts/publish.py verify [--app <id>] [--quick] live catalog signature + every file hash
```

`publish.py` refuses to publish (and changes nothing) if:

* the version is not higher than the published one (older and already-published builds are
  just skipped)
* a build has the published version but different bytes (you forgot to bump the version)
* two different builds of one app have the same version
* the APK's signing certificate differs from the published one
* the zip hash doesn't match its `.json`, or the entry exe is missing from the zip
* the release tag already exists
* the signing key is missing or doesn't match `market.json`

### Notes about the existing apps

* **XReel:** the Windows build calls the app `xreel`, but the APK is `com.slx.xreel`. The
  publisher will stop and ask. Either change the id in XReel's portable build to
  `com.slx.xreel`, or publish the zip once with `--folder XReel --app-id com.slx.xreel`. After that, the
  catalog remembers the mapping.
* **Whylist** and **XReel** don't have a portable-ZIP build script yet (Classly and Luma do).
* Android apps must keep using the same keystore forever (see step 3).

---

## Development

```powershell
py -m unittest discover -s scripts      # publisher tests
cd market; flutter test; flutter analyze
```

* `market/lib/src/config.g.dart` is generated from `market.json`
  (`py scripts/publish.py sync-config`). That's the only place that knows the hosting URL.
* Android builds need JDK 17 and the SDK at `D:\dev\android-sdk`
  (`market/build-android.ps1` sets both). `kotlin.incremental=false` in
  `market/android/gradle.properties` works around a Kotlin cache bug that happens when the
  project and the pub cache are on different drives.
