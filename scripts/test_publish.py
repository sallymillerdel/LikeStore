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
