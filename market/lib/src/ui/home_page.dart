import 'package:flutter/material.dart';

import '../config.g.dart';
import '../store_controller.dart';
import 'app_card.dart';
import 'app_details.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'window_frame.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final StoreController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppLifecycleListener _lifecycle;

  StoreController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Back from the Android install prompt, settings, or an uninstall.
    _lifecycle = AppLifecycleListener(onResume: c.refreshInstalled);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Apps with an update that is not already downloading or installing.
  List<AppStatus> get _pending => [
    for (final a in c.apps)
      if (a.hasUpdate && !a.busy) a,
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        // The list runs behind the Android gesture bar; its bottom padding
        // keeps the last card clear of it.
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > 700;
              final pad = wide ? 24.0 : 16.0;
              return Column(
                children: [
                  customWindowFrame || wide ? _desktopBar(context, box.maxWidth) : _narrowBar(context, pad),
                  Expanded(
                    child: RefreshIndicator(onRefresh: c.refresh, child: _body(context, box.maxWidth, pad, wide)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _refreshIcon() => c.loading
      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.refresh, size: 18);

  /// Android: the title and two icon buttons on the page background.
  Widget _narrowBar(BuildContext context, double pad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad + 4, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kStoreName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(tooltip: 'Check for updates', onPressed: c.loading ? null : c.refresh, icon: _refreshIcon()),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => showSettingsSheet(context, c),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  /// Windows: logo and title on the left, buttons on the right, and (with the
  /// custom window frame) the caption buttons. The whole bar drags the window.
  Widget _desktopBar(BuildContext context, double width) {
    final x = StoreColors.of(context);
    final pending = _pending.length;
    final frame = customWindowFrame;
    // Below this the labels no longer fit next to the caption buttons.
    final labels = width >= (frame ? 960 : 700);
    void settings() => showSettingsSheet(context, c);
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    );

    final row = Row(
      children: [
        // Not clickable, so the window drags from them too.
        IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.png', width: 32, height: 32, filterQuality: FilterQuality.medium),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: IgnorePointer(
            child: Text(
              kStoreName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        if (labels)
          OutlinedButton.icon(
            style: compact,
            onPressed: c.loading ? null : c.refresh,
            icon: _refreshIcon(),
            label: const Text('Check for updates'),
          )
        else
          IconButton(tooltip: 'Check for updates', onPressed: c.loading ? null : c.refresh, icon: _refreshIcon()),
        if (pending > 0) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            style: compact,
            onPressed: c.updateAll,
            icon: const Icon(Icons.download, size: 18),
            label: Text(labels ? 'Update all ($pending)' : '$pending', style: const TextStyle(fontFeatures: kTabular)),
          ),
        ],
        const SizedBox(width: 8),
        if (labels)
          OutlinedButton.icon(
            style: compact,
            onPressed: settings,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Settings'),
          )
        else
          IconButton(tooltip: 'Settings', onPressed: settings, icon: const Icon(Icons.settings_outlined)),
        if (frame) ...[
          IgnorePointer(
            child: Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: x.hairline,
            ),
          ),
          const WindowButtons(),
        ],
      ],
    );
    final padded = Padding(
      padding: EdgeInsets.fromLTRB(24, 8, frame ? 8 : 24, 8),
      child: SizedBox(height: 40, child: row),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: x.page,
        border: Border(bottom: BorderSide(color: x.hairline)),
      ),
      child: frame ? WindowDragArea(child: padded) : padded,
    );
  }

  Widget _body(BuildContext context, double width, double pad, bool wide) {
    final banners = <Widget>[
      if (c.needsInstallPermission)
        _Banner(
          icon: Icons.install_mobile,
          text: 'Allow $kStoreName to install apps. Android asks for this once.',
          action: 'Allow',
          onAction: c.openInstallPermissionSettings,
        ),
      if (c.catalogError != null)
        _Banner(
          icon: c.offline ? Icons.cloud_off : Icons.error_outline,
          text: c.offline ? 'Offline: showing the saved catalog. ${c.catalogError}' : c.catalogError!,
          action: 'Retry',
          onAction: c.refresh,
          warning: !c.offline,
        ),
    ];
    final top = wide ? 24.0 : 8.0;
    final inset = MediaQuery.paddingOf(context).bottom;

    Widget message(Widget child) => ListView(
      padding: EdgeInsets.fromLTRB(pad, top, pad, 24 + inset),
      children: [
        for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
        const SizedBox(height: 120),
        Center(child: child),
      ],
    );

    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (c.catalog == null) {
      return message(c.loading ? const CircularProgressIndicator() : Text('No catalog yet', style: textStyle));
    }
    if (c.apps.isEmpty) return message(Text('No apps for this device yet', style: textStyle));

    final columns = (width / 460).floor().clamp(1, 3);
    final pending = _pending;
    // The store's own card leads its section.
    final ordered = [...c.apps.where((a) => a.isStore), ...c.apps.where((a) => !a.isStore)];
    final sections = [
      (
        'Updates',
        [
          for (final a in ordered)
            if (a.hasUpdate) a,
        ],
      ),
      (
        'Installed',
        [
          for (final a in ordered)
            if (a.installed != null && !a.hasUpdate) a,
        ],
      ),
      (
        'Not installed',
        [
          for (final a in c.apps)
            if (a.installed == null) a,
        ],
      ),
    ];

    // The first header sits right under the top bar, without the gap that
    // separates it from a banner, the updates panel or another section.
    final leading = banners.isEmpty && pending.isEmpty
        ? sections.firstWhere((s) => s.$2.isNotEmpty).$1
        : null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(pad, top, pad, 32 + inset),
      children: [
        for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
        if (pending.isNotEmpty) _UpdatesHero(apps: pending, wide: wide, onUpdateAll: c.updateAll),
        for (final (title, apps) in sections)
          if (apps.isNotEmpty) ...[
            _SectionHeader(title: title, count: apps.length, first: title == leading),
            for (var i = 0; i < apps.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                // Cards in a row share the tallest card's height.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: 12),
                        Expanded(
                          child: j < apps.length
                              ? AppCard(
                                  status: apps[j],
                                  controller: c,
                                  onTap: () => showAppDetails(context, c, apps[j]),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

/// "Updates ready: N apps can update", with the apps' icons and their version
/// steps, and on phones the Update all button (on Windows it sits in the top
/// bar).
class _UpdatesHero extends StatelessWidget {
  const _UpdatesHero({required this.apps, required this.wide, required this.onUpdateAll});

  final List<AppStatus> apps;
  final bool wide;
  final VoidCallback onUpdateAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final n = apps.length;
    final shown = apps.take(wide ? 4 : 3).toList();

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Updates ready', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$n', style: TextStyle(color: scheme.primary)),
              TextSpan(text: n == 1 ? ' app can update' : ' apps can update'),
            ],
          ),
          style: text.headlineSmall?.copyWith(fontSize: wide ? 24 : 22, height: 32 / 24, fontFeatures: kTabular),
        ),
      ],
    );

    // One row per app: icon, name and the version it moves to.
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, a) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              AppIcon(url: a.app.icon, name: a.app.name, size: 28),
              const SizedBox(width: 12),
              SizedBox(
                width: wide ? 120 : null,
                child: Text(a.app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
              ),
              if (wide) ...[
                const SizedBox(width: 16),
                VersionStep(from: a.installed?.versionName ?? '', to: a.pkg.versionName),
              ] else ...[
                const SizedBox(width: 12),
                Expanded(child: VersionStep(from: a.installed?.versionName ?? '', to: a.pkg.versionName)),
              ],
            ],
          ),
        ],
        if (n > shown.length) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Text('and ${n - shown.length} more', style: text.bodySmall),
          ),
        ],
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: panelDecoration(context),
      padding: const EdgeInsets.all(24),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 24),
                list,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 20),
                list,
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onUpdateAll,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.download, size: 18),
                    label: Text('Update all ($n)', style: const TextStyle(fontFeatures: kTabular)),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, required this.first});

  final String title;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 0 : 24, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(width: 8),
          Text('$count', style: theme.textTheme.bodyMedium?.copyWith(color: StoreColors.of(context).muted, fontFeatures: kTabular)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
    this.warning = false,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: warning
          ? panelDecoration(context, color: scheme.errorContainer, border: scheme.error.withValues(alpha: 0.24))
          : panelDecoration(context),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Icon(icon, size: 18, color: warning ? scheme.error : scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            style: warning ? TextButton.styleFrom(foregroundColor: scheme.error) : null,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
