import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef Progress = void Function(int received, int total);

/// Downloads [url] to [dest], resuming a previous partial download when the
/// server allows it, and verifies the SHA-256 before returning
/// (MARKET_SPEC.md section 7). A file that fails verification is deleted.
Future<File> downloadVerified({
  required String url,
  required File dest,
  required String sha256Hex,
  required int expectedSize,
  required Progress onProgress,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final part = File('${dest.path}.part');
  try {
    // A complete file left over from an earlier attempt may already be good.
    if (await dest.exists()) {
      if (await _sha256(dest) == sha256Hex) return dest;
      await dest.delete();
    }

    var offset = await part.exists() ? await part.length() : 0;
    if (expectedSize > 0 && offset > expectedSize) {
      await part.delete();
      offset = 0;
    }

    final req = http.Request('GET', Uri.parse(url));
    if (offset > 0) req.headers['Range'] = 'bytes=$offset-';
    final http.StreamedResponse res;
    try {
      res = await c.send(req).timeout(const Duration(seconds: 30));
    } on SocketException {
      throw DownloadException('No internet connection.');
    } on TimeoutException {
      throw DownloadException('The download server did not respond.');
    }

    if (res.statusCode == 200) {
      offset = 0; // server ignored the range: start over
    } else if (res.statusCode == 416) {
      // Range not satisfiable: the partial file is complete or invalid.
      await res.stream.drain<void>();
    } else if (res.statusCode != 206) {
      await res.stream.drain<void>();
      throw DownloadException('Download failed (HTTP ${res.statusCode}).');
    }

    if (res.statusCode != 416) {
      final total = expectedSize > 0 ? expectedSize : offset + (res.contentLength ?? 0);
      final sink = part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
      var received = offset;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastReport).inMilliseconds > 100) {
            lastReport = now;
            onProgress(received, total);
          }
        }
        await sink.flush();
      } on TimeoutException {
        throw DownloadException('The download stalled. Try again to resume it.');
      } on SocketException {
        throw DownloadException('The connection was lost. Try again to resume it.');
      } on http.ClientException {
        throw DownloadException('The connection was lost. Try again to resume it.');
      } finally {
        await sink.close();
      }
      onProgress(received, total);
    }

    if (await _sha256(part) != sha256Hex) {
      await part.delete();
      throw DownloadException(
          'The downloaded file does not match the catalog (SHA-256 mismatch). It was deleted.');
    }
    return await part.rename(dest.path);
  } on FileSystemException catch (e) {
    if (_isDiskFull(e)) {
      if (await part.exists()) await part.delete();
      throw DownloadException('Not enough free storage for this download.');
    }
    throw DownloadException('Could not write the download: ${e.message}');
  } finally {
    if (client == null) c.close();
  }
}

Future<String> _sha256(File f) async => (await sha256.bind(f.openRead()).first).toString();

bool _isDiskFull(FileSystemException e) {
  final code = e.osError?.errorCode;
  // ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL on Windows, ENOSPC on Linux/Android.
  return code == 112 || code == 39 || code == 28;
}
