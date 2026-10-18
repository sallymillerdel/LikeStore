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

  group('store location', () {
    test('finds the apps folder Setup chose', () {
      final exe = p.join('D:', 'Apps', 'com.likestore.market', '1.0.2', 'LikeStore.exe');
      expect(WindowsInstaller.storeBaseFor(exe), p.join('D:', 'Apps'));
    });

    test('a build run from elsewhere has none', () {
      final exe = p.join('D:', 'src', 'market', 'build', 'Release', 'LikeStore.exe');
      expect(WindowsInstaller.storeBaseFor(exe), isNull);
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

  group('install layout', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('likestore_layout'));
    tearDown(() => dir.deleteSync(recursive: true));

    String folder(String name, Map<String, String> files) {
      final d = p.join(dir.path, name);
      files.forEach((f, content) => (File(p.join(d, f))..createSync(recursive: true)).writeAsStringSync(content));
      return d;
    }

    test('apps keep one fixed folder, the store one per version', () {
      final appDir = p.join('D:', 'Apps', 'com.classly.app');
      expect(WindowsInstaller.versionDirFor(appDir, '2.4.1', isSelf: false), p.join(appDir, 'current'));
      expect(WindowsInstaller.versionDirFor(appDir, '2.4.2', isSelf: false), p.join(appDir, 'current'));
      expect(WindowsInstaller.versionDirFor(appDir, '1.0.8', isSelf: true), p.join(appDir, '1.0.8'));
    });

    test('first install moves the files into place', () async {
      final staged = folder('.tmp-1', {'Notes.exe': 'new'});
      final target = p.join(dir.path, 'current');
      expect(await WindowsInstaller.moveIntoPlace(staged, target), isNull);
      expect(File(p.join(target, 'Notes.exe')).readAsStringSync(), 'new');
      expect(Directory(staged).existsSync(), isFalse);
    });

    test('an update replaces current and hands back the old files', () async {
      final target = folder('current', {'Notes.exe': 'old'});
      final staged = folder('.tmp-1', {'Notes.exe': 'new'});
      final aside = await WindowsInstaller.moveIntoPlace(staged, target);
      expect(File(p.join(target, 'Notes.exe')).readAsStringSync(), 'new');
      expect(p.basename(aside!), startsWith('.old-'));
      expect(File(p.join(aside, 'Notes.exe')).readAsStringSync(), 'old');
    });

    test('a failed swap puts the old version back', () async {
      final target = folder('current', {'Notes.exe': 'old'});
      await expectLater(WindowsInstaller.moveIntoPlace(p.join(dir.path, 'missing'), target),
          throwsA(isA<FileSystemException>()));
      expect(File(p.join(target, 'Notes.exe')).readAsStringSync(), 'old');
      expect(dir.listSync().map((e) => p.basename(e.path)), ['current']);
    });

    test('a crash between the renames is recovered on the next start', () async {
      folder('.old-100', {'Notes.exe': 'older'});
      folder('.old-200', {'Notes.exe': 'old'});
      folder('.old-300', {'other.txt': 'no entry'});
      final current = p.join(dir.path, 'current');
      expect(await WindowsInstaller.recoverAside(dir.path, current, 'Notes.exe'), isTrue);
      expect(File(p.join(current, 'Notes.exe')).readAsStringSync(), 'old');
      // Nothing to do once current exists.
      expect(await WindowsInstaller.recoverAside(dir.path, current, 'Notes.exe'), isFalse);
    });
  });

  group('shortcut repair', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('likestore_lnk'));
    tearDown(() => dir.deleteSync(recursive: true));

    String ps(String s) => "'${s.replaceAll("'", "''")}'";

    Future<void> makeLink(String link, String target) async {
      final r = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        '\$s = (New-Object -ComObject WScript.Shell).CreateShortcut(${ps(link)}); '
            '\$s.TargetPath = ${ps(target)}; \$s.IconLocation = ${ps('$target,0')}; \$s.Save()',
      ]);
      expect(r.exitCode, 0, reason: r.stderr as String);
    }

    Future<String> targetOf(String link) async {
      final r = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        '(New-Object -ComObject WScript.Shell).CreateShortcut(${ps(link)}).TargetPath',
      ]);
      return (r.stdout as String).trim();
    }

    test('repoints pins at older versions and leaves the rest alone', () async {
      final appDir = p.join(dir.path, 'Apps', 'com.classly.app');
      String exe(String version, [String name = 'classly.exe']) {
        final path = p.join(appDir, version, name);
        File(path).createSync(recursive: true);
        return path;
      }

      final current = exe('current');
      final pins = p.join(dir.path, 'User Pinned', 'TaskBar');
      final desktop = p.join(dir.path, 'Desktop');
      Directory(pins).createSync(recursive: true);
      Directory(p.join(desktop, 'Sub')).createSync(recursive: true);
      final pinned = p.join(pins, 'Classly.lnk');
      final onDesktop = p.join(desktop, 'Classly.lnk');
      final helper = p.join(pins, 'Helper.lnk');
      final nested = p.join(desktop, 'Sub', 'Classly.lnk');
      final upToDate = p.join(pins, 'Current.lnk');
      await makeLink(pinned, exe('2.4.1'));
      await makeLink(onDesktop, exe('2.4.0'));
      await makeLink(helper, exe('2.4.1', 'helper.exe'));
      await makeLink(nested, exe('2.4.1'));
      await makeLink(upToDate, current);

      final changed = await WindowsInstaller.repairShortcutsIn(
          [(p.join(dir.path, 'User Pinned'), true), (desktop, false)], [(appDir, current)]);

      expect(changed.map((c) => p.normalize(c).toLowerCase()).toSet(),
          {pinned, onDesktop}.map((c) => p.normalize(c).toLowerCase()).toSet());
      expect(await targetOf(pinned), current);
      expect(await targetOf(onDesktop), current);
      expect(await targetOf(helper), p.join(appDir, '2.4.1', 'helper.exe')); // other exe
      expect(await targetOf(nested), p.join(appDir, '2.4.1', 'classly.exe')); // Desktop is not recursive
    }, testOn: 'windows', timeout: const Timeout(Duration(minutes: 1)));

    test('nothing to repair runs nothing', () async {
      expect(await WindowsInstaller.repairShortcutsIn([(dir.path, true)], const []), isEmpty);
    });
  });
}
