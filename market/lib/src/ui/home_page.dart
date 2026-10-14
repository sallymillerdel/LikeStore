import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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
        body: PageBackground(
          child: SafeArea(
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
      ),
    );
  }

  Widget _refreshIcon() => c.loading
      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.refresh);

  /// Android: a floating pill with the title and two icon buttons.
  Widget _narrowBar(BuildContext context, double pad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 4),
      child: Container(
        decoration: panelDecoration(context, radius: 40),
        padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
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

    final bar = Container(
      decoration: BoxDecoration(
        color: x.card.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: x.cardBorder)),
      ),
      padding: EdgeInsets.fromLTRB(24, frame ? 10 : 12, frame ? 10 : 24, frame ? 10 : 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset('assets/logo.png', width: 36, height: 36, filterQuality: FilterQuality.medium),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              kStoreName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (labels)
            OutlinedButton.icon(
              onPressed: c.loading ? null : c.refresh,
              icon: _refreshIcon(),
              label: const Text('Check for updates'),
            )
          else
            IconButton(tooltip: 'Check for updates', onPressed: c.loading ? null : c.refresh, icon: _refreshIcon()),
          if (pending > 0) ...[
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: c.updateAll,
              icon: const Icon(Icons.download),
              label: Text(labels ? 'Update all ($pending)' : '$pending'),
            ),
          ],
          const SizedBox(width: 10),
          if (labels)
            OutlinedButton.icon(
              onPressed: settings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Settings'),
            )
          else
            IconButton(tooltip: 'Settings', onPressed: settings, icon: const Icon(Icons.settings_outlined)),
          if (frame) ...[
            Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 14), color: x.cardBorder),
            const WindowButtons(),
          ],
        ],
      ),
    );
    return frame ? DragToMoveArea(child: bar) : bar;
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

    Widget message(Widget child) => ListView(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
      children: [
        for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
        const SizedBox(height: 120),
        Center(child: child),
      ],
    );

    final textStyle = Theme.of(context).textTheme.bodyLarge;
    if (c.catalog == null) {
      return message(c.loading ? const CircularProgressIndicator() : Text('No catalog yet.', style: textStyle));
    }
    if (c.apps.isEmpty) return message(Text('No apps for this device yet.', style: textStyle));

    final columns = (width / 460).floor().clamp(1, 3);
    final pending = _pending;
    final sections = [
      (
        'Updates',
        [
          for (final a in c.apps)
            if (a.hasUpdate) a,
        ],
      ),
      (
        'Installed',
        [
          for (final a in c.apps)
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(pad, wide ? 20 : 12, pad, 24),
      children: [
        for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
        if (pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _UpdatesHero(apps: pending, wide: wide, onUpdateAll: c.updateAll),
          ),
        for (final (title, apps) in sections)
          if (apps.isNotEmpty) ...[
            _SectionHeader(title: title, count: apps.length),
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

/// "Updates ready — N apps can update", with the apps' icons and, on phones,
/// the Update all button (on Windows it sits in the top bar).
class _UpdatesHero extends StatelessWidget {
  const _UpdatesHero({required this.apps, required this.wide, required this.onUpdateAll});

  final List<AppStatus> apps;
  final bool wide;
  final VoidCallback onUpdateAll;

  @override
  Widget build(BuildContext context) {
    final x = StoreColors.of(context);
    final text = Theme.of(context).textTheme;
    final n = apps.length;
    final icons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final a in apps.take(wide ? 8 : 3)) AppIcon(url: a.app.icon, name: a.app.name, size: wide ? 40 : 38),
      ],
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Updates ready',
          style: text.titleSmall?.copyWith(color: x.heroLabel, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          n == 1 ? '1 app can update' : '$n apps can update',
          style: (wide ? text.headlineSmall : text.headlineMedium)?.copyWith(
            color: x.heroText,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: x.heroBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [x.heroStart, x.heroEnd],
        ),
        boxShadow: [if (x.shadow.a > 0) BoxShadow(color: x.shadow, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      padding: EdgeInsets.fromLTRB(wide ? 28 : 24, 22, wide ? 28 : 20, 22),
      child: wide
          ? Row(
              children: [
                Expanded(child: heading),
                icons,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: icons),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: onUpdateAll,
                      style: FilledButton.styleFrom(
                        backgroundColor: x.heroButton,
                        foregroundColor: x.heroButtonText,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        textStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      icon: const Icon(Icons.download),
                      label: Text('Update all ($n)'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 0, 12),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 26),
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(13)),
            child: Text(
              '$count',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
    final circle = warning ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = warning ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      decoration: warning
          ? panelDecoration(
              context,
              color: scheme.errorContainer.withValues(alpha: 0.35),
              border: scheme.error.withValues(alpha: 0.35),
            )
          : panelDecoration(context),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          const SizedBox(width: 4),
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
