String formatBytes(int n) {
  if (n <= 0) return '0 MB';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatDate(DateTime? d) {
  if (d == null) return '-';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
