import 'package:flutter/material.dart';

/// Design tokens ported 1:1 from the Vue app's `styles/global.scss`.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF2DD4BF);
  static const primaryDark = Color(0xFF14B8A6);
  static const primaryLight = Color(0x292DD4BF); // rgba(45,212,191,0.16)

  // Semantic
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const error = Color(0xFFF87171);

  // Background
  static const bg = Color(0xFF0F1720);
  static const surface = Color(0xFF182430);
  static const surface2 = Color(0xFF1F2E3B);

  // Text
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF92B7C9);
  static const textTertiary = Color(0xFF5B7A8C);

  // Border
  static const border = Color(0xFF263542);

  static const btnColor = Color(0xFF233C48);

  // Gradients (Samsung Health style cards)
  static const gradBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
  );
  static const gradPurple = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFFD946EF)],
  );
  static const gradOrange = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
  );
  static const gradGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), Color(0xFF10B981)],
  );
  static const gradPink = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
  );

  // Heatmap color ramp (from chart/detail Heat component's visualMap)
  static const List<Color> heatRamp = [
    Color(0xFF8BC9EC),
    Color(0xFFFFEDEA),
    Color(0xFFFBDAD5),
    Color(0xFFFEC4BC),
    Color(0xFFF9B8AF),
    Color(0xFFFDADA2),
    Color(0xFFFF1F04),
    Color(0xFFFF0000),
  ];
}
