import 'package:flutter/material.dart';

import 'colores.dart';

ThemeData construirTema() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ColoresDonTramite.azul,
      primary: ColoresDonTramite.azul,
      secondary: ColoresDonTramite.amarillo,
      surface: ColoresDonTramite.superficie,
    ),
    scaffoldBackgroundColor: ColoresDonTramite.fondo,
  );

  OutlineInputBorder borde(Color color, double grosor) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: grosor),
  );

  return base.copyWith(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ColoresDonTramite.blanco,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: borde(ColoresDonTramite.linea, 1),
      enabledBorder: borde(ColoresDonTramite.linea, 1),
      focusedBorder: borde(ColoresDonTramite.azul, 1.6),
      errorBorder: borde(Colors.red.shade400, 1),
      focusedErrorBorder: borde(Colors.red.shade600, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ColoresDonTramite.azul,
        foregroundColor: ColoresDonTramite.blanco,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: ColoresDonTramite.linea, space: 1),
  );
}
