import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PMV2Colors {
  static const brandAction = Color(0xFF48BB78); // Success / Verde Menta
  static const primary = Color(0xFF1A365D); // Azul Marino
  static const primaryContainer = Color(0xFFEDF2F7);
  static const onPrimaryContainer = Color(0xFF0A2010);
  static const tertiary = Color(0xFF4A624D);
  static const tertiaryContainer = Color(0xFF637A64);
  static const tertiaryFixed = Color(0xFFCFE9CF);
  static const tertiaryFixedDim = Color(0xFFB3CDB4);
  static const onTertiaryFixed = Color(0xFF0A2010);
  static const surface = Color(0xFFEDF2F7); // Escala de grises limpios
  static const surfaceContainer = Color(0xFFF5EDE4);
  static const surfaceContainerLow = Color(0xFFFAF2E9);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerHigh = Color(0xFFEFE7DE);
  static const surfaceContainerHighest = Color(0xFFE9E1D8);
  static const onSurface = Color(0xFF1E1B16);
  static const onSurfaceVariant = Color(0xFF58423B);
  static const outline = Color(0xFF8B716A);
  static const outlineVariant = Color(0xFFDFC0B7);
  static const secondaryContainer = Color(0xFFEEDDC8);
  static const error = Color(0xFFBA1A1A);
  static const aversiveAccent = Color(0xFFA43714);
}

class PMV2Theme {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PMV2Colors.primary,
        primary: PMV2Colors.primary,
        primaryContainer: PMV2Colors.primaryContainer,
        onPrimaryContainer: PMV2Colors.onPrimaryContainer,
        tertiary: PMV2Colors.tertiary,
        tertiaryContainer: PMV2Colors.tertiaryContainer,
        surface: PMV2Colors.surface,
        onSurface: PMV2Colors.onSurface,
        onSurfaceVariant: PMV2Colors.onSurfaceVariant,
        outline: PMV2Colors.outline,
        outlineVariant: PMV2Colors.outlineVariant,
        error: PMV2Colors.error,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: PMV2Colors.surface,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: PMV2Colors.onSurface,
        displayColor: PMV2Colors.onSurface,
      ),
    );
  }
}
