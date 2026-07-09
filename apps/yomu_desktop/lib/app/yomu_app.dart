import 'package:flutter/material.dart';
import 'package:yomu_ui/yomu_ui.dart';

import '../shell/home_shell.dart';

class YomuApp extends StatelessWidget {
  const YomuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yomu',
      debugShowCheckedModeBanner: false,
      theme: buildYomuTheme(),
      home: const HomeShell(),
    );
  }
}
