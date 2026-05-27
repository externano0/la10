import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData la10LightTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Tokens.seed),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

ThemeData la10DarkTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Tokens.seed, brightness: Brightness.dark),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
