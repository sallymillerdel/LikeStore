import 'dart:async';
import 'dart:convert';
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
///   apps\<app-id>\current\         the installed version of an app
///   apps\com.likestore.market\<version>\   the store, one folder per version
///
/// The apps folder can be moved: Setup may put the store elsewhere (apps then
/// go next to it), and Settings can choose another folder for apps.
///
/// An update unpacks into a temporary folder, renames `current` aside, renames
/// the new files to `current`, switches installed.json and only then deletes
/// the old files; if anything fails before the switch, the old version is put
/// back. The exe path never changes, so Start and taskbar pins keep working.
/// The store cannot rename the folder it runs from, so it keeps version
/// folders and repoints its shortcuts and pins instead. User data never lives
/// in these folders.
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

  /// %LocalAppData%\LikeStore\apps, where everything goes unless Setup or
  /// Settings chose another folder.
  String get _defaultAppsDir => p.join(storage.root.path, 'apps');

  /// The folder Setup put the store in: the running exe sits in
  /// `<folder>\com.likestore.market\<version>\`. Null for a build run elsewhere.
  String? get _storeBaseDir => storeBaseFor(Platform.resolvedExecutable);

  @visibleForTesting
  static String? storeBaseFor(String exe) {
    final idDir = p.dirname(p.dirname(exe));
    return p.basename(idDir).toLowerCase() == _safeName(kMarketAppId).toLowerCase() ? p.dirname(idDir) : null;
  }

  /// Where apps are installed: chosen in Settings, else next to the store.
  String get appsDir => settings.appsDir ?? _storeBaseDir ?? _defaultAppsDir;

  Directory get _appsDir => Directory(appsDir);

  /// Changes where new installs and updates go. Installed apps stay where
  /// they are until their next update. Throws if [dir] is not writable.
  Future<void> setAppsDir(String dir) async {
    dir = p.normalize(p.absolute(dir));
    bool inside(String parent) => p.equals(parent, dir) || p.isWithin(parent, dir);
    if (inside(storage.root.path) && !inside(_defaultAppsDir)) {
      throw InstallException('Choose a folder outside $kStoreName\'s own data folder.');
    }
    try {
      await Directory(dir).create(recursive: true);
      final probe = File(p.join(dir, '.likestore-write-test'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } on FileSystemException catch (e) {
      throw InstallException('$kStoreName cannot write to $dir: ${e.osError?.message ?? e.message}');
    }
    final fallback = _storeBaseDir ?? _defaultAppsDir;
    await settings.setString('appsDir', p.equals(dir, fallback) ? null : dir);
  }

  /// Opens the apps folder in Explorer.
  Future<void> openAppsDir() async {
    await _appsDir.create(recursive: true);
    await Process.start('explorer.exe', [appsDir], mode: ProcessStartMode.detached);
  }

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
    if (kReleaseMode) {
      unawaited(_ensureOwnShortcut().then((_) => _migrateShortcutSettings()).then((_) => _repairAllShortcuts()));
      if (settings.startWithSystem) unawaited(_writeRunEntry(true));
    }
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

    // The store's own updates stay next to it (the folder Setup chose).
    final base = isSelf ? (_storeBaseDir ?? appsDir) : appsDir;
    final appDir = Directory(p.join(base, _safeName(app.id)));
    await appDir.create(recursive: true);
    final target = Directory(versionDirFor(appDir.path, pkg.versionName, isSelf: isSelf));
    if (oldDir != null &&
        p.equals(oldDir, target.path) &&
        old?['version'] == pkg.versionName &&
        await File(p.join(oldDir, entry)).exists()) {
      throw InstallException('${app.name} ${pkg.versionName} is already installed.');
    }

    final tmp = Directory(p.join(appDir.path, '.tmp-${DateTime.now().millisecondsSinceEpoch}'));
    String? aside;
    try {
      final zipPath = file.path, tmpPath = tmp.path;
      final root = await Isolate.run(() => extractPortableZip(zipPath, tmpPath, entry));
      try {
        aside = await moveIntoPlace(root, target.path);
      } on FileSystemException catch (e) {
        throw InstallException('Could not replace ${app.name}: ${e.osError?.message ?? e.message} '
            'Close any program or Explorer window that uses its folder and try again.');
      }
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
    try {
      await storage.writeJson(_stateFile, state);
    } catch (_) {
      // installed.json still names the old version: put its files back.
      if (aside != null) await _restore(aside, target.path);
      rethrow;
    }
    await file.delete().catchError((_) => file);
    final exe = p.join(target.path, entry);
    await _writeShortcuts(app.name, exe);
    // Pins and other shortcuts made from an older folder (a version folder of
    // the old layout, the store's previous version, an earlier apps folder).
    await _repairShortcuts([
      (appDir.path, exe),
      if (oldDir != null && !p.equals(p.dirname(oldDir), appDir.path)) (p.dirname(oldDir), exe),
    ]);
    if (aside != null) await _tryDelete(aside);

    if (isSelf) {
      // The running exe cannot replace itself, but the new version lives in its
      // own folder: start it and let it clean up after this process exits.
      await Process.start(p.join(target.path, entry), ['--finish-update', '$pid'],
          workingDirectory: target.path, mode: ProcessStartMode.detached);
      return true;
    }
    if (oldDir != null && !p.equals(oldDir, target.path)) {
      await _tryDelete(oldDir);
      // Moved to a new apps folder: drop the old, now empty, app folder.
      final oldAppDir = Directory(p.dirname(oldDir));
      if (!p.equals(oldAppDir.path, appDir.path) && await oldAppDir.exists() && await oldAppDir.list().isEmpty) {
        await _tryDelete(oldAppDir.path);
      }
    }
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
    final appDir = p.dirname(dir);
    await _tryDelete(p.basename(appDir) == _safeName(app.id) ? appDir : dir);
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

  /// The folder a version is installed into. Apps always use
  /// `<app-id>\current\`, so the exe path (which Windows uses to identify the
  /// app in Start pins, taskbar pins and the icon cache) survives updates. The
  /// store itself cannot move the folder it runs from and keeps one folder
  /// per version.
  @visibleForTesting
  static String versionDirFor(String appDir, String version, {required bool isSelf}) =>
      p.join(appDir, isSelf ? _safeName(version) : _currentDir);

  static const _currentDir = 'current';

  /// Renames [staged] to [target]. An existing [target] is first renamed
  /// aside and put back if the second rename fails; returns the aside folder
  /// (for the caller to delete), or null if [target] did not exist.
  @visibleForTesting
  static Future<String?> moveIntoPlace(String staged, String target) async {
    final existing = Directory(target);
    String? aside;
    if (await existing.exists()) {
      aside = p.join(p.dirname(target), '.old-${DateTime.now().microsecondsSinceEpoch}');
      await existing.rename(aside);
    }
    try {
      await Directory(staged).rename(target);
    } catch (_) {
      if (aside != null) await Directory(aside).rename(target);
      rethrow;
    }
    return aside;
  }

  /// After a crash between the two renames of [moveIntoPlace], `current` is
  /// missing and the installed version sits in a `.old-*` folder: puts the
  /// newest such folder that still has [entry] back. Returns true if it did.
  @visibleForTesting
  static Future<bool> recoverAside(String appDir, String dir, String entry) async {
    if (!p.equals(p.dirname(dir), appDir) || await Directory(dir).exists()) return false;
    final candidates = <Directory>[
      await for (final d in Directory(appDir).list())
        if (d is Directory && p.basename(d.path).startsWith('.old-') && await File(p.join(d.path, entry)).exists()) d,
    ]..sort((a, b) => b.path.compareTo(a.path));
    if (candidates.isEmpty) return false;
    try {
      await candidates.first.rename(dir);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Undoes [moveIntoPlace]: the new files go away, the old ones come back.
  Future<void> _restore(String aside, String target) async {
    final failed = '$target.failed-${DateTime.now().microsecondsSinceEpoch}';
    await Directory(target).rename(failed);
    await Directory(aside).rename(target);
    await _tryDelete(failed);
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
    final state = await _readState();
    final records = (state['apps'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>().toList();
    final ownDir = p.dirname(Platform.resolvedExecutable);
    // Every apps folder in use: the current one, the default, Setup's, and
    // the ones apps were installed into before the folder was changed.
    final bases = <String>{
      for (final b in [appsDir, _defaultAppsDir, ?_storeBaseDir, for (final r in records) p.dirname(p.dirname(r['dir'] as String))])
        p.normalize(b).toLowerCase(),
    };
    for (final base in bases) {
      if (!await Directory(base).exists()) continue;
      await _cleanupIn(Directory(base), records, ownDir);
    }
  }

  Future<void> _cleanupIn(Directory base, List<Map<String, dynamic>> records, String ownDir) async {
    await for (final appDir in base.list()) {
      if (appDir is! Directory) continue;
      final rec = records.where((r) => p.isWithin(appDir.path, r['dir'] as String)).firstOrNull;
      final isOwn = p.isWithin(appDir.path, ownDir);
      if (rec == null && !isOwn) continue; // not ours to judge
      if (rec != null) await recoverAside(appDir.path, rec['dir'] as String, rec['entry'] as String);
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

  /// The store writes Start Menu shortcuts only. Desktop ones (made by store
  /// versions before 1.0.2) are still removed with the app.
  Future<List<String>> _shortcutPaths(String name, {required bool onlyEnabled}) async {
    final file = '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.lnk';
    return [
      p.join(_startMenuDir, file),
      if (!onlyEnabled) p.join(await _desktop(), file),
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
    final link = File(p.join(_startMenuDir, '$kStoreName.lnk'));
    if (!await link.exists()) await _writeShortcuts(kStoreName, Platform.resolvedExecutable);
  }

  /// Where shortcuts to the store's apps can be, as (folder, recursive):
  /// the Start Menu, the Desktop, and the copies Windows keeps for taskbar
  /// and Start pins (`Quick Launch\User Pinned\...`).
  Future<List<(String, bool)>> _shortcutFolders() async => [
        (_startMenuDir, true),
        (await _desktop(), false),
        (p.join(Platform.environment['APPDATA'] ?? '', 'Microsoft', 'Internet Explorer', 'Quick Launch'), true),
      ];

  /// Points every shortcut whose target is the same exe in an older folder
  /// under one of the given app folders at the current exe.
  Future<void> _repairShortcuts(List<(String appDir, String exe)> fixes) async {
    try {
      await repairShortcutsIn(await _shortcutFolders(), fixes);
    } catch (_) {
      // Cosmetic: never fail an install over a shortcut.
    }
  }

  /// Startup pass: repairs shortcuts left pointing at deleted versions (by
  /// older store versions, and by the store's own self-updates).
  Future<void> _repairAllShortcuts() async {
    final state = await _readState();
    await _repairShortcuts([
      for (final rec in (state['apps'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>())
        if (rec['dir'] is String && rec['entry'] is String)
          (p.dirname(rec['dir'] as String), p.join(rec['dir'] as String, rec['entry'] as String)),
      if (_storeBaseDir != null) (p.dirname(p.dirname(Platform.resolvedExecutable)), Platform.resolvedExecutable),
    ]);
  }

  /// Rewrites the `.lnk` files in [folders] (path, recursive) whose target has
  /// the file name of a fix's exe and lies under its app folder, but is not
  /// that exe. Tells Explorer about each one so the icon refreshes. Returns
  /// the shortcuts that were changed.
  @visibleForTesting
  static Future<List<String>> repairShortcutsIn(
      List<(String, bool)> folders, List<(String appDir, String exe)> fixes) async {
    if (fixes.isEmpty) return const [];
    String prefix(String dir) => dir.endsWith('\\') ? dir : '$dir\\';
    final script = StringBuffer()
      ..writeln(r'$w = New-Object -ComObject WScript.Shell; $changed = @(); $fixes = @(); $folders = @()')
      // `+= ,@(...)` keeps each pair an array of its own.
      ..writeAll(fixes.map((f) => '\$fixes += ,@(${_psQuote(prefix(f.$1))}, ${_psQuote(f.$2)})\n'))
      ..writeAll(folders.map((f) => '\$folders += ,@(${_psQuote(f.$1)}, \$${f.$2})\n'))
      ..write(r'''
foreach ($d in $folders) {
  if (-not $d[0] -or -not (Test-Path -LiteralPath $d[0])) { continue }
  foreach ($f in Get-ChildItem -LiteralPath $d[0] -Filter *.lnk -File -Recurse:$d[1] -ErrorAction SilentlyContinue) {
    $s = $w.CreateShortcut($f.FullName); $t = $s.TargetPath
    if (-not $t) { continue }
    foreach ($x in $fixes) {
      if ($t.StartsWith($x[0], [StringComparison]::OrdinalIgnoreCase) -and $t -ne $x[1] -and
          [IO.Path]::GetFileName($t) -eq [IO.Path]::GetFileName($x[1])) {
        $s.TargetPath = $x[1]; $s.WorkingDirectory = [IO.Path]::GetDirectoryName($x[1])
        if ($s.IconLocation.StartsWith($x[0], [StringComparison]::OrdinalIgnoreCase)) { $s.IconLocation = $x[1] + ',0' }
        $s.Save(); $changed += $f.FullName; break
      }
    }
  }
}
if ($changed) {
  Add-Type -Namespace LikeStore -Name Shell -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern void SHChangeNotify(int e, int f, string a, IntPtr b);'
  foreach ($c in $changed) { [LikeStore.Shell]::SHChangeNotify(0x2000, 0x5, $c, [IntPtr]::Zero) }
}
$changed
''');
    // Encoded, so quotes and newlines need no command-line escaping.
    final encoded = base64.encode([
      for (final u in script.toString().codeUnits) ...[u & 0xff, u >> 8], // UTF-16LE
    ]);
    final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded]);
    if (r.exitCode != 0) throw ProcessException('powershell', const [], (r.stderr as String).trim(), r.exitCode);
    return const LineSplitter().convert(r.stdout as String).where((l) => l.trim().isNotEmpty).toList();
  }

  /// Once, after the shortcut settings were dropped: re-creates every
  /// shortcut, which removes the Desktop ones the old settings could add.
  Future<void> _migrateShortcutSettings() async {
    if (!settings.has('startMenuShortcut') && !settings.has('desktopShortcut')) return;
    final state = await _readState();
    for (final rec in (state['apps'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>()) {
      final name = rec['name'] as String? ?? '';
      if (name.isEmpty) continue;
      await _removeShortcuts(name);
      await _writeShortcuts(name, p.join(rec['dir'] as String, rec['entry'] as String));
    }
    await settings.remove(['startMenuShortcut', 'desktopShortcut']);
  }

  // Start with Windows ---------------------------------------------------------

  static const _runKey = r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Starts the store when the user signs in to Windows, or stops doing so.
  Future<void> setStartWithSystem(bool on) async {
    await settings.set('startWithSystem', on);
    await _writeRunEntry(on);
  }

  /// Points the Run entry at the running exe (it moves to a new version folder
  /// with every self-update), or removes it.
  Future<void> _writeRunEntry(bool on) async {
    final key = _psQuote(_runKey), name = _psQuote(kStoreName);
    final command = on
        ? 'Set-ItemProperty -Path $key -Name $name '
              '-Value ([char]34 + ${_psQuote(Platform.resolvedExecutable)} + [char]34)'
        : 'Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue';
    await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', command]);
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

  bool get startWithSystem => _values['startWithSystem'] as bool? ?? false;
  bool get checkOnStartup => _values['checkOnStartup'] as bool? ?? true;

  /// Apps folder chosen in Settings, null for the default.
  String? get appsDir => _values['appsDir'] as String?;

  bool has(String key) => _values.containsKey(key);

  /// Sets a text value; null removes it.
  Future<void> setString(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    await _storage.writeJson(_file, _values);
  }

  Future<void> set(String key, bool value) async {
    _values[key] = value;
    await _storage.writeJson(_file, _values);
  }

  Future<void> remove(List<String> keys) async {
    keys.forEach(_values.remove);
    await _storage.writeJson(_file, _values);
  }
}
