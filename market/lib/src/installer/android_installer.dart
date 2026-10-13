import 'dart:io';

import 'package:flutter/services.dart';

import '../catalog.dart';
import '../catalog_service.dart';
import '../config.g.dart';
import 'installer.dart';

/// Talks to MainActivity.kt / ApkInstaller.kt over a method channel. Installs
/// go through the PackageInstaller session API (MARKET_SPEC.md section 5).
class AndroidInstaller implements PlatformInstaller {
  static const _channel = MethodChannel('likestore/installer');

  @override
  String get platform => 'android';

  @override
  Future<void> init() async {}

  String _package(AppEntry app, PlatformPackage pkg) => pkg.packageName ?? app.id;

  @override
  Future<InstalledInfo?> installed(AppEntry app, PlatformPackage pkg) async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
        'getInstalled', {'packageName': _package(app, pkg)});
    if (r == null) return null;
    return InstalledInfo(
      versionName: r['versionName'] as String? ?? '',
      versionCode: (r['versionCode'] as num?)?.toInt(),
    );
  }

  @override
  bool canOpen(AppEntry app) => app.id != kMarketAppId;

  Future<bool> canRequestInstalls() async =>
      await _channel.invokeMethod<bool>('canRequestInstalls') ?? false;

  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  @override
  Future<bool> install(AppEntry app, PlatformPackage pkg, File file) async {
    if (!await canRequestInstalls()) throw InstallPermissionException();

    // The certificate check is optional in the spec but cheap, and it turns
    // Android's vague "app not installed" into a clear message.
    final expected = pkg.signingCertSha256;
    if (expected != null && expected.isNotEmpty) {
      final actual = await _channel.invokeMethod<String>('apkCertSha256', {'path': file.path});
      if (actual != null && actual.toLowerCase() != expected) {
        throw InstallException('The downloaded APK is signed with an unexpected certificate.');
      }
    }

    final r = await _channel.invokeMapMethod<String, dynamic>(
        'install', {'path': file.path, 'packageName': _package(app, pkg)});
    if (await file.exists()) await file.delete();
    switch (r?['status']) {
      case 'success':
        return false;
      case 'cancelled':
        throw InstallCancelledException();
      default:
        throw InstallException(_explain(r?['message'] as String?));
    }
  }

  static String _explain(String? message) {
    final m = message ?? '';
    if (m.contains('INCOMPATIBLE') || m.contains('signatures do not match')) {
      return 'The installed copy is signed with a different key. Uninstall it once, then install again.';
    }
    if (m.contains('INSUFFICIENT_STORAGE')) return 'Not enough storage to install.';
    if (m.contains('VERSION_DOWNGRADE')) return 'A newer version is already installed.';
    return m.isEmpty ? 'Installation failed.' : 'Installation failed: $m';
  }

  @override
  Future<void> open(AppEntry app, PlatformPackage pkg) async {
    final ok = await _channel.invokeMethod<bool>('launch', {'packageName': _package(app, pkg)});
    if (ok != true) throw InstallException('${app.name} cannot be opened.');
  }

  @override
  Future<void> uninstall(AppEntry app, PlatformPackage pkg) =>
      _channel.invokeMethod<void>('uninstall', {'packageName': _package(app, pkg)});

  /// Background update checks (WorkManager, every 6 hours).
  Future<void> setBackgroundCheck(bool enabled) => _channel.invokeMethod<void>(
      'setBackgroundCheck', {'enabled': enabled, 'catalogUrl': catalogFileUrl('catalog.json')});

  Future<bool> backgroundCheckEnabled() async =>
      await _channel.invokeMethod<bool>('backgroundCheckEnabled') ?? false;
}
