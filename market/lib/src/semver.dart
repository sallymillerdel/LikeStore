// Semantic version comparison for Windows packages (same rules as publish.py).

final _semver = RegExp(r'^v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$');

/// Negative if a < b, zero if equal, positive if a > b. Unparseable versions
/// sort below everything, so they are never offered as an update.
int compareVersions(String a, String b) {
  final ma = _semver.firstMatch(a.trim()), mb = _semver.firstMatch(b.trim());
  if (ma == null || mb == null) {
    if (ma == null && mb == null) return a.compareTo(b);
    return ma == null ? -1 : 1;
  }
  final na = ma.group(1)!.split('.').map(int.parse).toList();
  final nb = mb.group(1)!.split('.').map(int.parse).toList();
  final len = na.length > nb.length ? na.length : nb.length;
  for (var i = 0; i < len; i++) {
    final x = i < na.length ? na[i] : 0, y = i < nb.length ? nb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  final pa = ma.group(2), pb = mb.group(2);
  if (pa == null && pb == null) return 0;
  if (pa == null) return 1; // release > pre-release
  if (pb == null) return -1;
  final ia = pa.split('.'), ib = pb.split('.');
  for (var i = 0; i < ia.length && i < ib.length; i++) {
    final xa = int.tryParse(ia[i]), xb = int.tryParse(ib[i]);
    final c = (xa != null && xb != null)
        ? xa.compareTo(xb)
        : (xa != null)
            ? -1
            : (xb != null)
                ? 1
                : ia[i].compareTo(ib[i]);
    if (c != 0) return c;
  }
  return ia.length.compareTo(ib.length);
}
