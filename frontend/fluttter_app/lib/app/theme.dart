import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFFB71C1C);

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      );
}
