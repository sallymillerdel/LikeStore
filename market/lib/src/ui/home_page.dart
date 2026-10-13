import 'package:flutter/material.dart';

import '../config.g.dart';
import '../store_controller.dart';
import 'app_card.dart';
import 'app_details.dart';
import 'settings_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final updates = c.updateCount;
        return Scaffold(
          appBar: AppBar(
            title: const Text(kStoreName),
            actions: [
              if (updates > 1)
                TextButton.icon(
                  onPressed: c.updateAll,
                  icon: const Icon(Icons.system_update_alt),
                  label: Text('Update all ($updates)'),
                ),
              IconButton(
                tooltip: 'Check for updates',
                onPressed: c.loading ? null : c.refresh,
                icon: c.loading
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => showSettingsSheet(context, c),
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(onRefresh: c.refresh, child: _body(context)),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final banners = <Widget>[
      if (c.needsInstallPermission)
        _Banner(
          icon: Icons.lock_open,
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

    if (c.catalog == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...banners,
          const SizedBox(height: 120),
          Center(
            child: c.loading
                ? const CircularProgressIndicator()
                : Text('No catalog yet.', style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      );
    }

    if (c.apps.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...banners,
          const SizedBox(height: 120),
          Center(
            child: Text('No apps for this device yet.',
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final columns = (box.maxWidth / 460).floor().clamp(1, 3);
      final pad = box.maxWidth > 700 ? 24.0 : 12.0;
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            sliver: SliverList.list(children: [
              for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
            ]),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 124,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final s = c.apps[i];
                  return AppCard(
                    status: s,
                    controller: c,
                    onTap: () => showAppDetails(context, c, s),
                  );
                },
                childCount: c.apps.length,
              ),
            ),
          ),
        ],
      );
    });
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
    final bg = warning ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = warning ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
          TextButton(onPressed: onAction, child: Text(action)),
        ]),
      ),
    );
  }
}
