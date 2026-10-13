"""Read what the store needs to know about an APK, without the Android SDK.

    info = read_apk("notes.apk")
    info.package_name, info.version_code, info.version_name, info.min_sdk,
    info.label, info.signing_cert_sha256

The manifest is read from the binary XML (AXML) inside the APK. The signing
certificate comes from the APK Signing Block (v3.1, v3 or v2 scheme), falling
back to the v1 JAR signature in META-INF. The certificate digest is the SHA-256
of the DER certificate, the same value `apksigner verify --print-certs` prints
as "certificate SHA-256 digest" and Android compares on update.

`label` is only filled when the manifest carries a literal string; usually it
is a resource reference (@string/app_name) and stays None.
"""

from __future__ import annotations

import hashlib
import struct
import zipfile
from dataclasses import dataclass

# Android framework attribute resource ids (android.R.attr).
ATTR_LABEL = 0x01010001
ATTR_MIN_SDK = 0x0101020C
ATTR_VERSION_CODE = 0x0101021B
ATTR_VERSION_NAME = 0x0101021C

# AXML chunk types.
RES_STRING_POOL = 0x0001
RES_XML = 0x0003
RES_XML_START_ELEMENT = 0x0102
RES_XML_RESOURCE_MAP = 0x0180

# Typed value data types.
TYPE_REFERENCE = 0x01
TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10
TYPE_INT_HEX = 0x11

# APK Signing Block ids, preferred first.
SIG_V31 = 0x1B93AD61
SIG_V3 = 0xF05368C0
SIG_V2 = 0x7109871A


class ApkError(Exception):
    pass


@dataclass
class ApkInfo:
    package_name: str
    version_code: int
    version_name: str
    min_sdk: int | None
    label: str | None
    signing_cert_sha256: str
    signature_scheme: str


def read_apk(path: str) -> ApkInfo:
    try:
        with zipfile.ZipFile(path) as z:
            manifest = z.read("AndroidManifest.xml")
            names = z.namelist()
            v1_cert = _v1_cert(z, names)
    except (zipfile.BadZipFile, KeyError) as e:
        raise ApkError(f"{path}: not a valid APK ({e})") from e

    attrs = _parse_manifest(manifest)
    package = attrs.get("package")
    code = attrs.get("versionCode")
    if not package or code is None:
        raise ApkError(f"{path}: manifest has no package name or versionCode")

    scheme, cert = _signing_block_cert(path)
    if cert is None:
        scheme, cert = "v1", v1_cert
    if cert is None:
        raise ApkError(f"{path}: APK is not signed")

    return ApkInfo(
        package_name=package,
        version_code=int(code),
        version_name=str(attrs.get("versionName") or code),
        min_sdk=attrs.get("minSdkVersion"),
        label=attrs.get("label"),
        signing_cert_sha256=hashlib.sha256(cert).hexdigest(),
        signature_scheme=scheme,
    )


# --- binary manifest -------------------------------------------------------


def _parse_manifest(data: bytes) -> dict:
    ctype, hsize, _ = struct.unpack_from("<HHI", data, 0)
    if ctype != RES_XML:
        raise ApkError("AndroidManifest.xml is not binary XML")
    strings: list[str] = []
    res_ids: list[int] = []
    out: dict = {}
    pos = hsize
    while pos + 8 <= len(data):
        ctype, hsize, csize = struct.unpack_from("<HHI", data, pos)
        if csize < 8:
            break
        if ctype == RES_STRING_POOL:
            strings = _string_pool(data, pos)
        elif ctype == RES_XML_RESOURCE_MAP:
            n = (csize - hsize) // 4
            res_ids = list(struct.unpack_from(f"<{n}I", data, pos + hsize))
        elif ctype == RES_XML_START_ELEMENT:
            _start_element(data, pos, hsize, strings, res_ids, out)
        pos += csize
    return out


def _string_pool(data: bytes, start: int) -> list[str]:
    _, hsize, _, count, _, flags, strings_start, _ = struct.unpack_from("<HHIIIIII", data, start)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from(f"<{count}I", data, start + hsize)
    base = start + strings_start
    result = []
    for off in offsets:
        p = base + off
        if utf8:
            _, p = _utf8_len(data, p)  # length in UTF-16 units, unused
            n, p = _utf8_len(data, p)
            result.append(data[p : p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, p)[0]
            p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, p)[0]
                p += 2
            result.append(data[p : p + n * 2].decode("utf-16-le", "replace"))
    return result


def _utf8_len(data: bytes, p: int) -> tuple[int, int]:
    n = data[p]
    p += 1
    if n & 0x80:
        n = ((n & 0x7F) << 8) | data[p]
        p += 1
    return n, p


def _start_element(data, pos, hsize, strings, res_ids, out):
    name_idx, attr_start, attr_size, attr_count = struct.unpack_from("<4xIHHH", data, pos + hsize)
    tag = strings[name_idx] if name_idx < len(strings) else ""
    if tag not in ("manifest", "uses-sdk", "application"):
        return
    p = pos + hsize + attr_start
    for _ in range(attr_count):
        _, aname, raw, dtype, value = struct.unpack_from("<IIi3xBI", data, p)
        p += attr_size
        res_id = res_ids[aname] if aname < len(res_ids) else None
        attr = strings[aname] if aname < len(strings) else ""
        if dtype == TYPE_STRING:
            v = strings[value] if value < len(strings) else None
        elif dtype in (TYPE_INT_DEC, TYPE_INT_HEX):
            v = value
        elif dtype == TYPE_REFERENCE:
            v = None  # resource reference; not resolvable without resources.arsc
        else:
            v = strings[raw] if 0 <= raw < len(strings) else None

        if tag == "manifest" and attr == "package" and res_id is None:
            out["package"] = v
        elif tag == "manifest" and res_id == ATTR_VERSION_CODE:
            out["versionCode"] = int(v) if v is not None else None
        elif tag == "manifest" and res_id == ATTR_VERSION_NAME:
            out["versionName"] = v
        elif tag == "uses-sdk" and res_id == ATTR_MIN_SDK and isinstance(v, int):
            out["minSdkVersion"] = v
        elif tag == "application" and res_id == ATTR_LABEL and isinstance(v, str):
            out["label"] = v


# --- signing certificate ---------------------------------------------------


def _signing_block_cert(path: str) -> tuple[str | None, bytes | None]:
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        tail_len = min(size, 65535 + 22)
        f.seek(size - tail_len)
        tail = f.read()
        eocd = tail.rfind(b"PK\x05\x06")
        if eocd < 0:
            raise ApkError(f"{path}: no ZIP end-of-central-directory record")
        cd_offset = struct.unpack_from("<I", tail, eocd + 16)[0]
        if cd_offset < 32:
            return None, None
        f.seek(cd_offset - 24)
        footer = f.read(24)
        block_size, magic = struct.unpack("<Q16s", footer)
        if magic != b"APK Sig Block 42":
            return None, None
        f.seek(cd_offset - block_size - 8)
        block = f.read(block_size + 8)

    pairs = {}
    p, end = 8, len(block) - 24
    while p + 12 <= end:
        length, pid = struct.unpack_from("<QI", block, p)
        pairs[pid] = block[p + 12 : p + 8 + length]
        p += 8 + length

    for pid, name in ((SIG_V31, "v3.1"), (SIG_V3, "v3"), (SIG_V2, "v2")):
        if pid in pairs:
            return name, _first_signer_cert(pairs[pid])
    return None, None


def _lp(buf: bytes, p: int) -> tuple[bytes, int]:
    """Read a uint32 length-prefixed field."""
    n = struct.unpack_from("<I", buf, p)[0]
    return buf[p + 4 : p + 4 + n], p + 4 + n


def _first_signer_cert(value: bytes) -> bytes:
    signers, _ = _lp(value, 0)
    signer, _ = _lp(signers, 0)
    signed_data, _ = _lp(signer, 0)
    _digests, p = _lp(signed_data, 0)
    certs, _ = _lp(signed_data, p)
    cert, _ = _lp(certs, 0)
    return cert


def _v1_cert(z: zipfile.ZipFile, names: list[str]) -> bytes | None:
    for n in names:
        upper = n.upper()
        if upper.startswith("META-INF/") and upper.endswith((".RSA", ".DSA", ".EC")):
            from cryptography.hazmat.primitives.serialization import Encoding, pkcs7

            certs = pkcs7.load_der_pkcs7_certificates(z.read(n))
            if certs:
                return certs[0].public_bytes(Encoding.DER)
    return None


if __name__ == "__main__":
    import sys

    for a in sys.argv[1:]:
        print(a, read_apk(a))
