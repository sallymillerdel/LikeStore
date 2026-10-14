# LikeStore — UI design brief

Brief for generating UI drafts of the LikeStore client. Everything below reflects
what the app actually does today (`market/lib/`); the drafts should restyle and
improve it, not invent features the backend can't support.

---

## 1. What the product is

LikeStore is a **private app store for one developer's own apps**. It is a single
Flutter app that runs on **Android phones** and **Windows PCs**. It reads a signed
catalog from the internet, shows the apps available for the current platform, and
installs, updates, opens and uninstalls them.

- One user (the developer), many devices. Usually 5–20 apps in the catalog.
- No accounts, no ratings, no reviews, no search ranking, no payments, no screenshots
  gallery. It is a personal tool: fast, calm, trustworthy.
- The main job: **open it, see what has an update, press Update.**
- The store lists itself as an app (`LikeStore`) so it can update itself.

Tone: clean, utilitarian, a bit friendly. Think "well-made system utility",
not "consumer marketplace".

## 2. Platforms and layout

| | Android | Windows |
|---|---|---|
| Form factor | Phone, portrait, ~360–430 dp wide | Desktop window, resizable, ~800–1600 px wide |
| Grid | 1 column of app cards | 2–3 columns (one column per ~460 px) |
| Side padding | 12 px | 24 px (when wider than 700 px) |
| Detail / Settings | Bottom sheet (drag handle, up to 95% height) | Same sheet, max width 640 px, centered |
| Pull to refresh | Yes | No (refresh button) |

Please draft **both**: Android phone (light + dark) and Windows desktop window (light + dark).

## 3. Visual system (current, can be refined)

- Material 3, `ColorScheme.fromSeed` with seed **#4F46E5** (indigo). Light and dark themes follow the system.
- Cards: no elevation, `surfaceContainerLow` fill, **16 px** corner radius.
- App icons: square PNG from the catalog, corner radius = 24% of size. Fallback when
  missing: `primaryContainer` tile with the app's first letter.
- Typography: Material 3 default type scale (Roboto on Android, Segoe UI on Windows).
- Icons: Material Symbols.

The drafts must stay implementable with **Flutter Material 3 widgets** (cards, filled /
tonal / outlined buttons, bottom sheets, list tiles, switches, linear progress,
banners). Custom colors and spacing are fine; exotic effects (blur glass, 3D) are not.

## 4. Screens

### 4.1 Home (app list) — the main screen

**Top app bar**
- Title: `LikeStore`
- `Update all (N)` text button with icon — only shown when 2+ apps have updates
- Refresh icon button ("Check for updates"); becomes a small spinner while loading
- Settings icon button

**Banners** (stacked above the list, rounded 12 px, icon + text + text button):
- Android only, info style: *"Allow LikeStore to install apps. Android asks for this once."* → **Allow**
- Offline, info style: *"Offline: showing the saved catalog. No internet connection."* → **Retry**
- Catalog error, error style: e.g. *"The catalog signature is invalid. Refusing to use it."* → **Retry**

**App list / grid**, sorted: apps with updates first, then installed, then not installed;
alphabetical within each group. Each card (fixed height ~124 px):

```
[icon 52]  Name (bold, 1 line)                    [Action button]
           Description (2 lines, muted)
-------------------------------------------------------------
footer: version info / progress / error (small, muted)
```

Footer variants:
- Not installed: `1.4.0 · 17.4 MB`
- Update available: `1.3.2 → 1.4.0 · 17.4 MB`
- Up to date: `Installed 1.4.0`
- Downloading: linear progress bar + `8.2 MB of 17.4 MB`
- Installing: indeterminate progress bar + `Installing...`
- Error: red error icon + message, e.g. `The connection was lost. Try again to resume it.`

Action button states:
| State | Button |
|---|---|
| Not installed | **Install** (filled) |
| Update available | **Update** (filled) |
| Installed, can open | **Open** (tonal) |
| Installed, can't open (the store itself) | **Up to date** (outlined, disabled) |
| Downloading | tonal, disabled, shows `42%` |
| Installing | tonal, disabled, `Installing` |

Ideas welcome: a clearer "Updates" section header, a count badge, or a subtle highlight
on cards with updates — as long as it stays a single scrolling list.

**Empty / loading states**
- First launch, loading: centered spinner
- No catalog and not loading: *"No catalog yet."*
- Catalog loaded but nothing for this platform: *"No apps for this device yet."*

### 4.2 App details (bottom sheet, opened by tapping a card)

- Header: icon 64 px, name (headline), app id below in small muted text (`my.app.notes`)
- Description paragraph
- Full-width action button (same states as above) + progress bar while busy + error text
- **Uninstall** outlined button with trash icon (only when installed, not for the store itself, not while busy)
- Info rows (label column ~130 px, muted):
  - Installed: `1.3.2` or `Not installed`
  - Available: `1.4.0 (12)` — the number in brackets is the Android versionCode
  - Download size: `17.4 MB`
  - Released: `2026-10-13 14:05` (optional)
  - Requires: `Android API 26+` (Android only)
- **What's new**: changelog text (plain, may be multi-line), or muted *"No changelog for this version."*

**Uninstall confirmation dialog**
- Title: `Uninstall Notes?`
- Body: *"The program is removed. Its own settings and data are kept."*
- Buttons: `Cancel` / `Uninstall` (filled)

### 4.3 Settings (bottom sheet)

Title `Settings`, then:
- **Windows only** (switches): `Start Menu shortcuts` (on by default), `Desktop shortcuts` (off), `Check for updates on startup` (on)
- **Android only** (switch): `Check for updates in the background` — subtitle *"Every few hours, with a notification when updates exist"*
- Divider
- `Store version` → `1.0.0`
- `Catalog` → subtitle `https://sallymillerdel.github.io/LikeStore/`, trailing last catalog date

### 4.4 System moments to show (optional frames)

- Android: the system "Install unknown apps" permission flow is outside our UI; just show the banner before and after.
- Android: background update notification — *"3 updates available"* with app names.
- Windows: an app is running during update → card error *"Notes is running. Close it, then try again."*
- Store self-update on Windows: the window closes and reopens; a short "Restarting to finish the update" state would be nice to design.

## 5. Sample data for the drafts

| Icon | Name | Id | Description | Installed | Available | Size | State |
|---|---|---|---|---|---|---|---|
| 📝 | Notes | my.app.notes | Quick notes with tags and offline sync | 1.3.2 | 1.4.0 | 17.4 MB | Update |
| 💸 | Budget | my.app.budget | Monthly spending tracker with categories | 2.0.1 | 2.1.0 | 9.8 MB | Downloading 47% |
| 🛍️ | LikeStore | com.likestore.market | My private app store | 1.0.0 | 1.0.0 | 22.1 MB | Up to date |
| ⏱️ | Focus Timer | my.app.focus | Pomodoro timer with daily stats | 0.9.4 | 0.9.4 | 6.2 MB | Open |
| 📷 | Photo Sorter | my.app.photosort | Sort camera photos into folders by date | — | 1.2.0 | 31.0 MB | Install |
| 🎵 | Practice Log | my.app.practice | Log music practice sessions | — | 0.3.0 | 4.5 MB | Install (no icon → letter fallback "P") |
| 🧾 | Receipts | my.app.receipts | Scan and archive receipts | 1.1.0 | 1.2.0 | 12.7 MB | Error: "The connection was lost. Try again to resume it." |

Changelog example for Notes 1.4.0:
```
- Tags can be renamed
- Faster search on large notebooks
- Fixed a crash when sharing an empty note
```

## 6. Deliverables wanted

1. Home — Android phone, light and dark, with 2 updates + 1 downloading + 1 error (data above).
2. Home — Windows window (~1280×800), light and dark, 2–3 column grid.
3. App details sheet — update-available state and downloading state.
4. Settings sheet — Android and Windows variants.
5. Banners and empty states (offline, permission needed, signature error, no apps).
6. A small component sheet: app card in every state, action button states, banner variants, icon fallback.

Optional: one or two alternative directions for the Home screen (e.g. compact list rows
instead of cards on Windows, or a dedicated "Updates" section at the top).

## 7. Constraints / don'ts

- No search, categories, ratings, reviews, screenshots, accounts, or prices.
- Keep all copy in English and as written above (it's what the app shows).
- Don't hide the version numbers: seeing `1.3.2 → 1.4.0` is a core need.
- Accessibility: WCAG AA contrast in both themes, touch targets ≥ 48 dp on Android,
  progress and errors must not rely on color alone.
