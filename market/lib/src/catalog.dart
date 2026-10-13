// The catalog format from MARKET_SPEC.md section 4. Unknown fields are ignored.

class Catalog {
  Catalog({required this.schemaVersion, required this.generatedAt, required this.apps});

  final int schemaVersion;
  final DateTime? generatedAt;
  final List<AppEntry> apps;

  factory Catalog.fromJson(Map<String, dynamic> json) {
    final apps = <AppEntry>[];
    for (final a in (json['apps'] as List? ?? const [])) {
      if (a is Map<String, dynamic>) {
        final entry = AppEntry.tryParse(a);
        if (entry != null) apps.add(entry);
      }
    }
    final at = json['generatedAt'];
    return Catalog(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      generatedAt: at is String ? DateTime.tryParse(at) : null,
      apps: apps,
    );
  }
}

class AppEntry {
  AppEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.packages,
  });

  final String id;
  final String name;
  final String description;
  final String? icon;

  /// Keyed by platform: "android" / "windows".
  final Map<String, PlatformPackage> packages;

  static AppEntry? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final packages = <String, PlatformPackage>{};
    final raw = json['packages'];
    if (raw is Map<String, dynamic>) {
      raw.forEach((platform, value) {
        if (value is Map<String, dynamic>) {
          final pkg = PlatformPackage.tryParse(value);
          if (pkg != null) packages[platform] = pkg;
        }
      });
    }
    return AppEntry(
      id: id,
      name: (json['name'] as String?) ?? id,
      description: (json['description'] as String?) ?? '',
      icon: json['icon'] as String?,
      packages: packages,
    );
  }
}

class PlatformPackage {
  PlatformPackage({
    required this.kind,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    required this.changelog,
    this.versionCode,
    this.packageName,
    this.minSdk,
    this.signingCertSha256,
    this.entry,
    this.releasedAt,
  });

  /// "apk" or "zip".
  final String kind;
  final String versionName;
  final String url;
  final String sha256;
  final int sizeBytes;
  final String changelog;

  // Android
  final int? versionCode;
  final String? packageName;
  final int? minSdk;
  final String? signingCertSha256;

  // Windows
  final String? entry;

  final DateTime? releasedAt;

  static PlatformPackage? tryParse(Map<String, dynamic> j) {
    final url = j['url'], sha = j['sha256'], version = j['versionName'];
    if (url is! String || sha is! String || version is! String) return null;
    // HTTPS only (MARKET_SPEC.md section 7).
    if (!url.startsWith('https://')) return null;
    final at = j['releasedAt'];
    return PlatformPackage(
      kind: (j['package'] as String?) ?? '',
      versionName: version,
      url: url,
      sha256: sha.toLowerCase(),
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      changelog: (j['changelog'] as String?) ?? '',
      versionCode: (j['versionCode'] as num?)?.toInt(),
      packageName: j['packageName'] as String?,
      minSdk: (j['minSdk'] as num?)?.toInt(),
      signingCertSha256: (j['signingCertSha256'] as String?)?.toLowerCase(),
      entry: j['entry'] as String?,
      releasedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }
}

/// What is installed on this device.
class InstalledInfo {
  const InstalledInfo({required this.versionName, this.versionCode});

  final String versionName;
  final int? versionCode;
}
