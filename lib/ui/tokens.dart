import 'package:flutter/material.dart';

/// Design tokens of the WowUp Linux design (slate palette, light and dark).
@immutable
class WTokens extends ThemeExtension<WTokens> {
  const WTokens({
    required this.app,
    required this.surface,
    required this.alt,
    required this.border,
    required this.strong,
    required this.fg,
    required this.fg2,
    required this.muted,
    required this.hover,
    required this.chip,
    required this.sel,
    required this.selFg,
    required this.shadow,
    required this.side,
    required this.line,
    required this.track,
  });

  final Color app;
  final Color surface;
  final Color alt;
  final Color border;
  final Color strong;
  final Color fg;
  final Color fg2;
  final Color muted;
  final Color hover;
  final Color chip;
  final Color sel;
  final Color selFg;
  final List<BoxShadow> shadow;
  final Color side;
  final Color line;
  final Color track;

  static const light = WTokens(
    app: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    alt: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    strong: Color(0xFFCBD5E1),
    fg: Color(0xFF0F172A),
    fg2: Color(0xFF334155),
    muted: Color(0xFF64748B),
    hover: Color(0xFFF8FAFC),
    chip: Color(0xFFF1F5F9),
    sel: Color(0xFFEFF6FF),
    selFg: Color(0xFF1D4ED8),
    shadow: [
      BoxShadow(color: Color(0x1A0F172A), blurRadius: 3, offset: Offset(0, 1)),
    ],
    side: Color(0xFF0F172A),
    line: Color(0xFF1E293B),
    track: Color(0xFFE2E8F0),
  );

  static const dark = WTokens(
    app: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    alt: Color(0xFF162033),
    border: Color(0xFF334155),
    strong: Color(0xFF475569),
    fg: Color(0xFFF1F5F9),
    fg2: Color(0xFFCBD5E1),
    muted: Color(0xFF94A3B8),
    hover: Color(0xFF243044),
    chip: Color(0xFF334155),
    sel: Color(0x332563EB),
    selFg: Color(0xFF93C5FD),
    shadow: [
      BoxShadow(color: Color(0x80020617), blurRadius: 3, offset: Offset(0, 1)),
    ],
    side: Color(0xFF020617),
    line: Color(0xFF1E293B),
    track: Color(0xFF334155),
  );

  @override
  WTokens copyWith() => this;

  @override
  WTokens lerp(WTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Fixed accent colors shared by both themes.
abstract final class WColors {
  static const orange = Color(0xFFEA580C);
  static const orangeHover = Color(0xFFC2410C);
  static const blue = Color(0xFF2563EB);
  static const blueHover = Color(0xFF1D4ED8);
  static const blueLight = Color(0xFF3B82F6);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const amber = Color(0xFFD97706);
  static const disabled = Color(0xFF94A3B8);

  // Sidebar and title bar are dark in both themes.
  static const sideHover = Color(0xFF1E293B);
  static const sideText = Color(0xFFF8FAFC);
  static const sideMuted = Color(0xFF94A3B8);
  static const sideLabel = Color(0xFF64748B);
  static const sideDotBorder = Color(0xFF475569);
}

abstract final class WFonts {
  static const sans = 'Noto Sans';
  static const mono = 'Noto Sans Mono';
}

extension WTokensContext on BuildContext {
  WTokens get w => Theme.of(this).extension<WTokens>()!;
}

/// Frequently used text styles from the design.
abstract final class WText {
  static TextStyle title(BuildContext c) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.48,
    color: c.w.fg,
    height: 1.25,
  );

  static TextStyle cardTitle(BuildContext c) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.w.fg);

  static TextStyle body(BuildContext c) =>
      TextStyle(fontSize: 13, color: c.w.fg, height: 1.4);

  static TextStyle muted(BuildContext c, {double size = 12}) =>
      TextStyle(fontSize: size, color: c.w.muted, height: 1.4);

  static TextStyle mono(
    BuildContext c, {
    double size = 11,
    Color? color,
    FontWeight? weight,
  }) => TextStyle(
    fontFamily: WFonts.mono,
    fontSize: size,
    color: color ?? c.w.muted,
    fontWeight: weight,
    height: 1.4,
  );

  /// Uppercase section label (`WOW-CLIENT`, `VERWALTUNG`, ...).
  static TextStyle caps(Color color, {double spacing = 1.0}) => TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: spacing,
    color: color,
  );
}
