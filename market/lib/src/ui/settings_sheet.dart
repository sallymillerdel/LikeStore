import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.g.dart';
import '../installer/installer.dart';
import '../installer/windows_installer.dart';
import '../store_controller.dart';
import 'format.dart';
import 'panel.dart';

/// What the store is, shown under About.
const kStoreAbout = '$kStoreName is the official store for SLSoft apps. It installs SLSoft apps '
    'on Android and Windows and keeps them up to date.';

/// Settings: a bottom sheet on phones, a centered dialog on wide windows.
Future<void> showSettingsSheet(BuildContext context, StoreController c) {
  if (useDialog(context)) {
    return showPanelDialog(context, builder: (context) => _Settings(controller: c, dialog: true));
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
  String? _folderError;

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
          PanelTitle(dialog: widget.dialog, child: Text('Settings', style: theme.textTheme.headlineSmall)),
          PanelGroup(children: [
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
          PanelGroup(children: [
            ListTile(
              title: const Text('About'),
              subtitle: Text(kStoreAbout, style: muted?.copyWith(height: 1.4)),
            ),
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

  WindowsInstaller get _win => c.installer as WindowsInstaller;

  List<Widget> _windows(WindowsSettings s) => [
    ListTile(
      title: const Text('Install location'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(_win.appsDir),
          const SizedBox(height: 2),
          Text(
            _folderError ?? 'New installs and updates go here. Installed apps move on their next update.',
            style: TextStyle(
              fontSize: 12,
              color: _folderError != null ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: _win.openAppsDir, child: const Text('Open')),
          const SizedBox(width: 4),
          FilledButton.tonal(onPressed: _changeFolder, child: const Text('Change')),
        ],
      ),
    ),
    SwitchListTile(
      title: const Text('Start with Windows'),
      subtitle: const Text('Open $kStoreName when you sign in'),
      value: s.startWithSystem,
      onChanged: (v) async {
        await (c.installer as WindowsInstaller).setStartWithSystem(v);
        setState(() {});
      },
    ),
    SwitchListTile(
      title: const Text('Check for updates on startup'),
      value: s.checkOnStartup,
      onChanged: (v) async {
        await s.set('checkOnStartup', v);
        setState(() {});
      },
    ),
  ];

  Future<void> _changeFolder() async {
    final dir = await getDirectoryPath(
      initialDirectory: _win.appsDir,
      confirmButtonText: 'Use this folder',
    );
    if (dir == null) return;
    try {
      await _win.setAppsDir(dir);
      setState(() => _folderError = null);
    } on InstallException catch (e) {
      setState(() => _folderError = e.message);
    }
  }
}
