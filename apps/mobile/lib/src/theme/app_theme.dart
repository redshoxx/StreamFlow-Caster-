import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF5B7CFA);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        navigationBarTheme: const NavigationBarThemeData(height: 70),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0B0D),
        navigationBarTheme: const NavigationBarThemeData(height: 70),
      );
}
