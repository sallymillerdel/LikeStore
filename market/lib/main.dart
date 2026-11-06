import 'package:flutter/material.dart';

import 'src/config.g.dart';
import 'src/store_controller.dart';
import 'src/ui/home_page.dart';
import 'src/ui/theme.dart';
import 'src/ui/window_frame.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initWindowFrame();
  final controller = await StoreController.create(args);
  runApp(LikeStoreApp(controller: controller));
  controller.start();
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
      home: HomePage(controller: controller),
    );
  }
}
