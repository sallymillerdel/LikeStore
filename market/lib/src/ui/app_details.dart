import 'package:flutter/material.dart';

import '../store_controller.dart';
import 'app_card.dart';
import 'format.dart';
import 'panel.dart';
import 'theme.dart';

/// An app's page: a centered dialog laid out like Settings on wide windows,
/// a bottom sheet on phones.
Future<void> showAppDetails(BuildContext context, StoreController c, AppStatus s) {
  Widget page(bool dialog) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => _Details(controller: c, status: s, dialog: dialog),
  );
  if (useDialog(context)) {
    return showPanelDialog(context, maxWidth: 600, builder: (context) => page(true));
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => page(false),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.controller, required this.status, required this.dialog});

  final StoreController controller;
  final AppStatus status;
  final bool dialog;

  @override
  Widget build(BuildContext context) => dialog ? _dialog(context) : _sheet(context);

  // --- Windows: like the Settings dialog -------------------------------------

  Widget _dialog(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final canUninstall = s.installed != null && !s.isStore && !s.busy;

    Widget info(String label, String value, {bool strong = false}) => ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: strong
            ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)
            : muted,
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(
            child: Row(
              children: [
                AppIcon(url: s.app.icon, name: s.app.name, size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.app.name, style: theme.textTheme.headlineSmall),
                      Text(s.app.id, style: theme.textTheme.bodySmall?.copyWith(color: muted?.color)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (s.app.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(s.app.description, style: muted?.copyWith(fontSize: 15, height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 140, minHeight: 44),
                  child: ActionButton(status: s, controller: controller),
                ),
                if (canUninstall) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _confirmUninstall(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Uninstall'),
                  ),
                ],
                if (s.busy) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: s.phase == Phase.installing ? null : s.progress,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          PanelGroup(children: [
            info('Installed', s.installed?.versionName ?? 'Not installed'),
            info(
              'Available',
              s.pkg.versionName + (s.pkg.versionCode != null ? '  (${s.pkg.versionCode})' : ''),
              strong: s.hasUpdate,
            ),
            info('Download size', formatBytes(s.pkg.sizeBytes)),
            if (s.pkg.releasedAt != null) info('Released', formatDate(s.pkg.releasedAt)),
            if (s.pkg.minSdk != null) info('Requires', 'Android API ${s.pkg.minSdk}+'),
          ]),
          const SizedBox(height: 12),
          PanelGroup(children: [
            ListTile(
              title: const Text("What's new"),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  s.pkg.changelog.isEmpty ? 'No changelog for this version.' : s.pkg.changelog,
                  style: muted?.copyWith(height: 1.5),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // --- phones: a draggable bottom sheet --------------------------------------

  Widget _sheet(BuildContext context) {
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
