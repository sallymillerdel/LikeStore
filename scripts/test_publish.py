"""Tests for publish.py that need no network, no GitHub and no real key.

    py -m unittest discover -s scripts
"""

import argparse
import base64
import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import publish
from publish import Item, Stop


def args(**kw):
    base = dict(name=None, description=None, changelog=None, app_id=None)
    base.update(kw)
    return argparse.Namespace(**base)


def android_item(code=2, cert="aa" * 32, pkg="com.x.notes", name="Notes"):
    return Item(platform="android", source_id=pkg, files=[], upload=Path("x.apk"),
                upload_name="x.apk", version_name=f"1.{code}.0", version_code=code,
                name=name, cert=cert)


def catalog_with_android(code=1, cert="aa" * 32):
    return {"apps": [{"id": "com.x.notes", "name": "Notes", "packages": {"android": {
        "packageName": "com.x.notes", "versionCode": code, "versionName": "1.0.0",
        "signingCertSha256": cert}}}]}


class SemverTest(unittest.TestCase):
    def test_order(self):
        self.assertTrue(publish.semver_gt("1.10.0", "1.9.9"))
        self.assertTrue(publish.semver_gt("1.4.1", "1.4"))
        self.assertTrue(publish.semver_gt("2.0.0", "2.0.0-beta.2"))
        self.assertTrue(publish.semver_gt("2.0.0-beta.10", "2.0.0-beta.2"))
        self.assertFalse(publish.semver_gt("1.4.0", "1.4.0"))
        self.assertFalse(publish.semver_gt("1.4.0+build5", "1.4.0"))

    def test_invalid(self):
        with self.assertRaises(Stop):
            publish.semver_key("latest")


class ZipTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())

    def make_zip(self, names):
        p = self.dir / "notes-win-1.5.0.zip"
        with zipfile.ZipFile(p, "w") as z:
            for n in names:
                z.writestr(n, "x")
        return p

    def write_meta(self, zip_path, **over):
        meta = {"id": "notes", "name": "Notes", "platform": "windows", "package": "zip",
                "entry": "Notes.exe", "versionName": "1.5.0",
                "sha256": publish.sha256_file(zip_path), "sizeBytes": zip_path.stat().st_size}
        meta.update(over)
        m = zip_path.with_suffix(".json")
        # PowerShell writes a BOM; make sure that is accepted.
        m.write_text(json.dumps(meta), encoding="utf-8-sig")
        return m

    def test_entry_root_and_single_folder(self):
        self.assertTrue(publish.entry_in_zip(self.make_zip(["Notes.exe", "lib/a.dll"]), "Notes.exe"))
        self.assertTrue(publish.entry_in_zip(self.make_zip(["Notes/Notes.exe", "Notes/a.dll"]), "Notes.exe"))
        self.assertFalse(publish.entry_in_zip(self.make_zip(["a/Notes.exe", "b/x.dll"]), "Notes.exe"))

    def test_windows_item_ok(self):
        z = self.make_zip(["Notes.exe"])
        it = publish.windows_item(z, self.write_meta(z))
        self.assertEqual((it.source_id, it.version_name, it.entry), ("notes", "1.5.0", "Notes.exe"))

    def test_hash_mismatch_stops(self):
        z = self.make_zip(["Notes.exe"])
        with self.assertRaises(Stop):
            publish.windows_item(z, self.write_meta(z, sha256="00" * 32))

    def test_missing_entry_stops(self):
        z = self.make_zip(["Other.exe"])
        with self.assertRaises(Stop):
            publish.windows_item(z, self.write_meta(z))


class ValidateTest(unittest.TestCase):
    cfg = {"owner": "o", "repo": "r"}

    def run_validate(self, items, catalog, **kw):
        with mock.patch.object(publish, "release_exists", return_value=False):
            publish.validate(items, catalog, self.cfg, args(**kw))

    def test_android_update_ok(self):
        it = android_item(code=2)
        publish.resolve_ids([it], catalog_with_android(1), None)
        self.run_validate([it], catalog_with_android(1))
        self.assertEqual(it.tag, "com.x.notes-android-1.2.0")

    def test_android_same_code_stops(self):
        it = android_item(code=1)
        publish.resolve_ids([it], catalog_with_android(1), None)
        with self.assertRaises(Stop):
            self.run_validate([it], catalog_with_android(1))

    def test_android_other_cert_stops(self):
        it = android_item(code=2, cert="bb" * 32)
        publish.resolve_ids([it], catalog_with_android(1), None)
        with self.assertRaises(Stop):
            self.run_validate([it], catalog_with_android(1))

    def test_windows_not_newer_stops(self):
        cat = {"apps": [{"id": "notes", "name": "Notes", "packages": {"windows": {"versionName": "1.5.0"}}}]}
        it = Item(platform="windows", source_id="notes", files=[], upload=Path("n.zip"),
                  upload_name="n.zip", version_name="1.5.0", name="Notes")
        publish.resolve_ids([it], cat, None)
        with self.assertRaises(Stop):
            self.run_validate([it], cat)

    def test_existing_tag_stops(self):
        it = android_item(code=2)
        publish.resolve_ids([it], catalog_with_android(1), None)
        with mock.patch.object(publish, "release_exists", return_value=True):
            with self.assertRaises(Stop):
                publish.validate([it], catalog_with_android(1), self.cfg, args())

    def test_same_name_different_id_is_ambiguous(self):
        cat = catalog_with_android(1)
        it = Item(platform="windows", source_id="notes", files=[], upload=Path("n.zip"),
                  upload_name="n.zip", version_name="1.0.0", name="Notes")
        with self.assertRaises(Stop):
            publish.resolve_ids([it], cat, None)
        publish.resolve_ids([it], cat, "com.x.notes")
        self.assertEqual(it.app_id, "com.x.notes")

    def test_windows_matched_by_source_id(self):
        cat = {"apps": [{"id": "com.x.notes", "name": "Notes", "packages": {
            "windows": {"versionName": "1.0.0", "sourceId": "notes"}}}]}
        it = Item(platform="windows", source_id="notes", files=[], upload=Path("n.zip"),
                  upload_name="n.zip", version_name="1.1.0", name="Notes")
        publish.resolve_ids([it], cat, None)
        self.assertEqual(it.app_id, "com.x.notes")


class AppFoldersTest(unittest.TestCase):
    """incoming/<App>/ folders: newest build per app wins, published ones are skipped."""

    def setUp(self):
        self.incoming = Path(tempfile.mkdtemp())
        patcher = mock.patch.object(publish, "INCOMING", self.incoming)
        patcher.start()
        self.addCleanup(patcher.stop)

    def drop_zip(self, folder, version, app_id="notes", content="x"):
        d = self.incoming / folder
        d.mkdir(exist_ok=True)
        z = d / f"{app_id}-win-{version}.zip"
        with zipfile.ZipFile(z, "w") as f:
            f.writestr("Notes.exe", content)
        meta = {"id": app_id, "name": app_id.title(), "entry": "Notes.exe", "versionName": version,
                "sha256": publish.sha256_file(z)}
        z.with_suffix(".json").write_text(json.dumps(meta), encoding="utf-8")
        return z

    def scan(self, catalog, folder=None):
        found, icons = publish.scan_incoming(folder)
        publish.resolve_ids(found, catalog, None)
        new, skipped = publish.select_new(found, catalog)
        return new, skipped, publish.resolve_icons(icons, found)

    def published(self, version, sha="00" * 32):
        return {"apps": [{"id": "notes", "name": "Notes", "packages": {
            "windows": {"versionName": version, "sha256": sha}}}]}

    def test_newest_build_in_folder_wins(self):
        self.drop_zip("Notes", "1.0.0")
        self.drop_zip("Notes", "1.2.0")
        self.drop_zip("Notes", "1.10.0")
        new, skipped, _ = self.scan(self.published("1.0.0"))
        self.assertEqual([i.version_name for i in new], ["1.10.0"])
        self.assertEqual(sorted(i.version_name for i, _ in skipped), ["1.0.0", "1.2.0"])

    def test_several_folders_and_root(self):
        self.drop_zip("Notes", "1.1.0")
        self.drop_zip("Todo", "2.0.0", app_id="todo")
        (self.incoming / "desktop.ini").write_text("")
        new, _, _ = self.scan({"apps": []})
        self.assertEqual(sorted(i.app_id for i in new), ["notes", "todo"])
        new, _, _ = self.scan({"apps": []}, folder="Todo")
        self.assertEqual([i.app_id for i in new], ["todo"])

    def test_already_published_is_skipped(self):
        z = self.drop_zip("Notes", "1.0.0")
        new, skipped, _ = self.scan(self.published("1.0.0", publish.sha256_file(z)))
        self.assertEqual(new, [])
        self.assertEqual(skipped[0][1], "already published")

    def test_same_version_other_bytes_is_kept_for_validate_to_stop(self):
        self.drop_zip("Notes", "1.0.0")
        new, _, _ = self.scan(self.published("1.0.0"))
        self.assertEqual(len(new), 1)
        with mock.patch.object(publish, "release_exists", return_value=False):
            with self.assertRaises(Stop):
                publish.validate(new, self.published("1.0.0"), {}, args())

    def test_two_different_builds_same_version_stop(self):
        self.drop_zip("Notes", "1.1.0", content="a")
        self.drop_zip("Notes2", "1.1.0", content="b")
        with self.assertRaises(Stop):
            self.scan(self.published("1.0.0"))

    def test_icon_png_in_folder_belongs_to_its_app(self):
        self.drop_zip("Notes", "1.1.0")
        (self.incoming / "Notes" / "icon.png").write_bytes(b"\x89PNG")
        _, _, (icons, notes) = self.scan(self.published("1.0.0"))
        self.assertEqual(list(icons), ["notes"])
        self.assertEqual(notes, [])

    def test_unknown_file_in_folder_stops(self):
        self.drop_zip("Notes", "1.1.0")
        (self.incoming / "Notes" / "Notes-Setup.exe").write_bytes(b"MZ")
        with self.assertRaises(Stop):
            self.scan(self.published("1.0.0"))


class EditIconTest(unittest.TestCase):
    cfg = {"catalogBaseUrl": "https://o.github.io/r/"}

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.icons = self.dir / "icons"
        self.png = self.dir / "icon.png"
        self.png.write_bytes(b"\x89PNG fake")
        self.catalog = {"apps": [{"id": "com.x.notes", "name": "Notes", "packages": {}}]}

    def run_edit(self, **kw):
        a = argparse.Namespace(id="com.x.notes", name=None, description=None,
                               icon=str(self.png), dry_run=False, yes=False, no_push=False)
        vars(a).update(kw)
        with mock.patch.multiple(publish, ICONS_DIR=self.icons,
                                 load_config=mock.Mock(return_value=self.cfg),
                                 load_private_key=mock.DEFAULT, check_key_matches_config=mock.DEFAULT,
                                 check_git_ready=mock.DEFAULT,
                                 load_catalog=mock.Mock(return_value=self.catalog),
                                 write_signed_catalog=mock.DEFAULT,
                                 commit_and_push=mock.DEFAULT) as m:
            publish.cmd_edit(a)
        return m

    def test_dry_run_writes_nothing(self):
        m = self.run_edit(dry_run=True)
        self.assertFalse(self.icons.exists())
        m["write_signed_catalog"].assert_not_called()
        m["commit_and_push"].assert_not_called()

    def test_yes_copies_icon_with_matching_url(self):
        m = self.run_edit(yes=True)
        dst = self.icons / "com.x.notes.png"
        self.assertEqual(dst.read_bytes(), self.png.read_bytes())
        digest = publish.sha256_file(dst)[:12]
        self.assertEqual(self.catalog["apps"][0]["icon"],
                         f"https://o.github.io/r/icons/com.x.notes.png?v={digest}")
        m["commit_and_push"].assert_called_once()


class SigningTest(unittest.TestCase):
    def test_roundtrip_and_tamper(self):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        key = Ed25519PrivateKey.generate()
        pub = publish.public_key_b64(key)
        data = publish.catalog_bytes({"schemaVersion": 1, "generatedAt": "2026-01-01T00:00:00Z", "apps": []})
        sig = base64.b64encode(key.sign(data)).decode()
        self.assertTrue(publish.verify_signature(data, sig, pub))
        self.assertFalse(publish.verify_signature(data.replace(b"2026", b"2025"), sig, pub))

    def test_generated_at_always_increases(self):
        future = "2999-01-01T00:00:00Z"
        self.assertEqual(publish.now_iso(future), "2999-01-01T00:00:01Z")


class ApkInfoTest(unittest.TestCase):
    """Runs against real APKs when APKINFO_TEST_APK points at one."""

    def test_real_apk(self):
        import os

        path = os.environ.get("APKINFO_TEST_APK")
        if not path:
            self.skipTest("APKINFO_TEST_APK not set")
        from apkinfo import read_apk

        info = read_apk(path)
        self.assertTrue(info.package_name)
        self.assertGreater(info.version_code, 0)
        self.assertEqual(len(info.signing_cert_sha256), 64)


if __name__ == "__main__":
    unittest.main()
