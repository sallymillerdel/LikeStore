import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.g.dart';
import '../installer/windows_installer.dart';
import '../store_controller.dart';
import 'format.dart';

Future<void> showSettingsSheet(BuildContext context, StoreController c) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _Settings(controller: c),
  );
}

class _Settings extends StatefulWidget {
  const _Settings({required this.controller});

  final StoreController controller;

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
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Settings', style: theme.textTheme.titleLarge),
        ),
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
        const Divider(height: 24),
        ListTile(
          dense: true,
          title: const Text('Store version'),
          trailing: Text(_version),
        ),
        ListTile(
          dense: true,
          title: const Text('Catalog'),
          subtitle: Text(kCatalogBaseUrl),
          trailing: Text(formatDate(c.catalog?.generatedAt)),
        ),
      ]),
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
