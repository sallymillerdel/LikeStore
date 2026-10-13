# LikeStore — rules for Claude Code

This repository is a private app store for my own Android and Windows apps.
The catalog format and publishing rules are in `MARKET_SPEC.md`; setup and the
day-to-day workflow are in `README.md`.

## Publishing ("Update Notes, I dropped the files")

1. Always use `scripts/publish.py`. Never hand-edit `catalog/catalog.json` or
   `catalog.json.sig`, and never upload releases with `gh` directly.
2. Files to publish are in `incoming/`: an `.apk`, and/or a `.zip` with its
   `.json` metadata, optionally `<app-id>.png` as the icon.
3. First run the dry run and show me its summary:
   `py scripts/publish.py publish --dry-run [--changelog "..."]`
4. **Ask me for confirmation before uploading, committing or pushing.** Only
   after I say yes: `py scripts/publish.py publish --yes [same options]`.
5. If the script stops (STOP: ...), report the message. Do not work around a
   validation rule. If a file is ambiguous (e.g. an apk and a zip of the same
   app with different ids), ask me which `--app-id` to use instead of guessing.
6. Never publish a version that is not higher than the current one.
7. After publishing, wait a few minutes for Pages, then run
   `py scripts/publish.py verify --app <id>` and report the result honestly,
   including any failure.

Other changes go through the script too: `edit` (name, description, icon),
`remove`, `list`, `verify`.

## Secrets

- Never read, print, copy or commit key material: the Ed25519 catalog key
  (`MARKET_SIGNING_KEY`), the Android keystore (`ANDROID_KEYSTORE`) and its
  passwords, GitHub tokens. Refer to them only through environment variables.
- `publish.py keygen` is a one-time step I run myself; do not run it again
  (installed clients trust only the current public key).

## Code

- `market/` is the Flutter client (Android + Windows, one codebase).
  `market/lib/src/config.g.dart` is generated from `market.json` by
  `publish.py sync-config`; don't edit it by hand.
- Do not modify the clients while handling a publish request unless I ask.
- Tests: `py -m unittest discover -s scripts` and `flutter test` in `market/`.
- Building Android needs JDK 17 and the SDK at `D:\dev\android-sdk`;
  `market/build-android.ps1` sets both.
