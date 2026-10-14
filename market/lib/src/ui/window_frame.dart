import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Windows draws its own title bar: the top bar of the home page is the drag
/// area and carries the minimize / maximize / close buttons.
bool get customWindowFrame => defaultTargetPlatform == TargetPlatform.windows;

/// Hides the native title bar before the first frame (the runner shows the
/// window only once Flutter has drawn, so the native bar never flashes).
Future<void> initWindowFrame() async {
  if (!Platform.isWindows) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(titleBarStyle: TitleBarStyle.hidden, minimumSize: Size(420, 480)),
  );
}

/// Minimize, maximize / restore and close, in the style of the top bar.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(tooltip: 'Minimize', icon: Icons.remove, onPressed: windowManager.minimize),
        _CaptionButton(
          tooltip: _maximized ? 'Restore' : 'Maximize',
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _maximized ? 15 : 18,
          onPressed: () => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _CaptionButton(tooltip: 'Close', icon: Icons.close, close: true, onPressed: windowManager.close),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 18,
    this.close = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final bool close;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = !_hover
        ? Colors.transparent
        : widget.close
        ? const Color(0xFFC42B1C)
        : scheme.onSurface.withValues(alpha: 0.08);
    final fg = _hover && widget.close ? Colors.white : scheme.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: 40,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
