import 'package:flutter/material.dart';

import '../store_controller.dart';
import 'app_card.dart';
import 'format.dart';
import 'theme.dart';

Future<void> showAppDetails(BuildContext context, StoreController c, AppStatus s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) => _Details(controller: c, status: s),
    ),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.controller, required this.status});

  final StoreController controller;
  final AppStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final canUninstall = s.installed != null && !s.isStore && !s.busy;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              AppIcon(url: s.app.icon, name: s.app.name, size: 68),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.app.name, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(s.app.id, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
          if (s.app.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(s.app.description, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
          ],
          const SizedBox(height: 20),
          ActionButton(status: s, controller: controller, expanded: true),
          if (s.busy) ...[
            const SizedBox(height: 10),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: s.phase == Phase.installing ? null : s.progress,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (s.error != null) ...[
            const SizedBox(height: 10),
            Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (canUninstall) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmUninstall(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Uninstall'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            decoration: panelDecoration(context, radius: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _row(context, 'Installed', s.installed?.versionName ?? 'Not installed'),
                _row(
                  context,
                  'Available',
                  s.pkg.versionName + (s.pkg.versionCode != null ? '  (${s.pkg.versionCode})' : ''),
                  strong: s.hasUpdate,
                ),
                _row(context, 'Download size', formatBytes(s.pkg.sizeBytes)),
                if (s.pkg.releasedAt != null) _row(context, 'Released', formatDate(s.pkg.releasedAt)),
                if (s.pkg.minSdk != null) _row(context, 'Requires', 'Android API ${s.pkg.minSdk}+'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text("What's new", style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: panelDecoration(context, radius: 20),
            padding: const EdgeInsets.all(16),
            child: Text(
              s.pkg.changelog.isEmpty ? 'No changelog for this version.' : s.pkg.changelog,
              style: theme.textTheme.bodyMedium?.copyWith(color: s.pkg.changelog.isEmpty ? muted : null, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool strong = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: strong
                  ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUninstall(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Uninstall ${status.app.name}?'),
        content: const Text('The program is removed. Its own settings and data are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Uninstall')),
        ],
      ),
    );
    if (ok == true) await controller.uninstall(status);
  }
}
