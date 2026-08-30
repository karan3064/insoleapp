import 'package:flutter/material.dart';

/// The subset of colors that actually flip between light and dark mode
/// (backgrounds, text, borders, card surfaces). Brand/semantic colors that
/// read fine on both (primary teal, gradients, status colors) stay as
/// static constants in [AppColors] instead of living here.
class AppPalette {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color btnColor;
  final List<BoxShadow> cardShadow;

  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.btnColor,
    required this.cardShadow,
  });

  /// Samsung Health style: soft white/near-white surfaces, card elevation
  /// via subtle shadow rather than a visible border.
  static const light = AppPalette(
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0F2F5),
    text: Color(0xFF1A1D1F),
    textSecondary: Color(0xFF6B7280),
    textTertiary: Color(0xFF9CA3AF),
    border: Color(0xFFE7E9EC),
    btnColor: Color(0xFFEFF2F5),
    cardShadow: [
      BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
    ],
  );

  /// Classic Samsung-Health-style AMOLED dark: a true black background
  /// (not navy) so accent colors and white text pop with real contrast,
  /// neutral (not blue-tinted) grays for secondary text, and card
  /// elevation via a visible border since shadows don't read on black.
  static const dark = AppPalette(
    bg: Color(0xFF000000),
    surface: Color(0xFF121212),
    surface2: Color(0xFF1C1C1E),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9AA0A6),
    textTertiary: Color(0xFF6B7076),
    border: Color(0xFF262626),
    btnColor: Color(0xFF1E1E1E),
    cardShadow: [],
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// The standard "card" look: a visible border in dark mode (shadows don't
  /// read on dark backgrounds), a soft shadow with no border in light mode
  /// (the Samsung-Health-style elevated white card).
  BoxDecoration card({double radius = 20}) {
    final isDark = cardShadow.isEmpty;
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: isDark ? Border.all(color: border) : null,
      boxShadow: cardShadow,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}
