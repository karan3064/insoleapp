import 'package:flutter/material.dart';

/// Brand/semantic tokens that stay the same in both light and dark mode.
/// Backgrounds, text, borders, and card surfaces flip between themes --
/// see [AppPalette] / `context.palette` for those.
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

  /// Text/icon color for content drawn directly on top of [primary] --
  /// teal is bright enough in both themes that a dark color always reads
  /// best on it, so this doesn't flip with light/dark mode.
  static const onPrimary = Color(0xFF0F1720);

  // Per-category gradients -- classic Samsung Health used one fixed color
  // per metric category (green always meant activity, blue always meant
  // sleep, etc.), never an arbitrary rainbow reshuffled per card. These
  // three are assigned the same way: each metric card below always uses
  // the same one of these three, chosen by category, not by position.
  static const gradActivity = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );
  static const gradMechanics = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
  );
  static const gradBody = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
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
