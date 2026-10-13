import 'dart:io';

import '../catalog.dart';
import '../storage.dart';
import 'android_installer.dart';
import 'windows_installer.dart';

class InstallException implements Exception {
  InstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The app is running and must be closed by the user before it can change.
class AppRunningException extends InstallException {
  AppRunningException(String name) : super('$name is running. Close it, then try again.');
}

/// The user still has to allow installs from this store (Android).
class InstallPermissionException extends InstallException {
  InstallPermissionException()
      : super('Allow this store to install apps, then try again.');
}

/// The user dismissed the system install prompt.
class InstallCancelledException extends InstallException {
  InstallCancelledException() : super('Installation was cancelled.');
}

/// What each platform does with a verified download.
abstract class PlatformInstaller {
  /// "android" or "windows": the key into [AppEntry.packages].
  String get platform;

  Future<void> init();

  Future<InstalledInfo?> installed(AppEntry app, PlatformPackage pkg);

  /// Installs or updates from [file], which has already passed SHA-256 checks.
  /// Returns true when the store itself will now restart.
  Future<bool> install(AppEntry app, PlatformPackage pkg, File file);

  Future<void> open(AppEntry app, PlatformPackage pkg);

  Future<void> uninstall(AppEntry app, PlatformPackage pkg);

  /// Whether [open] makes sense (false for the store itself).
  bool canOpen(AppEntry app);

  static PlatformInstaller create(Storage storage, List<String> args) {
    if (Platform.isAndroid) return AndroidInstaller();
    if (Platform.isWindows) return WindowsInstaller(storage, args);
    throw UnsupportedError('LikeStore runs on Android and Windows.');
  }
}
