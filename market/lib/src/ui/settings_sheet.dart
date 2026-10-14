import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.g.dart';
import '../installer/windows_installer.dart';
import '../store_controller.dart';
import 'format.dart';
import 'theme.dart';

/// Settings: a bottom sheet on phones, a centered dialog on wide windows.
Future<void> showSettingsSheet(BuildContext context, StoreController c) {
  if (MediaQuery.sizeOf(context).width > 700) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: StoreColors.of(context).cardBorder),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _Settings(controller: c, dialog: true),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _Settings(controller: c, dialog: false),
  );
}

class _Settings extends StatefulWidget {
  const _Settings({required this.controller, required this.dialog});

  final StoreController controller;
  final bool dialog;

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  String _version = '';
  bool? _background;

  StoreController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) => setState(() => _version = i.version));
    c.android?.backgroundCheckEnabled().then((v) => setState(() => _background = v));
  }

  @override
  Widget build(BuildContext context) {
    final win = c.windowsSettings;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: widget.dialog ? 12 : 0, bottom: widget.dialog ? 20 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, widget.dialog ? 12 : 24, widget.dialog ? 8 : 16),
            child: Row(
              children: [
                Expanded(child: Text('Settings', style: theme.textTheme.headlineSmall)),
                if (widget.dialog)
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          _group(context, [
            if (win != null) ..._windows(win),
            if (c.android != null)
              SwitchListTile(
                title: const Text('Check for updates in the background'),
                subtitle: const Text('Every few hours, with a notification when updates exist'),
                value: _background ?? false,
                onChanged: _background == null
                    ? null
                    : (v) async {
                        await c.android!.setBackgroundCheck(v);
                        setState(() => _background = v);
                      },
              ),
          ]),
          const SizedBox(height: 12),
          _group(context, [
            ListTile(
              title: const Text('Store version'),
              trailing: Text(_version, style: muted),
            ),
            ListTile(
              title: const Text('Catalog'),
              subtitle: Text(kCatalogBaseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(formatDate(c.catalog?.generatedAt), style: muted),
            ),
          ]),
        ],
      ),
    );
  }

  /// A rounded panel of list tiles.
  Widget _group(BuildContext context, List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: panelDecoration(context, radius: 20),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: tiles),
      ),
    );
  }

  List<Widget> _windows(WindowsSettings s) => [
    SwitchListTile(
      title: const Text('Start Menu shortcuts'),
      value: s.startMenuShortcut,
      onChanged: (v) => _set(s, 'startMenuShortcut', v),
    ),
    SwitchListTile(
      title: const Text('Desktop shortcuts'),
      value: s.desktopShortcut,
      onChanged: (v) => _set(s, 'desktopShortcut', v),
    ),
    SwitchListTile(
      title: const Text('Check for updates on startup'),
      value: s.checkOnStartup,
      onChanged: (v) => _set(s, 'checkOnStartup', v, refreshShortcuts: false),
    ),
  ];

  Future<void> _set(WindowsSettings s, String key, bool v, {bool refreshShortcuts = true}) async {
    await s.set(key, v);
    setState(() {});
    if (refreshShortcuts) await (c.installer as WindowsInstaller).refreshShortcuts();
  }
}
