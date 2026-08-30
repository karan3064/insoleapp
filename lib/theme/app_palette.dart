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

  /// The original dark navy look: card elevation via a visible border
  /// instead of a shadow (shadows don't read well on dark backgrounds).
  static const dark = AppPalette(
    bg: Color(0xFF0F1720),
    surface: Color(0xFF182430),
    surface2: Color(0xFF1F2E3B),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF92B7C9),
    textTertiary: Color(0xFF5B7A8C),
    border: Color(0xFF263542),
    btnColor: Color(0xFF233C48),
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
