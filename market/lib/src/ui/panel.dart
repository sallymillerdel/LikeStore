import 'package:flutter/material.dart';

import 'theme.dart';

/// Windows-sized windows show pages as a centered dialog, phones as a sheet.
bool useDialog(BuildContext context) => MediaQuery.sizeOf(context).width > 700;

/// A centered dialog in the style of the Settings page.
Future<void> showPanelDialog(BuildContext context, {required WidgetBuilder builder, double maxWidth = 520}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: StoreColors.of(context).cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// The title row of a dialog page, with a close button.
class PanelTitle extends StatelessWidget {
  const PanelTitle({super.key, required this.child, this.dialog = true});

  final Widget child;
  final bool dialog;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, dialog ? 12 : 24, dialog ? 8 : 16),
      child: Row(
        children: [
          Expanded(child: child),
          if (dialog)
            IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

/// A rounded panel of list tiles.
class PanelGroup extends StatelessWidget {
  const PanelGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: panelDecoration(context, radius: 20),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}

