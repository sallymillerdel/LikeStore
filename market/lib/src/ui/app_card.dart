import 'package:flutter/material.dart';

import '../store_controller.dart';
import 'format.dart';
import 'theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.status, required this.controller, required this.onTap});

  final AppStatus status;
  final StoreController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);

    return DecoratedBox(
      decoration: panelDecoration(context),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(url: s.app.icon, name: s.app.name, size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            s.app.description.isEmpty ? s.app.id : s.app.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ActionButton(status: s, controller: controller),
                  ],
                ),
                const SizedBox(height: 16),
                // The home grid stretches cards in a row to the same height.
                const Spacer(),
                const Divider(),
                const SizedBox(height: 12),
                _Footer(status: s),
              ],
            ),
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
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(fontFeatures: kTabular);

    if (s.busy) {
      final label = s.phase == Phase.installing
          ? 'Installing'
          : '${formatBytes(s.received)} of ${formatBytes(s.total)}';
      return SizedBox(
        height: 18,
        child: Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: s.phase == Phase.installing ? null : s.progress,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            Text(label, style: small),
          ],
        ),
      );
    }
    if (s.error != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: 16, color: scheme.error),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: small?.copyWith(color: scheme.error),
            ),
          ),
        ],
      );
    }
    final installed = s.installed;
    if (installed != null && s.hasUpdate) {
      return Row(
        children: [
          Flexible(child: VersionStep(from: installed.versionName, to: s.pkg.versionName)),
          Text('  ·  ${formatBytes(s.pkg.sizeBytes)}', style: small),
        ],
      );
    }
    final text = installed == null
        ? '${s.pkg.versionName}  ·  ${formatBytes(s.pkg.sizeBytes)}'
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
    final theme = Theme.of(context);
    final x = StoreColors.of(context);
    Widget button;
    if (s.busy) {
      button = FilledButton.tonal(
        onPressed: null,
        style: FilledButton.styleFrom(
          disabledBackgroundColor: x.accentTint,
          disabledForegroundColor: x.accent,
          textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: kStrong, fontFeatures: kTabular),
        ),
        child: Text(
          s.phase == Phase.installing
              ? 'Installing'
              : s.progress == null
              ? 'Downloading'
              : '${(s.progress! * 100).floor()}%',
        ),
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
          button = OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: x.muted,
              side: BorderSide(color: x.hairline),
              textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
            ),
            child: const Text('Up to date'),
          );
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
    final x = StoreColors.of(context);
    final fallback = Container(
      width: size,
      height: size,
      color: x.raised,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.4, fontWeight: kStrong, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
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
