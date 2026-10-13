#!/usr/bin/env python3
"""LikeStore publisher: the only supported way to change the catalog.

    py scripts/publish.py publish --dry-run       show what would be published
    py scripts/publish.py publish --yes           publish what is in incoming/
    py scripts/publish.py list                    show the catalog
    py scripts/publish.py edit ID [--name N] [--description D] [--icon PNG]
    py scripts/publish.py remove ID [android|windows] [--yes]
    py scripts/publish.py verify [--app ID] [--quick]
    py scripts/publish.py keygen                  one-time: create the catalog signing key
    py scripts/publish.py sign                    re-sign catalog.json
    py scripts/publish.py sync-config             regenerate the client config from market.json

The catalog signing key is read from the path in MARKET_SIGNING_KEY (an
unencrypted PEM Ed25519 private key, or encrypted with the passphrase in
MARKET_SIGNING_KEY_PASSWORD). Key contents are never printed.

See MARKET_SPEC.md sections 4, 7 and 10 for the rules implemented here.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from apkinfo import ApkError, read_apk  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "market.json"
CATALOG_DIR = ROOT / "catalog"
CATALOG_PATH = CATALOG_DIR / "catalog.json"
SIG_PATH = CATALOG_DIR / "catalog.json.sig"
ICONS_DIR = CATALOG_DIR / "icons"
INCOMING = ROOT / "incoming"
ARCHIVE = ROOT / "archive"
DART_CONFIG = ROOT / "market" / "lib" / "src" / "config.g.dart"

SCHEMA_VERSION = 1
PLATFORMS = ("android", "windows")


class Stop(Exception):
    """A hard stop: print the message and exit non-zero, changing nothing."""


# --- config, catalog, signing ---------------------------------------------


def load_config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def save_config(cfg: dict) -> None:
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8", newline="\n")


def load_catalog() -> dict:
    if not CATALOG_PATH.exists():
        return {"schemaVersion": SCHEMA_VERSION, "generatedAt": None, "apps": []}
    return json.loads(CATALOG_PATH.read_bytes().decode("utf-8"))


def catalog_bytes(catalog: dict) -> bytes:
    return (json.dumps(catalog, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def now_iso(after: str | None = None) -> str:
    """Current UTC time, strictly later than `after` (clients reject non-increasing)."""
    t = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    if after:
        prev = parse_iso(after)
        if t <= prev:
            t = prev + dt.timedelta(seconds=1)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def signing_key_path() -> Path:
    p = os.environ.get("MARKET_SIGNING_KEY")
    if not p:
        raise Stop(
            "MARKET_SIGNING_KEY is not set. Set it to the path of the catalog signing key "
            "(created once with `publish.py keygen`)."
        )
    return Path(p)


def load_private_key():
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import load_pem_private_key

    path = signing_key_path()
    if not path.is_file():
        raise Stop(f"MARKET_SIGNING_KEY points to a missing file: {path}")
    pw = os.environ.get("MARKET_SIGNING_KEY_PASSWORD")
    try:
        key = load_pem_private_key(path.read_bytes(), password=pw.encode() if pw else None)
    except Exception as e:  # noqa: BLE001 - never echo key material, only the error type
        raise Stop(f"Could not load the signing key at {path} ({type(e).__name__}).") from None
    if not isinstance(key, Ed25519PrivateKey):
        raise Stop(f"The key at {path} is not an Ed25519 private key.")
    return key


def public_key_b64(private_key) -> str:
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

    raw = private_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    return base64.b64encode(raw).decode()


def check_key_matches_config(private_key, cfg: dict) -> None:
    pub = public_key_b64(private_key)
    if not cfg.get("publicKey"):
        raise Stop("market.json has no publicKey. Run `publish.py keygen` first.")
    if pub != cfg["publicKey"]:
        raise Stop(
            "The key in MARKET_SIGNING_KEY does not match market.json publicKey. "
            "The clients would reject this catalog. Use the original key."
        )


def verify_signature(data: bytes, sig_b64: str, pub_b64: str) -> bool:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

    try:
        Ed25519PublicKey.from_public_bytes(base64.b64decode(pub_b64)).verify(
            base64.b64decode(sig_b64.strip()), data
        )
        return True
    except (InvalidSignature, ValueError):
        return False


def write_signed_catalog(catalog: dict, private_key) -> None:
    data = catalog_bytes(catalog)
    CATALOG_DIR.mkdir(exist_ok=True)
    CATALOG_PATH.write_bytes(data)
    SIG_PATH.write_bytes(base64.b64encode(private_key.sign(data)) + b"\n")


# --- versions -------------------------------------------------------------

_SEMVER = re.compile(r"^v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")


def semver_key(v: str):
    m = _SEMVER.match(v.strip())
    if not m:
        raise Stop(f"'{v}' is not a valid version (expected something like 1.4.0).")
    nums = [int(x) for x in m.group(1).split(".")]
    nums += [0] * (3 - len(nums)) if len(nums) < 3 else []
    pre = m.group(2)
    # A release sorts after any pre-release of the same version.
    pre_key = (1,) if pre is None else (0,) + tuple(
        (0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split(".")
    )
    return (tuple(nums), pre_key)


def semver_gt(a: str, b: str) -> bool:
    return semver_key(a) > semver_key(b)


# --- helpers --------------------------------------------------------------


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return str(n)


def run(cmd: list[str], check=True, capture=True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, check=check, text=True, capture_output=capture)


def find_app(catalog: dict, app_id: str) -> dict | None:
    return next((a for a in catalog["apps"] if a["id"] == app_id), None)


def release_url(cfg: dict, tag: str, filename: str) -> str:
    return f"https://github.com/{cfg['owner']}/{cfg['repo']}/releases/download/{tag}/{filename}"


def icon_url(cfg: dict, app_id: str, digest: str) -> str:
    return f"{cfg['catalogBaseUrl'].rstrip('/')}/icons/{app_id}.png?v={digest[:12]}"


def confirm(question: str, assume_yes: bool) -> None:
    if assume_yes:
        return
    if not sys.stdin.isatty():
        raise Stop("Confirmation needed: re-run with --yes after reviewing the summary above.")
    if input(f"{question} [y/N] ").strip().lower() not in ("y", "yes"):
        raise Stop("Cancelled. Nothing was changed.")


def entry_in_zip(zip_path: Path, entry: str) -> bool:
    """The entry exe at the root, or under a single top-level folder."""
    with zipfile.ZipFile(zip_path) as z:
        names = [n.replace("\\", "/") for n in z.namelist() if not n.endswith("/")]
    if entry in names:
        return True
    tops = {n.split("/", 1)[0] for n in names}
    return len(tops) == 1 and f"{next(iter(tops))}/{entry}" in names


# --- scanning incoming/ ---------------------------------------------------


@dataclass
class Item:
    platform: str  # android | windows
    source_id: str  # id as the build knows it (package name / metadata id)
    files: list[Path]
    upload: Path  # the file uploaded to the release
    upload_name: str
    version_name: str
    version_code: int | None = None
    name: str | None = None
    min_sdk: int | None = None
    cert: str | None = None
    entry: str | None = None
    sha256: str = ""
    size: int = 0
    changelog: str | None = None
    app_id: str = ""  # resolved catalog id
    old_version: str | None = None
    tag: str = ""
    notes: list[str] = field(default_factory=list)


def scan_incoming() -> tuple[list[Item], dict[str, Path]]:
    if not INCOMING.is_dir():
        raise Stop("incoming/ does not exist.")
    files = sorted(p for p in INCOMING.iterdir() if p.is_file() and p.name != ".gitkeep")
    if not files:
        raise Stop("incoming/ is empty. Drop the .apk, or the .zip with its .json, there first.")

    items: list[Item] = []
    icons: dict[str, Path] = {}
    used: set[Path] = set()

    for p in files:
        ext = p.suffix.lower()
        if ext == ".apk":
            try:
                info = read_apk(str(p))
            except ApkError as e:
                raise Stop(str(e)) from None
            items.append(
                Item(
                    platform="android",
                    source_id=info.package_name,
                    files=[p],
                    upload=p,
                    upload_name=f"{info.package_name}-android-{info.version_name}.apk",
                    version_name=info.version_name,
                    version_code=info.version_code,
                    name=info.label,
                    min_sdk=info.min_sdk,
                    cert=info.signing_cert_sha256,
                    sha256=sha256_file(p),
                    size=p.stat().st_size,
                )
            )
            used.add(p)
        elif ext == ".zip":
            meta_path = p.with_suffix(".json")
            if not meta_path.exists():
                raise Stop(f"{p.name}: no metadata file {meta_path.name} next to it.")
            items.append(windows_item(p, meta_path))
            used.update({p, meta_path})
        elif ext == ".png":
            icons[p.stem] = p
            used.add(p)

    leftovers = [p.name for p in files if p not in used]
    if leftovers:
        raise Stop(
            "Don't know what to do with: " + ", ".join(leftovers)
            + ". Expected .apk, .zip + .json, or <app-id>.png. Remove them or ask."
        )
    if not items and icons:
        raise Stop("Only icons in incoming/. Use `publish.py edit <id> --icon <file>` for that.")
    return items, icons


def windows_item(zip_path: Path, meta_path: Path) -> Item:
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        raise Stop(f"{meta_path.name}: invalid JSON ({e}).") from None
    for k in ("id", "entry", "versionName", "sha256"):
        if not meta.get(k):
            raise Stop(f"{meta_path.name}: missing '{k}'.")
    if meta.get("platform", "windows") != "windows" or meta.get("package", "zip") != "zip":
        raise Stop(f"{meta_path.name}: only platform=windows, package=zip is supported.")

    digest = sha256_file(zip_path)
    if digest != meta["sha256"].lower():
        raise Stop(f"{zip_path.name}: SHA-256 does not match {meta_path.name}. Rebuild the zip.")
    size = zip_path.stat().st_size
    if meta.get("sizeBytes") and int(meta["sizeBytes"]) != size:
        raise Stop(f"{zip_path.name}: size does not match {meta_path.name}.")
    if not entry_in_zip(zip_path, meta["entry"]):
        raise Stop(f"{zip_path.name}: entry '{meta['entry']}' is not inside the zip.")
    semver_key(meta["versionName"])

    return Item(
        platform="windows",
        source_id=meta["id"],
        files=[zip_path, meta_path],
        upload=zip_path,
        upload_name=zip_path.name,
        version_name=meta["versionName"],
        name=meta.get("name"),
        entry=meta["entry"],
        sha256=digest,
        size=size,
        changelog=meta.get("changelog"),
    )


def resolve_ids(items: list[Item], catalog: dict, forced_id: str | None) -> None:
    """Decide which catalog entry each item belongs to (see CLAUDE.md: ask when ambiguous)."""
    if forced_id and len({i.source_id for i in items}) > 1:
        raise Stop("--app-id applies to one app at a time, but incoming/ holds several apps.")

    for it in items:
        if forced_id:
            it.app_id = forced_id
            continue
        match = None
        for app in catalog["apps"]:
            pkg = app.get("packages", {}).get(it.platform) or {}
            if it.platform == "android" and pkg.get("packageName") == it.source_id:
                match = app
            elif it.platform == "windows" and pkg.get("sourceId") == it.source_id:
                match = app
        if match is None:
            match = find_app(catalog, it.source_id)
        it.app_id = match["id"] if match else it.source_id

    # A new id whose name matches another app is probably the same app under a
    # different id (e.g. an apk com.x.notes and a zip "notes").
    known = {a["id"]: a.get("name", "") for a in catalog["apps"]}
    for it in items:
        if it.name:
            known.setdefault(it.app_id, it.name)
    for it in items:
        if find_app(catalog, it.app_id) or forced_id:
            continue
        same = [i for i, n in known.items() if i != it.app_id and it.name and n.lower() == it.name.lower()]
        if same:
            raise Stop(
                f"{it.platform} build '{it.source_id}' looks like the existing app '{same[0]}' "
                f"(same name '{it.name}') but has a different id. If it is the same app, re-run "
                f"with --app-id {same[0]}; if it is a different app, pass --app-id {it.app_id}."
            )


def validate(items: list[Item], catalog: dict, cfg: dict, args) -> None:
    seen = set()
    for it in items:
        key = (it.app_id, it.platform)
        if key in seen:
            raise Stop(f"incoming/ has two {it.platform} builds for {it.app_id}.")
        seen.add(key)

        app = find_app(catalog, it.app_id)
        cur = (app or {}).get("packages", {}).get(it.platform)
        if it.platform == "android":
            if cur:
                it.old_version = f"{cur['versionName']} (code {cur['versionCode']})"
                if it.version_code <= int(cur["versionCode"]):
                    raise Stop(
                        f"{it.app_id}: versionCode {it.version_code} is not greater than the "
                        f"published {cur['versionCode']}. Bump versionCode and rebuild."
                    )
                if cur.get("packageName") and cur["packageName"] != it.source_id:
                    raise Stop(
                        f"{it.app_id}: package name {it.source_id} differs from the published "
                        f"{cur['packageName']}. Android would treat it as a different app."
                    )
                if cur.get("signingCertSha256") and cur["signingCertSha256"] != it.cert:
                    raise Stop(
                        f"{it.app_id}: the apk is signed with a different certificate "
                        f"({it.cert[:16]}...) than the published one "
                        f"({cur['signingCertSha256'][:16]}...). Devices would refuse the update. "
                        "Sign it with the shared keystore."
                    )
            others = {
                a["packages"]["android"].get("signingCertSha256")
                for a in catalog["apps"]
                if a["id"] != it.app_id and a.get("packages", {}).get("android")
            } - {None}
            if others and it.cert not in others:
                it.notes.append(
                    "warning: signing certificate differs from the other apps in the catalog "
                    "(all apps should share one keystore)"
                )
        else:
            if cur:
                it.old_version = cur["versionName"]
                if not semver_gt(it.version_name, cur["versionName"]):
                    raise Stop(
                        f"{it.app_id}: version {it.version_name} is not greater than the "
                        f"published {cur['versionName']}."
                    )

        if not app and not (args.name or it.name):
            raise Stop(f"{it.app_id} is a new app and its name is unknown. Re-run with --name.")

        it.tag = f"{it.app_id}-{it.platform}-{it.version_name}"
        if not re.fullmatch(r"[A-Za-z0-9._+-]+", it.tag):
            raise Stop(f"Release tag '{it.tag}' contains unsupported characters.")
        if release_exists(cfg, it.tag):
            raise Stop(
                f"Release {it.tag} already exists. Publish a new version "
                "(for android, bump versionName too, since the tag uses it)."
            )


def release_exists(cfg: dict, tag: str) -> bool:
    r = run(["gh", "release", "view", tag, "-R", f"{cfg['owner']}/{cfg['repo']}"], check=False)
    if r.returncode == 0:
        return True
    err = (r.stderr or "").lower()
    if "not found" in err or "could not find" in err:
        return False
    raise Stop(f"Could not ask GitHub whether release {tag} exists: {r.stderr.strip()}")


def check_git_ready() -> None:
    if run(["git", "status", "--porcelain", "--", "catalog"]).stdout.strip():
        raise Stop("catalog/ has uncommitted changes. Commit or discard them first.")
    run(["git", "fetch", "-q", "origin"], check=False)
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
    r = run(["git", "rev-list", "--count", f"HEAD..origin/{branch}"], check=False)
    if r.returncode == 0 and int(r.stdout.strip() or 0) > 0:
        raise Stop(f"Local {branch} is behind origin. Run `git pull` first.")


# --- commands -------------------------------------------------------------


def cmd_publish(args) -> None:
    cfg = load_config()
    key = load_private_key()
    check_key_matches_config(key, cfg)
    catalog = load_catalog()
    check_git_ready()

    items, icons = scan_incoming()
    resolve_ids(items, catalog, args.app_id)
    validate(items, catalog, cfg, args)
    for app_id in icons:
        if app_id not in {i.app_id for i in items}:
            raise Stop(f"Icon {app_id}.png does not belong to any app being published.")

    print("Publish plan")
    print("============")
    for it in items:
        app = find_app(catalog, it.app_id)
        name = args.name or (app or {}).get("name") or it.name
        print(f"\n{name}  [{it.app_id}]  {it.platform}" + ("  (NEW APP)" if not app else ""))
        print(f"  version:  {it.old_version or '-'}  ->  {it.version_name}"
              + (f" (code {it.version_code})" if it.version_code is not None else ""))
        print(f"  file:     {it.upload.name} ({human_size(it.size)})  sha256 {it.sha256[:16]}...")
        print(f"  release:  {it.tag}")
        if it.platform == "android":
            print(f"  package:  {it.source_id}, minSdk {it.min_sdk}, cert {it.cert[:16]}...")
        else:
            print(f"  entry:    {it.entry}")
        changelog = args.changelog if args.changelog is not None else it.changelog
        print(f"  changelog: {changelog or '(none)'}")
        if it.app_id in icons:
            print(f"  icon:     {icons[it.app_id].name}")
        for n in it.notes:
            print(f"  {n}")
    print(f"\nThen: update catalog.json, sign it, commit and {'(not) ' if args.no_push else ''}push catalog/.")

    if args.dry_run:
        print("\nDry run: nothing was uploaded or changed.")
        return
    confirm("Upload and publish?", args.yes)

    # 1. Upload.
    repo = f"{cfg['owner']}/{cfg['repo']}"
    with tempfile.TemporaryDirectory() as tmp:
        for it in items:
            staged = Path(tmp) / it.upload_name
            shutil.copyfile(it.upload, staged)
            changelog = args.changelog if args.changelog is not None else it.changelog
            print(f"Uploading {it.upload_name} to release {it.tag} ...", flush=True)
            r = run(
                ["gh", "release", "create", it.tag, str(staged), "-R", repo,
                 "--title", f"{it.app_id} {it.platform} {it.version_name}",
                 "--notes", changelog or f"{it.platform} {it.version_name}", "--latest=false"],
                check=False,
            )
            if r.returncode != 0:
                raise Stop(f"Upload of {it.tag} failed: {r.stderr.strip()}\n"
                           "The catalog was not changed. Earlier releases in this run (if any) "
                           "exist on GitHub but are not referenced yet.")

    # 2. Catalog.
    for it in items:
        app = find_app(catalog, it.app_id)
        if app is None:
            app = {"id": it.app_id, "name": args.name or it.name, "description": "", "packages": {}}
            catalog["apps"].append(app)
        if args.name:
            app["name"] = args.name
        if args.description is not None:
            app["description"] = args.description
        changelog = args.changelog if args.changelog is not None else it.changelog
        url = release_url(cfg, it.tag, it.upload_name)
        if it.platform == "android":
            pkg = {
                "package": "apk",
                "packageName": it.source_id,
                "versionCode": it.version_code,
                "versionName": it.version_name,
                "minSdk": it.min_sdk,
                "signingCertSha256": it.cert,
            }
        else:
            pkg = {"package": "zip", "entry": it.entry, "versionName": it.version_name}
            if it.source_id != it.app_id:
                pkg["sourceId"] = it.source_id
        pkg.update({"url": url, "sha256": it.sha256, "sizeBytes": it.size,
                    "changelog": changelog or "", "releasedAt": now_iso()})
        app.setdefault("packages", {})[it.platform] = pkg
        if it.app_id in icons:
            ICONS_DIR.mkdir(parents=True, exist_ok=True)
            dst = ICONS_DIR / f"{it.app_id}.png"
            shutil.copyfile(icons[it.app_id], dst)
            app["icon"] = icon_url(cfg, it.app_id, sha256_file(dst))

    catalog["schemaVersion"] = SCHEMA_VERSION
    catalog["generatedAt"] = now_iso(catalog.get("generatedAt"))
    catalog["apps"].sort(key=lambda a: a.get("name", a["id"]).lower())
    write_signed_catalog(catalog, key)

    # 3. Commit and push.
    summary = ", ".join(f"{it.app_id} {it.platform} {it.version_name}" for it in items)
    run(["git", "add", "--", "catalog"])
    run(["git", "commit", "-q", "-m", f"Publish {summary}", "--", "catalog"])
    pushed = False
    if not args.no_push:
        r = run(["git", "push", "-q"], check=False)
        pushed = r.returncode == 0
        if not pushed:
            print(f"\nWARNING: git push failed: {r.stderr.strip()}\nThe commit is local; push it manually.")

    # 4. Archive.
    for it in items:
        dest = ARCHIVE / it.app_id / it.version_name
        dest.mkdir(parents=True, exist_ok=True)
        for f in it.files:
            shutil.move(str(f), dest / f.name)
        if it.app_id in icons and icons[it.app_id].exists():
            shutil.move(str(icons[it.app_id]), dest / icons[it.app_id].name)

    print(f"\nPublished: {summary}")
    print(f"Catalog generatedAt: {catalog['generatedAt']}")
    if pushed:
        print("Pushed. GitHub Pages redeploys in about a minute; devices may see it after up to "
              "~10 minutes (CDN cache). Then run `publish.py verify`.")


def cmd_list(args) -> None:
    catalog = load_catalog()
    print(f"generatedAt: {catalog.get('generatedAt')}   apps: {len(catalog['apps'])}")
    for app in catalog["apps"]:
        print(f"\n{app.get('name')}  [{app['id']}]")
        for plat, pkg in app.get("packages", {}).items():
            code = f" (code {pkg['versionCode']})" if "versionCode" in pkg else ""
            print(f"  {plat:8} {pkg['versionName']}{code}  {human_size(pkg.get('sizeBytes', 0))}")


def cmd_edit(args) -> None:
    cfg = load_config()
    key = load_private_key()
    check_key_matches_config(key, cfg)
    check_git_ready()
    catalog = load_catalog()
    app = find_app(catalog, args.id)
    if not app:
        raise Stop(f"No app '{args.id}' in the catalog.")
    if args.name:
        app["name"] = args.name
    if args.description is not None:
        app["description"] = args.description
    if args.icon:
        src = Path(args.icon)
        if src.suffix.lower() != ".png" or not src.is_file():
            raise Stop("--icon must be an existing .png file.")
        ICONS_DIR.mkdir(parents=True, exist_ok=True)
        dst = ICONS_DIR / f"{app['id']}.png"
        shutil.copyfile(src, dst)
        app["icon"] = icon_url(cfg, app["id"], sha256_file(dst))
    print(json.dumps({k: v for k, v in app.items() if k != "packages"}, indent=2))
    if args.dry_run:
        print("Dry run: nothing was changed.")
        return
    confirm("Save, sign, commit and push?", args.yes)
    catalog["generatedAt"] = now_iso(catalog.get("generatedAt"))
    write_signed_catalog(catalog, key)
    commit_and_push(f"Edit {app['id']}", args.no_push)


def cmd_remove(args) -> None:
    cfg = load_config()
    key = load_private_key()
    check_key_matches_config(key, cfg)
    check_git_ready()
    catalog = load_catalog()
    app = find_app(catalog, args.id)
    if not app:
        raise Stop(f"No app '{args.id}' in the catalog.")
    if args.platform:
        if args.platform not in app.get("packages", {}):
            raise Stop(f"{args.id} has no {args.platform} package.")
        what = f"the {args.platform} package of {app.get('name')} [{args.id}]"
    else:
        what = f"{app.get('name')} [{args.id}] entirely"
    print(f"Remove {what} from the catalog. (GitHub releases are kept.)")
    confirm("Remove?", args.yes)
    if args.platform:
        del app["packages"][args.platform]
        if not app["packages"]:
            catalog["apps"].remove(app)
    else:
        catalog["apps"].remove(app)
    catalog["generatedAt"] = now_iso(catalog.get("generatedAt"))
    write_signed_catalog(catalog, key)
    commit_and_push(f"Remove {args.id} {args.platform or ''}".strip(), args.no_push)


def commit_and_push(message: str, no_push: bool) -> None:
    run(["git", "add", "--", "catalog"])
    run(["git", "commit", "-q", "-m", message, "--", "catalog"])
    if no_push:
        print("Committed (not pushed).")
        return
    r = run(["git", "push", "-q"], check=False)
    print("Committed and pushed." if r.returncode == 0 else f"Committed, but push failed: {r.stderr.strip()}")


def http_get(url: str, method="GET"):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "LikeStore-publish"})
    return urllib.request.urlopen(req, timeout=60)


def cmd_verify(args) -> None:
    import time

    cfg = load_config()
    base = cfg["catalogBaseUrl"].rstrip("/")
    t = int(time.time())
    problems = 0
    try:
        live = http_get(f"{base}/catalog.json?t={t}").read()
        sig = http_get(f"{base}/catalog.json.sig?t={t}").read().decode()
    except Exception as e:  # noqa: BLE001
        raise Stop(f"Could not download the live catalog from {base}: {e}") from None

    if verify_signature(live, sig, cfg["publicKey"]):
        print("Live catalog signature: OK")
    else:
        print("Live catalog signature: INVALID")
        problems += 1
    catalog = json.loads(live)
    local = load_catalog()
    if catalog.get("generatedAt") != local.get("generatedAt"):
        print(f"Note: live generatedAt {catalog.get('generatedAt')} differs from local "
              f"{local.get('generatedAt')} (Pages deploy or CDN cache may still be pending).")

    for app in catalog["apps"]:
        if args.app and app["id"] != args.app:
            continue
        for plat, pkg in app.get("packages", {}).items():
            label = f"{app['id']} {plat} {pkg['versionName']}"
            try:
                if args.quick:
                    with http_get(pkg["url"], "HEAD") as r:
                        size = int(r.headers.get("Content-Length", -1))
                    ok = size == pkg["sizeBytes"]
                    detail = f"size {size}"
                else:
                    h = hashlib.sha256()
                    with http_get(pkg["url"]) as r:
                        for chunk in iter(lambda: r.read(1 << 20), b""):
                            h.update(chunk)
                    ok = h.hexdigest() == pkg["sha256"]
                    detail = "sha256 matches" if ok else "SHA-256 MISMATCH"
            except Exception as e:  # noqa: BLE001
                ok, detail = False, f"download failed: {e}"
            print(f"  {'OK  ' if ok else 'FAIL'} {label}: {detail}")
            problems += 0 if ok else 1
    if problems:
        raise Stop(f"verify found {problems} problem(s).")
    print("verify: all good.")


def cmd_keygen(args) -> None:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import (
        BestAvailableEncryption, Encoding, NoEncryption, PrivateFormat)

    path = signing_key_path().resolve()
    if path.exists():
        raise Stop(f"{path} already exists. Refusing to overwrite a signing key.")
    if ROOT in path.parents:
        raise Stop("The signing key must live outside the repository.")
    cfg = load_config()
    if cfg.get("publicKey") and not args.force:
        raise Stop("market.json already has a publicKey. Installed clients trust only that key. "
                   "Use --force to replace it (every client must then be rebuilt and reinstalled).")
    key = Ed25519PrivateKey.generate()
    pw = os.environ.get("MARKET_SIGNING_KEY_PASSWORD")
    enc = BestAvailableEncryption(pw.encode()) if pw else NoEncryption()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, enc))
    cfg["publicKey"] = public_key_b64(key)
    save_config(cfg)
    write_dart_config(cfg)
    catalog = load_catalog()
    catalog["generatedAt"] = now_iso(catalog.get("generatedAt"))
    write_signed_catalog(catalog, key)
    print(f"Signing key written to {path} (keep it safe and backed up, never commit it).")
    print(f"Public key: {cfg['publicKey']}")
    print("Updated market.json, market/lib/src/config.g.dart and signed catalog/catalog.json.")


def cmd_sign(args) -> None:
    cfg = load_config()
    key = load_private_key()
    check_key_matches_config(key, cfg)
    catalog = load_catalog()
    catalog["generatedAt"] = now_iso(catalog.get("generatedAt"))
    write_signed_catalog(catalog, key)
    print(f"Signed catalog.json (generatedAt {catalog['generatedAt']}).")


def write_dart_config(cfg: dict) -> None:
    def s(v):
        return json.dumps(v or "")  # JSON string literal is a valid Dart string literal here

    DART_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    DART_CONFIG.write_text(
        "// GENERATED by `scripts/publish.py sync-config` from market.json. Do not edit.\n\n"
        f"const String kStoreName = {s(cfg.get('storeName'))};\n"
        f"const String kCatalogBaseUrl = {s(cfg.get('catalogBaseUrl'))};\n"
        f"const String kCatalogPublicKey = {s(cfg.get('publicKey'))};\n"
        f"const String kMarketAppId = {s(cfg.get('marketAppId'))};\n",
        encoding="utf-8",
        newline="\n",
    )


def cmd_sync_config(args) -> None:
    write_dart_config(load_config())
    print(f"Wrote {DART_CONFIG.relative_to(ROOT)}.")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="publish.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("publish", help="publish what is in incoming/")
    p.add_argument("--dry-run", action="store_true", help="only show the plan")
    p.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    p.add_argument("--no-push", action="store_true", help="commit but do not push")
    p.add_argument("--changelog", help="changelog text for this version")
    p.add_argument("--app-id", help="catalog id to publish under (merges e.g. apk + zip ids)")
    p.add_argument("--name", help="display name (required for a new app without a known name)")
    p.add_argument("--description", help="short description shown in the store")
    p.set_defaults(fn=cmd_publish)

    sub.add_parser("list", help="show the catalog").set_defaults(fn=cmd_list)

    p = sub.add_parser("edit", help="change name, description or icon of an app")
    p.add_argument("id")
    p.add_argument("--name")
    p.add_argument("--description")
    p.add_argument("--icon", help="path to a .png")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--no-push", action="store_true")
    p.set_defaults(fn=cmd_edit)

    p = sub.add_parser("remove", help="remove an app or one platform from the catalog")
    p.add_argument("id")
    p.add_argument("platform", nargs="?", choices=PLATFORMS)
    p.add_argument("--yes", action="store_true")
    p.add_argument("--no-push", action="store_true")
    p.set_defaults(fn=cmd_remove)

    p = sub.add_parser("verify", help="check the live catalog and every file")
    p.add_argument("--app", help="only check this app id")
    p.add_argument("--quick", action="store_true", help="check sizes via HEAD instead of hashing")
    p.set_defaults(fn=cmd_verify)

    p = sub.add_parser("keygen", help="one-time: create the catalog signing key")
    p.add_argument("--force", action="store_true", help="replace an existing public key")
    p.set_defaults(fn=cmd_keygen)

    sub.add_parser("sign", help="re-sign catalog.json").set_defaults(fn=cmd_sign)
    sub.add_parser("sync-config", help="regenerate market/lib/src/config.g.dart").set_defaults(
        fn=cmd_sync_config)

    args = ap.parse_args(argv)
    try:
        args.fn(args)
    except Stop as e:
        print(f"STOP: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    sys.exit(main())
