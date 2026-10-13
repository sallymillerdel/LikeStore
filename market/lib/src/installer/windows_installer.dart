import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../catalog.dart';
import '../config.g.dart';
import '../storage.dart';
import 'installer.dart';

/// Portable-ZIP installs under %LocalAppData%\LikeStore (MARKET_SPEC.md section 6):
///
///   installed.json                 id -> version, entry, folder
///   downloads\                     temporary downloads
///   apps\<app-id>\<version>\       one folder per unpacked version
///
/// An update unpacks into a new version folder, switches installed.json to it
/// and only then removes the old folder; if anything fails before the switch,
/// the old version is untouched. User data never lives in these folders.
class WindowsInstaller implements PlatformInstaller {
  WindowsInstaller(this.storage, this.args);

  final Storage storage;
  final List<String> args;
  late final WindowsSettings settings;
  late final String _ownVersion;
  String? _desktopDir;

  static const _stateFile = 'installed.json';

  @override
  String get platform => 'windows';

  Directory get _appsDir => Directory(p.join(storage.root.path, 'apps'));

  @override
  Future<void> init() async {
    settings = await WindowsSettings.load(storage);
    _ownVersion = (await PackageInfo.fromPlatform()).version;

    // Started by a previous version of the store after a self-update:
    // wait for it to exit before cleaning up its folder.
    final i = args.indexOf('--finish-update');
    if (i >= 0 && i + 1 < args.length) {
      final oldPid = int.tryParse(args[i + 1]);
      if (oldPid != null) await _waitForExit(oldPid);
    }
    unawaited(_cleanupOldVersions());
    if (kReleaseMode) unawaited(_ensureOwnShortcut());
  }

  // --- installed state -----------------------------------------------------

  Future<Map<String, dynamic>> _readState() async {
    final s = await storage.readJson(_stateFile);
    s['apps'] = (s['apps'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return s;
  }

  Map<String, dynamic>? _record(Map<String, dynamic> state, String id) =>
      (state['apps'] as Map<String, dynamic>)[id] as Map<String, dynamic>?;

  @override
  Future<InstalledInfo?> installed(AppEntry app, PlatformPackage pkg) async {
    if (app.id == kMarketAppId) return InstalledInfo(versionName: _ownVersion);
    final rec = _record(await _readState(), app.id);
    if (rec == null) return null;
    final exe = File(p.join(rec['dir'] as String, rec['entry'] as String));
    if (!await exe.exists()) return null; // folder deleted by hand: not installed
    return InstalledInfo(versionName: rec['version'] as String);
  }

  @override
  bool canOpen(AppEntry app) => app.id != kMarketAppId;

  // --- install / update ---------------------------------------------------

  @override
  Future<bool> install(AppEntry app, PlatformPackage pkg, File file) async {
    final entry = pkg.entry;
    if (entry == null || entry.isEmpty || p.basename(entry) != entry) {
      throw InstallException('The catalog entry for ${app.name} has no valid "entry".');
    }
    final isSelf = app.id == kMarketAppId;
    final state = await _readState();
    final old = _record(state, app.id);
    final oldDir = old?['dir'] as String?;

    // Never touch a running version (and never kill it silently).
    if (!isSelf && oldDir != null && await _isRunningFrom(oldDir)) {
      throw AppRunningException(app.name);
    }

    final appDir = Directory(p.join(_appsDir.path, _safeName(app.id)));
    await appDir.create(recursive: true);
    final target = Directory(p.join(appDir.path, _safeName(pkg.versionName)));
    if (oldDir != null && p.equals(oldDir, target.path)) {
      throw InstallException('${app.name} ${pkg.versionName} is already installed.');
    }
    if (await target.exists()) await target.delete(recursive: true); // left from a failed try

    final tmp = Directory(p.join(appDir.path, '.tmp-${DateTime.now().millisecondsSinceEpoch}'));
    try {
      final zipPath = file.path, tmpPath = tmp.path;
      final root = await Isolate.run(() => extractPortableZip(zipPath, tmpPath, entry));
      await Directory(root).rename(target.path);
    } on ArchiveException catch (e) {
      throw InstallException('The download could not be unpacked: ${e.message}');
    } on FileSystemException catch (e) {
      throw InstallException('Could not unpack ${app.name}: ${e.message}');
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }

    // Switch: from here on the new version is the installed one.
    (state['apps'] as Map<String, dynamic>)[app.id] = {
      'name': app.name,
      'version': pkg.versionName,
      'entry': entry,
      'dir': target.path,
      'installedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await storage.writeJson(_stateFile, state);
    await file.delete().catchError((_) => file);
    await _writeShortcuts(app.name, p.join(target.path, entry));

    if (isSelf) {
      // The running exe cannot replace itself, but the new version lives in its
      // own folder: start it and let it clean up after this process exits.
      await Process.start(p.join(target.path, entry), ['--finish-update', '$pid'],
          workingDirectory: target.path, mode: ProcessStartMode.detached);
      return true;
    }
    if (oldDir != null) await _tryDelete(oldDir);
    return false;
  }

  @override
  Future<void> open(AppEntry app, PlatformPackage pkg) async {
    final rec = _record(await _readState(), app.id);
    if (rec == null) throw InstallException('${app.name} is not installed.');
    final dir = rec['dir'] as String;
    await Process.start(p.join(dir, rec['entry'] as String), const [],
        workingDirectory: dir, mode: ProcessStartMode.detached);
  }

  @override
  Future<void> uninstall(AppEntry app, PlatformPackage pkg) async {
    if (app.id == kMarketAppId) throw InstallException('The store cannot uninstall itself.');
    final state = await _readState();
    final rec = _record(state, app.id);
    if (rec == null) return;
    final dir = rec['dir'] as String;
    if (await _isRunningFrom(dir)) throw AppRunningException(app.name);
    // Only the program folder goes; the app's data in %AppData% is kept.
    await _tryDelete(p.join(_appsDir.path, _safeName(app.id)));
    (state['apps'] as Map<String, dynamic>).remove(app.id);
    await storage.writeJson(_stateFile, state);
    await _removeShortcuts(rec['name'] as String? ?? app.name);
  }

  // --- helpers ------------------------------------------------------------

  /// Unpacks into [dest], rejecting the whole archive if any entry would land
  /// outside it (zip-slip). Returns the folder that holds [entry]: [dest]
  /// itself, or its single top-level folder.
  @visibleForTesting
  static String extractPortableZip(String zipPath, String dest, String entry) {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final f in archive) {
        final out = p.normalize(p.join(dest, f.name));
        if (!p.isWithin(dest, out) || f.isSymbolicLink) {
          throw ArchiveException('Unsafe path in archive: ${f.name}');
        }
      }
      Directory(dest).createSync(recursive: true);
      extractArchiveToDiskSync(archive, dest);
    } finally {
      input.closeSync();
    }
    if (File(p.join(dest, entry)).existsSync()) return dest;
    final children = Directory(dest).listSync();
    if (children.length == 1 && children.single is Directory) {
      final inner = children.single.path;
      if (File(p.join(inner, entry)).existsSync()) return inner;
    }
    throw ArchiveException('$entry was not found in the archive.');
  }

  Future<bool> _isRunningFrom(String dir) async {
    final prefix = dir.endsWith('\\') ? dir : '$dir\\';
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Get-Process | Where-Object { \$_.Path -and \$_.Path.StartsWith(${_psQuote(prefix)}, "
          "[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 -ExpandProperty Id",
    ]);
    return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
  }

  Future<void> _waitForExit(int oldPid) async {
    for (var i = 0; i < 60; i++) {
      final r = await Process.run('tasklist', ['/FI', 'PID eq $oldPid', '/NH']);
      if (!(r.stdout as String).contains(' $oldPid ')) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Removes version folders that are no longer current (old versions whose
  /// files were locked earlier, leftovers of failed unpacks).
  Future<void> _cleanupOldVersions() async {
    if (!await _appsDir.exists()) return;
    final state = await _readState();
    final ownDir = p.dirname(Platform.resolvedExecutable);
    await for (final appDir in _appsDir.list()) {
      if (appDir is! Directory) continue;
      final rec = (state['apps'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>()
          .where((r) => p.isWithin(appDir.path, r['dir'] as String))
          .firstOrNull;
      final isOwn = p.isWithin(appDir.path, ownDir);
      if (rec == null && !isOwn) continue; // not ours to judge
      await for (final v in appDir.list()) {
        if (v is! Directory) continue;
        final keep = (rec != null &&
                (p.equals(v.path, rec['dir'] as String) || p.isWithin(v.path, rec['dir'] as String))) ||
            p.equals(v.path, ownDir) ||
            p.isWithin(v.path, ownDir);
        if (!keep) await _tryDelete(v.path);
      }
    }
  }

  Future<void> _tryDelete(String path) async {
    try {
      await Directory(path).delete(recursive: true);
    } catch (_) {
      // Locked files: retried by _cleanupOldVersions on the next start.
    }
  }

  // Shortcuts ----------------------------------------------------------------

  Future<String> _desktop() async {
    if (_desktopDir != null) return _desktopDir!;
    final r = await Process.run('powershell',
        ['-NoProfile', '-NonInteractive', '-Command', "[Environment]::GetFolderPath('Desktop')"]);
    return _desktopDir = (r.stdout as String).trim();
  }

  String get _startMenuDir => p.join(Platform.environment['APPDATA'] ?? '',
      'Microsoft', 'Windows', 'Start Menu', 'Programs');

  Future<List<String>> _shortcutPaths(String name, {required bool onlyEnabled}) async {
    final file = '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.lnk';
    return [
      if (!onlyEnabled || settings.startMenuShortcut) p.join(_startMenuDir, file),
      if (!onlyEnabled || settings.desktopShortcut) p.join(await _desktop(), file),
    ];
  }

  Future<void> _writeShortcuts(String name, String exe) async {
    final links = await _shortcutPaths(name, onlyEnabled: true);
    if (links.isEmpty) return;
    final script = StringBuffer(r'$w = New-Object -ComObject WScript.Shell; ');
    for (final l in links) {
      script.write('\$s = \$w.CreateShortcut(${_psQuote(l)}); \$s.TargetPath = ${_psQuote(exe)}; '
          '\$s.WorkingDirectory = ${_psQuote(p.dirname(exe))}; \$s.Save(); ');
    }
    await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script.toString()]);
  }

  Future<void> _removeShortcuts(String name) async {
    for (final l in await _shortcutPaths(name, onlyEnabled: false)) {
      final f = File(l);
      if (await f.exists()) await f.delete().catchError((_) => f);
    }
  }

  /// Gives the store itself a Start Menu entry pointing at the running exe.
  Future<void> _ensureOwnShortcut() async {
    if (!settings.startMenuShortcut) return;
    final link = File(p.join(_startMenuDir, '$kStoreName.lnk'));
    if (!await link.exists()) await _writeShortcuts(kStoreName, Platform.resolvedExecutable);
  }

  /// Re-creates shortcuts for everything installed after a settings change.
  Future<void> refreshShortcuts() async {
    final state = await _readState();
    for (final rec in (state['apps'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>()) {
      final name = rec['name'] as String? ?? '';
      if (name.isEmpty) continue;
      await _removeShortcuts(name);
      await _writeShortcuts(name, p.join(rec['dir'] as String, rec['entry'] as String));
    }
  }

  static String _psQuote(String s) => "'${s.replaceAll("'", "''")}'";

  static String _safeName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
}

class WindowsSettings {
  WindowsSettings._(this._storage, this._values);

  final Storage _storage;
  final Map<String, dynamic> _values;
  static const _file = 'settings.json';

  static Future<WindowsSettings> load(Storage s) async =>
      WindowsSettings._(s, await s.readJson(_file));

  bool get startMenuShortcut => _values['startMenuShortcut'] as bool? ?? true;
  bool get desktopShortcut => _values['desktopShortcut'] as bool? ?? false;
  bool get checkOnStartup => _values['checkOnStartup'] as bool? ?? true;

  Future<void> set(String key, bool value) async {
    _values[key] = value;
    await _storage.writeJson(_file, _values);
  }
}
