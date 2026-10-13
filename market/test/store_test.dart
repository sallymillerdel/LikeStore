import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market/src/catalog.dart';
import 'package:market/src/catalog_service.dart';
import 'package:market/src/downloader.dart';
import 'package:market/src/installer/windows_installer.dart';
import 'package:market/src/semver.dart';
import 'package:path/path.dart' as p;

// Signed by scripts/publish.py with a throwaway key (not the store's key), so
// this checks that Dart verifies exactly what the publisher signs.
const testCatalog = r'''{
  "schemaVersion": 1,
  "generatedAt": "2026-10-13T12:00:00Z",
  "apps": [
    {
      "id": "my.app.notes",
      "name": "Notes",
      "description": "Test",
      "futureField": true,
      "packages": {
        "android": {
          "package": "apk",
          "packageName": "my.app.notes",
          "versionCode": 12,
          "versionName": "1.4.0",
          "url": "https://example.com/n.apk",
          "sha256": "ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB",
          "sizeBytes": 10,
          "changelog": "Bug fixes"
        },
        "windows": {
          "package": "zip",
          "entry": "Notes.exe",
          "versionName": "1.4.0",
          "url": "http://insecure.example.com/n.zip",
          "sha256": "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
          "sizeBytes": 20
        }
      }
    }
  ]
}
''';
const testSig =
    'LBzQqhkb+WzirZwXTGtyCHpistFEA46ATPq5hBuht+gkFHOUf9P9knLDuQ8vgSkYrlXy4u1thsyuAuH2cAReAw==';
const testPub = 'JpcwvM8GeMCFS3qDbjllnCY4wrJBFiPOhjKzvcywD0c=';

void main() {
  group('semver', () {
    test('orders versions like publish.py', () {
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.4.1', '1.4'), greaterThan(0));
      expect(compareVersions('1.4', '1.4.0'), 0);
      expect(compareVersions('2.0.0', '2.0.0-beta.2'), greaterThan(0));
      expect(compareVersions('2.0.0-beta.10', '2.0.0-beta.2'), greaterThan(0));
      expect(compareVersions('1.4.0+5', '1.4.0'), 0);
      expect(compareVersions('garbage', '0.0.1'), lessThan(0));
    });
  });

  group('catalog signature', () {
    final bytes = utf8.encode(testCatalog);

    test('accepts what publish.py signed', () async {
      expect(await verifyCatalogSignature(bytes, testSig, testPub), isTrue);
    });

    test('rejects a modified catalog', () async {
      final tampered = utf8.encode(testCatalog.replaceFirst('1.4.0', '9.9.9'));
      expect(await verifyCatalogSignature(tampered, testSig, testPub), isFalse);
    });

    test('rejects garbage signatures', () async {
      expect(await verifyCatalogSignature(bytes, 'not base64!', testPub), isFalse);
    });
  });

  group('catalog parsing', () {
    test('reads fields, ignores unknown ones, drops non-https packages', () {
      final c = Catalog.fromJson(jsonDecode(testCatalog) as Map<String, dynamic>);
      expect(c.generatedAt, DateTime.utc(2026, 10, 13, 12));
      final app = c.apps.single;
      expect(app.name, 'Notes');
      final android = app.packages['android']!;
      expect(android.versionCode, 12);
      expect(android.sha256, 'ab' * 32); // normalised to lower case
      expect(app.packages.containsKey('windows'), isFalse); // http:// URL refused
    });
  });

  group('download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('likestore_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    final payload = utf8.encode('hello store' * 1000);
    final digest = sha256.convert(payload).toString();

    test('verifies the hash', () async {
      final client = MockClient.streaming((req, _) async =>
          http.StreamedResponse(Stream.value(payload), 200, contentLength: payload.length));
      final f = await downloadVerified(
        url: 'https://example.com/a.zip',
        dest: File(p.join(dir.path, 'a.zip')),
        sha256Hex: digest,
        expectedSize: payload.length,
        onProgress: (_, _) {},
        client: client,
      );
      expect(await f.readAsBytes(), payload);
    });

    test('resumes a partial download with a Range request', () async {
      File(p.join(dir.path, 'a.zip.part')).writeAsBytesSync(payload.sublist(0, 100));
      String? range;
      final client = MockClient.streaming((req, _) async {
        range = req.headers['Range'];
        return http.StreamedResponse(Stream.value(payload.sublist(100)), 206);
      });
      final f = await downloadVerified(
        url: 'https://example.com/a.zip',
        dest: File(p.join(dir.path, 'a.zip')),
        sha256Hex: digest,
        expectedSize: payload.length,
        onProgress: (_, _) {},
        client: client,
      );
      expect(range, 'bytes=100-');
      expect(await f.readAsBytes(), payload);
    });

    test('deletes the file on hash mismatch', () async {
      final client = MockClient.streaming(
          (req, _) async => http.StreamedResponse(Stream.value(payload), 200));
      await expectLater(
        downloadVerified(
          url: 'https://example.com/a.zip',
          dest: File(p.join(dir.path, 'a.zip')),
          sha256Hex: '00' * 32,
          expectedSize: payload.length,
          onProgress: (_, _) {},
          client: client,
        ),
        throwsA(isA<DownloadException>()),
      );
      expect(dir.listSync(), isEmpty);
    });
  });

  group('portable zip', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('likestore_zip'));
    tearDown(() => dir.deleteSync(recursive: true));

    String makeZip(Map<String, String> files) {
      final archive = Archive();
      files.forEach((name, content) => archive.add(ArchiveFile.string(name, content)));
      final path = p.join(dir.path, 'app.zip');
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      return path;
    }

    test('entry at the root', () {
      final zip = makeZip({'Notes.exe': 'x', 'data/a.txt': 'y'});
      final out = p.join(dir.path, 'out');
      expect(WindowsInstaller.extractPortableZip(zip, out, 'Notes.exe'), out);
      expect(File(p.join(out, 'data', 'a.txt')).existsSync(), isTrue);
    });

    test('single top-level folder is normalised', () {
      final zip = makeZip({'Notes/Notes.exe': 'x', 'Notes/lib.dll': 'y'});
      final out = p.join(dir.path, 'out');
      expect(WindowsInstaller.extractPortableZip(zip, out, 'Notes.exe'), p.join(out, 'Notes'));
    });

    test('zip-slip entries reject the whole archive', () {
      final zip = makeZip({'Notes.exe': 'x', '../evil.txt': 'y'});
      final out = p.join(dir.path, 'out');
      expect(() => WindowsInstaller.extractPortableZip(zip, out, 'Notes.exe'),
          throwsA(isA<ArchiveException>()));
      expect(File(p.join(dir.path, 'evil.txt')).existsSync(), isFalse);
    });

    test('missing entry is an error', () {
      final zip = makeZip({'Other.exe': 'x'});
      expect(() => WindowsInstaller.extractPortableZip(zip, p.join(dir.path, 'out'), 'Notes.exe'),
          throwsA(isA<ArchiveException>()));
    });
  });
}
