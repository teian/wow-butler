import 'package:flutter/material.dart';

import '../core/models/addon.dart';
import 'tokens.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light, WTokens.light);
  static ThemeData dark() => _build(Brightness.dark, WTokens.dark);

  static ThemeData _build(Brightness brightness, WTokens t) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: WColors.blue,
          brightness: brightness,
        ).copyWith(
          primary: WColors.blue,
          onPrimary: Colors.white,
          secondary: WColors.orange,
          error: WColors.red,
          surface: t.surface,
          onSurface: t.fg,
          onSurfaceVariant: t.muted,
          outline: t.strong,
          outlineVariant: t.border,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: WFonts.sans,
      scaffoldBackgroundColor: t.app,
      visualDensity: VisualDensity.compact,
      splashFactory: NoSplash.splashFactory,
      extensions: [t],
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: t.fg, displayColor: t.fg),
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: t.border),
        ),
        titleTextStyle: TextStyle(
          fontFamily: WFonts.sans,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: t.fg,
        ),
        contentTextStyle: TextStyle(
          fontFamily: WFonts.sans,
          fontSize: 13,
          color: t.fg2,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
          fontFamily: WFonts.sans,
          fontSize: 13,
          color: t.fg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: t.border),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: t.border),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(
          fontFamily: WFonts.sans,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 480,
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          fontFamily: WFonts.sans,
          fontSize: 13,
          color: Color(0xFFF1F5F9),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStatePropertyAll(t.strong),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: WColors.blue,
        linearTrackColor: t.track,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: WColors.blue,
        selectionColor: WColors.blue.withValues(alpha: 0.25),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? WColors.blue : t.surface,
        ),
        side: BorderSide(color: t.strong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

/// Badge colors per source (foreground, background).
({Color fg, Color bg}) sourceColors(BuildContext context, AddonSourceId? s) {
  final w = context.w;
  return switch (s) {
    AddonSourceId.curseforge => (
      fg: WColors.orange,
      bg: WColors.orange.withValues(alpha: 0.12),
    ),
    AddonSourceId.wago => (
      fg: WColors.blueLight,
      bg: WColors.blueLight.withValues(alpha: 0.14),
    ),
    AddonSourceId.wowup => (
      fg: const Color(0xFF8B5CF6),
      bg: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
    ),
    AddonSourceId.tukui => (
      fg: const Color(0xFF0D9488),
      bg: const Color(0xFF0D9488).withValues(alpha: 0.14),
    ),
    // Minion green, WoWInterface's own accent.
    AddonSourceId.wowinterface => (
      fg: const Color(0xFF65A30D),
      bg: const Color(0xFF65A30D).withValues(alpha: 0.14),
    ),
    AddonSourceId.github || null => (fg: w.fg2, bg: w.chip),
  };
}
