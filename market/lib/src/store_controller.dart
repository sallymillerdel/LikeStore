import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'catalog.dart';
import 'catalog_service.dart';
import 'config.g.dart';
import 'downloader.dart';
import 'installer/android_installer.dart';
import 'installer/installer.dart';
import 'installer/windows_installer.dart';
import 'semver.dart';
import 'storage.dart';

enum AppAction { install, update, open, upToDate }

enum Phase { idle, downloading, installing }

class AppStatus {
  AppStatus(this.app, this.pkg);

  final AppEntry app;
  final PlatformPackage pkg;
  InstalledInfo? installed;
  Phase phase = Phase.idle;
  int received = 0;
  int total = 0;
  String? error;

  bool get isStore => app.id == kMarketAppId;
  bool get busy => phase != Phase.idle;
  double? get progress => total > 0 ? received / total : null;

  bool get hasUpdate {
    final i = installed;
    if (i == null) return false;
    if (pkg.versionCode != null && i.versionCode != null) return pkg.versionCode! > i.versionCode!;
    return compareVersions(pkg.versionName, i.versionName) > 0;
  }

  AppAction action(bool canOpen) {
    if (installed == null) return AppAction.install;
    if (hasUpdate) return AppAction.update;
    return canOpen ? AppAction.open : AppAction.upToDate;
  }
}

class StoreController extends ChangeNotifier {
  StoreController._(this.storage, this.installer, this.catalogs);

  final Storage storage;
  final PlatformInstaller installer;
  final CatalogService catalogs;

  Catalog? catalog;
  List<AppStatus> apps = [];
  bool loading = false;
  bool offline = false;

  /// Problem with the catalog itself (shown as a banner).
  String? catalogError;

  /// Android: the user has not yet allowed this store to install apps.
  bool needsInstallPermission = false;

  static Future<StoreController> create(List<String> args) async {
    final storage = await Storage.open();
    final installer = PlatformInstaller.create(storage, args);
    await installer.init();
    return StoreController._(storage, installer, CatalogService(storage));
  }

  WindowsSettings? get windowsSettings =>
      installer is WindowsInstaller ? (installer as WindowsInstaller).settings : null;

  AndroidInstaller? get android =>
      installer is AndroidInstaller ? installer as AndroidInstaller : null;

  int get updateCount => apps.where((a) => a.hasUpdate).length;

  bool canOpen(AppStatus s) => installer.canOpen(s.app);

  /// Shows the cached catalog at once, then checks the server (unless the
  /// user turned off checking on startup on Windows).
  Future<void> start() async {
    final cached = await catalogs.cached();
    if (cached != null) await _apply(cached);
    final check = windowsSettings?.checkOnStartup ?? true;
    if (check || cached == null) {
      await refresh();
    } else {
      offline = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final r = await catalogs.load();
      offline = r.offline;
      catalogError = r.error;
      await _apply(r.catalog);
    } catch (e) {
      catalogError = e.toString();
      offline = catalog != null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _apply(Catalog c) async {
    final previous = {for (final a in apps) a.app.id: a};
    catalog = c;
    apps = [
      for (final app in c.apps)
        if (app.packages[installer.platform] case final pkg?)
          // Keep in-flight progress if the catalog is reloaded mid-download.
          (previous[app.id]?.busy ?? false)
              ? previous[app.id]!
              : AppStatus(app, pkg),
    ];
    await refreshInstalled();
  }

  /// Re-reads installed versions (e.g. when the app returns to the foreground
  /// after the Android install prompt or an uninstall).
  Future<void> refreshInstalled() async {
    for (final s in apps) {
      try {
        s.installed = await installer.installed(s.app, s.pkg);
      } catch (_) {
        s.installed = null;
      }
    }
    if (android != null) needsInstallPermission = !await android!.canRequestInstalls();
    _sort();
    notifyListeners();
  }

  void _sort() {
    int rank(AppStatus s) => s.hasUpdate ? 0 : (s.installed != null ? 1 : 2);
    apps.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.app.name.toLowerCase().compareTo(b.app.name.toLowerCase());
    });
  }

  Future<void> run(AppStatus s) async {
    switch (s.action(canOpen(s))) {
      case AppAction.install:
      case AppAction.update:
        await _install(s);
      case AppAction.open:
        await _guard(s, () => installer.open(s.app, s.pkg));
      case AppAction.upToDate:
        break;
    }
  }

  Future<void> updateAll() async {
    // The store last: updating it restarts it.
    final todo = apps.where((a) => a.hasUpdate && !a.busy).toList()
      ..sort((a, b) => (a.isStore ? 1 : 0).compareTo(b.isStore ? 1 : 0));
    for (final s in todo) {
      await _install(s);
      if (needsInstallPermission) break;
    }
  }

  Future<void> uninstall(AppStatus s) async {
    await _guard(s, () => installer.uninstall(s.app, s.pkg));
    await refreshInstalled();
  }

  Future<void> openInstallPermissionSettings() async => android?.openInstallPermissionSettings();

  Future<void> _install(AppStatus s) async {
    if (s.busy) return;
    if (android != null && !await android!.canRequestInstalls()) {
      needsInstallPermission = true;
      s.error = InstallPermissionException().message;
      notifyListeners();
      return;
    }
    s
      ..error = null
      ..phase = Phase.downloading
      ..received = 0
      ..total = s.pkg.sizeBytes;
    notifyListeners();
    try {
      final ext = s.pkg.kind == 'apk' ? 'apk' : 'zip';
      final name = '${s.app.id}-${s.pkg.versionName}.$ext'.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
      final file = await downloadVerified(
        url: s.pkg.url,
        dest: File(p.join(storage.downloads.path, name)),
        sha256Hex: s.pkg.sha256,
        expectedSize: s.pkg.sizeBytes,
        onProgress: (received, total) {
          s
            ..received = received
            ..total = total;
          notifyListeners();
        },
      );
      s.phase = Phase.installing;
      notifyListeners();
      final restarting = await installer.install(s.app, s.pkg, file);
      if (restarting) exit(0); // Windows self-update: the new version is starting.
    } on InstallPermissionException catch (e) {
      needsInstallPermission = true;
      s.error = e.message;
    } on InstallCancelledException {
      s.error = null;
    } on InstallException catch (e) {
      s.error = e.message;
    } on DownloadException catch (e) {
      s.error = e.message;
    } catch (e) {
      s.error = 'Something went wrong: $e';
    } finally {
      s.phase = Phase.idle;
      notifyListeners();
    }
    await refreshInstalled();
  }

  Future<void> _guard(AppStatus s, Future<void> Function() action) async {
    s.error = null;
    try {
      await action();
    } on InstallException catch (e) {
      s.error = e.message;
    } catch (e) {
      s.error = e.toString();
    }
    notifyListeners();
  }
}
