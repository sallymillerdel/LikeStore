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

  /// The set of updates the user put off with Later. The panel comes back
  /// when that set changes (a new version, another app) or on the next start.
  String? _later;

  static String _updateKey(List<AppStatus> apps) => [for (final a in apps) '${a.app.id}@${a.pkg.versionName}'].join(',');

  bool _panelShown(List<AppStatus> pending) => pending.isNotEmpty && _updateKey(pending) != _later;

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
    // The updates panel has its own Update all; the bar offers it only while
    // the panel is put off with Later.
    final pending = _panelShown(_pending) ? 0 : _pending.length;
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
    final panel = _panelShown(pending);
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
    final leading = banners.isEmpty && !panel
        ? sections.firstWhere((s) => s.$2.isNotEmpty).$1
        : null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(pad, top, pad, 32 + inset),
      children: [
        for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
        if (panel)
          _UpdatesPanel(
            apps: pending,
            wide: wide,
            onUpdateAll: c.updateAll,
            onLater: () => setState(() => _later = _updateKey(pending)),
            onOpen: (a) => showAppDetails(context, c, a),
          ),
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

/// "N updates available": the apps' icons stacked, their names, Later and
/// Update all, and under "Show versions" each app's version step.
class _UpdatesPanel extends StatefulWidget {
  const _UpdatesPanel({
    required this.apps,
    required this.wide,
    required this.onUpdateAll,
    required this.onLater,
    required this.onOpen,
  });

  final List<AppStatus> apps;
  final bool wide;
  final VoidCallback onUpdateAll;
  final VoidCallback onLater;
  final ValueChanged<AppStatus> onOpen;

  @override
  State<_UpdatesPanel> createState() => _UpdatesPanelState();
}

class _UpdatesPanelState extends State<_UpdatesPanel> {
  bool _open = false;

  /// "Classly", "Classly and Luma", "Classly, Luma, XReel and Zipper",
  /// "Classly, Luma, XReel and 3 more".
  static String _names(List<AppStatus> apps) {
    final names = [for (final a in apps) a.app.name];
    if (names.length == 1) return names.single;
    if (names.length <= 4) return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    return '${names.take(3).join(', ')} and ${names.length - 3} more';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final x = StoreColors.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final apps = widget.apps;
    final wide = widget.wide;
    final n = apps.length;
    final pad = wide ? 24.0 : 20.0;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          n == 1 ? '1 update available' : '$n updates available',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleLarge?.copyWith(fontFeatures: kTabular),
        ),
        const SizedBox(height: 2),
        Text(
          _names(apps),
          maxLines: wide ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(color: secondary),
        ),
      ],
    );
    final later = OutlinedButton(onPressed: widget.onLater, child: const Text('Later'));
    final updateAll = FilledButton(onPressed: widget.onUpdateAll, child: const Text('Update all'));

    final summary = wide
        ? Row(
            children: [
              _IconStack(apps: apps),
              const SizedBox(width: 16),
              Expanded(child: title),
              const SizedBox(width: 16),
              later,
              const SizedBox(width: 8),
              updateAll,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconStack(apps: apps),
              const SizedBox(height: 12),
              title,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: SizedBox(height: 44, child: later)),
                  const SizedBox(width: 8),
                  Expanded(child: SizedBox(height: 44, child: updateAll)),
                ],
              ),
            ],
          );

    final hairline = BorderSide(color: x.hairline);
    final toggle = InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Container(
        decoration: BoxDecoration(border: Border(top: hairline)),
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
        child: Row(
          children: [
            Text(_open ? 'Hide versions' : 'Show versions', style: text.bodyMedium?.copyWith(color: secondary)),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.arrow_drop_down, size: 20, color: secondary),
            ),
          ],
        ),
      ),
    );

    // Two apps per row on wide screens, split by hairlines like a table.
    final columns = wide ? 2 : 1;
    final versions = Column(
      children: [
        for (var i = 0; i < n; i += columns)
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: hairline)),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) VerticalDivider(width: 1, color: x.hairline),
                    Expanded(
                      child: j < n
                          ? _VersionRow(status: apps[j], pad: pad, onTap: () => widget.onOpen(apps[j]))
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: panelDecoration(context),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: EdgeInsets.all(pad), child: summary),
            toggle,
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open ? versions : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to four app icons overlapping left to right, each ringed in the card
/// color, then "+N" for the rest.
class _IconStack extends StatelessWidget {
  const _IconStack({required this.apps});

  final List<AppStatus> apps;

  static const _size = 36.0;
  static const _ring = 2.0;
  static const _step = 26.0;

  @override
  Widget build(BuildContext context) {
    final x = StoreColors.of(context);
    final shown = apps.take(apps.length > 4 ? 3 : 4).toList();
    final more = apps.length - shown.length;
    final count = shown.length + (more > 0 ? 1 : 0);
    const outer = _size + _ring * 2;

    Widget ring(Widget child) => Container(
      padding: const EdgeInsets.all(_ring),
      decoration: BoxDecoration(color: x.card, borderRadius: BorderRadius.circular(_size * 0.25 + _ring)),
      child: child,
    );

    return SizedBox(
      width: outer + _step * (count - 1),
      height: outer,
      child: Stack(
        children: [
          for (final (i, a) in shown.indexed)
            Positioned(left: _step * i, child: ring(AppIcon(url: a.app.icon, name: a.app.name, size: _size))),
          if (more > 0)
            Positioned(
              left: _step * shown.length,
              child: ring(
                Container(
                  width: _size,
                  height: _size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: x.raised, borderRadius: BorderRadius.circular(_size * 0.25)),
                  child: Text(
                    '+$more',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: kStrong, fontFeatures: kTabular),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One app in the expanded list: icon, name and `2.4.2 → 2.4.3`. Opens the
/// app's page.
class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.status, required this.pad, required this.onTap});

  final AppStatus status;
  final double pad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = status;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 14),
        child: Row(
          children: [
            AppIcon(url: a.app.icon, name: a.app.name, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                a.app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            VersionStep(from: a.installed?.versionName ?? '', to: a.pkg.versionName),
          ],
        ),
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
