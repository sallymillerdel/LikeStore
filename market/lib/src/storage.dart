import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config.g.dart';

/// Where the store keeps its own files.
///
/// Windows: %LocalAppData%\LikeStore (installed.json, downloads\, apps\),
/// the layout from MARKET_SPEC.md section 6.
/// Android: the app's private files dir, and its cache dir for downloads.
class Storage {
  Storage._(this.root, this.downloads);

  final Directory root;
  final Directory downloads;

  static Future<Storage> open() async {
    late Directory root, downloads;
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ??
          (await getApplicationSupportDirectory()).path;
      root = Directory(p.join(local, kStoreName));
      downloads = Directory(p.join(root.path, 'downloads'));
    } else {
      root = await getApplicationSupportDirectory();
      downloads = Directory(p.join((await getTemporaryDirectory()).path, 'downloads'));
    }
    await root.create(recursive: true);
    await downloads.create(recursive: true);
    return Storage._(root, downloads);
  }

  File file(String name) => File(p.join(root.path, name));

  Future<Map<String, dynamic>> readJson(String name) async {
    try {
      final f = file(name);
      if (await f.exists()) {
        final v = jsonDecode(await f.readAsString());
        if (v is Map<String, dynamic>) return v;
      }
    } catch (_) {
      // A corrupt state file is treated as empty.
    }
    return {};
  }

  /// Written to a temp file and renamed, so a crash never leaves half a file.
  Future<void> writeJson(String name, Map<String, dynamic> value) async {
    final f = file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(value), flush: true);
    await tmp.rename(f.path);
  }
}
