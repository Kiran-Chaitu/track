import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/scanner_screen.dart';

void main() {
  runApp(RegistrationScannerApp(config: AppConfig.fromEnvironment()));
}

class RegistrationScannerApp extends StatelessWidget {
  const RegistrationScannerApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2F4AA0);
    return MaterialApp(
      title: 'Registration Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: ScannerScreen(config: config),
    );
  }
}
