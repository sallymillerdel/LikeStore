import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'config.g.dart';
import 'storage.dart';

class CatalogException implements Exception {
  CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogResult {
  CatalogResult(this.catalog, {required this.offline, this.error});

  final Catalog catalog;

  /// True when the catalog shown is the cached copy, not a fresh download.
  final bool offline;

  /// Why the fresh download failed, when [offline].
  final String? error;
}

/// Downloads, verifies and caches the catalog (MARKET_SPEC.md sections 3 and 7).
class CatalogService {
  CatalogService(this.storage, {http.Client? client}) : _client = client ?? http.Client();

  final Storage storage;
  final http.Client _client;

  static const _cacheFile = 'catalog.json';
  static const _cacheSigFile = 'catalog.json.sig';
  static const _stateFile = 'catalog_state.json';

  // Cache-busting: Pages sits behind a CDN with a ~10 minute cache.
  Uri _url(String name) =>
      Uri.parse('${catalogFileUrl(name)}?t=${DateTime.now().millisecondsSinceEpoch ~/ 1000}');

  /// The last verified catalog stored on this device, if any.
  Future<Catalog?> cached() async {
    try {
      final data = await storage.file(_cacheFile).readAsBytes();
      final sig = await storage.file(_cacheSigFile).readAsString();
      return await _verifyAndParse(data, sig);
    } catch (_) {
      return null;
    }
  }

  /// Fetches the live catalog; falls back to the cached one when offline.
  Future<CatalogResult> load() async {
    try {
      final fresh = await _fetch();
      return CatalogResult(fresh, offline: false);
    } catch (e) {
      final cache = await cached();
      if (cache == null) rethrow;
      return CatalogResult(cache, offline: true, error: _describe(e));
    }
  }

  Future<Catalog> _fetch() async {
    late http.Response data, sig;
    try {
      final responses = await Future.wait([
        _client.get(_url('catalog.json')),
        _client.get(_url('catalog.json.sig')),
      ]).timeout(const Duration(seconds: 20));
      data = responses[0];
      sig = responses[1];
    } on SocketException {
      throw CatalogException('No internet connection.');
    } on HttpException catch (e) {
      throw CatalogException('Network error: ${e.message}');
    }
    if (data.statusCode != 200 || sig.statusCode != 200) {
      throw CatalogException(
          'The catalog server answered ${data.statusCode}/${sig.statusCode}.');
    }
    final catalog = await _verifyAndParse(data.bodyBytes, sig.body);

    // Rollback protection: never accept a catalog older than one already seen.
    final state = await storage.readJson(_stateFile);
    final last = DateTime.tryParse(state['lastGeneratedAt'] as String? ?? '');
    final now = catalog.generatedAt;
    if (last != null && (now == null || now.isBefore(last))) {
      throw CatalogException(
          'The server sent an older catalog than this device has already seen. Ignoring it.');
    }

    await storage.file(_cacheFile).writeAsBytes(data.bodyBytes, flush: true);
    await storage.file(_cacheSigFile).writeAsString(sig.body, flush: true);
    if (now != null) {
      await storage.writeJson(_stateFile, {'lastGeneratedAt': now.toUtc().toIso8601String()});
    }
    return catalog;
  }

  Future<Catalog> _verifyAndParse(Uint8List data, String sigB64) async {
    if (kCatalogPublicKey.isEmpty) {
      throw CatalogException(
          'This build has no catalog public key. Run `publish.py keygen` and rebuild.');
    }
    final ok = await verifyCatalogSignature(data, sigB64, kCatalogPublicKey);
    if (!ok) {
      throw CatalogException('The catalog signature is invalid. Refusing to use it.');
    }
    final json = jsonDecode(utf8.decode(data));
    if (json is! Map<String, dynamic>) throw CatalogException('The catalog is malformed.');
    return Catalog.fromJson(json);
  }

  static String _describe(Object e) =>
      e is CatalogException ? e.message : 'Could not reach the catalog server.';
}

/// The URL of a file next to catalog.json (the single place hosting is configured).
String catalogFileUrl(String name) =>
    '${kCatalogBaseUrl.endsWith('/') ? kCatalogBaseUrl : '$kCatalogBaseUrl/'}$name';

/// Ed25519 over the exact bytes of catalog.json; [sigB64] and [publicKeyB64]
/// are base64 of the raw 64-byte signature and 32-byte public key.
Future<bool> verifyCatalogSignature(List<int> data, String sigB64, String publicKeyB64) async {
  try {
    final publicKey = SimplePublicKey(base64.decode(publicKeyB64), type: KeyPairType.ed25519);
    final signature = Signature(base64.decode(sigB64.trim()), publicKey: publicKey);
    return await Ed25519().verify(data, signature: signature);
  } catch (_) {
    return false;
  }
}
