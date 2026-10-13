import 'package:flutter/material.dart';

import 'src/config.g.dart';
import 'src/store_controller.dart';
import 'src/ui/home_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await StoreController.create(args);
  runApp(LikeStoreApp(controller: controller));
  controller.start();
}

class LikeStoreApp extends StatelessWidget {
  const LikeStoreApp({super.key, required this.controller});

  final StoreController controller;

  static const _seed = Color(0xFF4F46E5);

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kStoreName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(controller: controller),
    );
  }
}
