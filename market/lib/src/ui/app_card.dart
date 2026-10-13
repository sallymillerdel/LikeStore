import 'package:flutter/material.dart';

import '../store_controller.dart';
import 'format.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.status, required this.controller, required this.onTap});

  final AppStatus status;
  final StoreController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(url: s.app.icon, name: s.app.name, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          s.app.description.isEmpty ? s.app.id : s.app.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActionButton(status: s, controller: controller),
                ],
              ),
              const Spacer(),
              _Footer(status: s),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.status});

  final AppStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    if (s.busy) {
      final label = s.phase == Phase.installing
          ? 'Installing...'
          : '${formatBytes(s.received)} of ${formatBytes(s.total)}';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(
          value: s.phase == Phase.installing ? null : s.progress,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Text(label, style: small),
      ]);
    }
    if (s.error != null) {
      return Row(children: [
        Icon(Icons.error_outline, size: 14, color: theme.colorScheme.error),
        const SizedBox(width: 4),
        Expanded(
          child: Text(s.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: small?.copyWith(color: theme.colorScheme.error)),
        ),
      ]);
    }
    final installed = s.installed;
    final text = installed == null
        ? '${s.pkg.versionName}  ·  ${formatBytes(s.pkg.sizeBytes)}'
        : s.hasUpdate
            ? '${installed.versionName}  →  ${s.pkg.versionName}  ·  ${formatBytes(s.pkg.sizeBytes)}'
            : 'Installed ${installed.versionName}';
    return Text(text, style: small);
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.status, required this.controller, this.expanded = false});

  final AppStatus status;
  final StoreController controller;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final s = status;
    Widget button;
    if (s.busy) {
      button = FilledButton.tonal(
        onPressed: null,
        child: Text(s.phase == Phase.installing
            ? 'Installing'
            : s.progress == null
                ? 'Downloading'
                : '${(s.progress! * 100).floor()}%'),
      );
    } else {
      switch (s.action(controller.canOpen(s))) {
        case AppAction.install:
          button = FilledButton(onPressed: () => controller.run(s), child: const Text('Install'));
        case AppAction.update:
          button = FilledButton(onPressed: () => controller.run(s), child: const Text('Update'));
        case AppAction.open:
          button = FilledButton.tonal(onPressed: () => controller.run(s), child: const Text('Open'));
        case AppAction.upToDate:
          button = const OutlinedButton(onPressed: null, child: Text('Up to date'));
      }
    }
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.url, required this.name, this.size = 48});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: url == null || !url!.startsWith('https://')
          ? fallback
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
            ),
    );
  }
}
