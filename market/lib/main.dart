import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.g.dart';
import 'src/store_controller.dart';
import 'src/ui/home_page.dart';
import 'src/ui/theme.dart';
import 'src/ui/window_frame.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initWindowFrame();
  // Android: draw behind the status and navigation bars instead of letting
  // the system paint them black. Content keeps clear of them through the
  // MediaQuery padding (SafeArea and the list's bottom padding).
  if (Platform.isAndroid) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final controller = await StoreController.create(args);
  runApp(LikeStoreApp(controller: controller));
  controller.start();
}

/// Transparent system bars with icons that read on the current theme.
SystemUiOverlayStyle systemBars(Brightness theme) {
  final icons = theme == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: theme,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    // Otherwise Android adds its own translucent scrim behind 3-button navigation.
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

class LikeStoreApp extends StatelessWidget {
  const LikeStoreApp({super.key, required this.controller});

  final StoreController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kStoreName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBars(Theme.of(context).brightness),
        child: child!,
      ),
      home: HomePage(controller: controller),
    );
  }
}
