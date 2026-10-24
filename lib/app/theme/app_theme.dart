import 'package:flutter/material.dart';

/// Design tokens for Deutschap's "paper & ink" identity: warm paper
/// backgrounds, deep ink-teal for actions, amber for highlights.
/// See docs/DESIGN_SYSTEM.md.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.paper,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.der,
    required this.die,
    required this.das,
  });

  final Color paper;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkMuted;
  final Color line;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;

  /// Gender colours. Always shown together with the article text so the
  /// information never depends on colour alone.
  final Color der;
  final Color die;
  final Color das;

  Color article(String? a) => switch (a) {
        'der' => der,
        'die' => die,
        'das' => das,
        _ => inkMuted,
      };

  static const light = AppPalette(
    paper: Color(0xFFF5F0E6),
    surface: Color(0xFFFFFCF6),
    surfaceAlt: Color(0xFFEFE8DA),
    ink: Color(0xFF1D2731),
    inkMuted: Color(0xFF5B6670),
    line: Color(0xFFE0D6C4),
    primary: Color(0xFF1F5160),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFB8761E),
    accentSoft: Color(0xFFF4E3C6),
    success: Color(0xFF2F7350),
    successSoft: Color(0xFFDCEEDF),
    danger: Color(0xFFB23B2A),
    dangerSoft: Color(0xFFF7DDD6),
    der: Color(0xFF2D5BA8),
    die: Color(0xFFB0384A),
    das: Color(0xFF2F7D4F),
  );

  static const dark = AppPalette(
    paper: Color(0xFF11171C),
    surface: Color(0xFF182128),
    surfaceAlt: Color(0xFF202B33),
    ink: Color(0xFFECE6DA),
    inkMuted: Color(0xFFA3ADB5),
    line: Color(0xFF2B3740),
    primary: Color(0xFF7DB9C9),
    onPrimary: Color(0xFF0B1B20),
    accent: Color(0xFFE2A74F),
    accentSoft: Color(0xFF3A2E1C),
    success: Color(0xFF7CC59A),
    successSoft: Color(0xFF1D3326),
    danger: Color(0xFFE58A7A),
    dangerSoft: Color(0xFF3A221E),
    der: Color(0xFF8FB2EE),
    die: Color(0xFFF09AA6),
    das: Color(0xFF8FD3A8),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

/// Variable fonts need the weight axis set explicitly.
TextStyle weight(TextStyle s, int w) =>
    s.copyWith(fontWeight: FontWeight.values[(w ~/ 100) - 1], fontVariations: [FontVariation('wght', w.toDouble())]);

extension TextStyleWeight on TextStyle {
  TextStyle get regular => weight(this, 400);
  TextStyle get medium => weight(this, 500);
  TextStyle get semibold => weight(this, 600);
  TextStyle get bold => weight(this, 700);
}

extension AppThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;

  /// Serif style for German reading text (stories, texts, examples).
  TextStyle get reading => text.bodyLarge!.copyWith(fontFamily: 'Literata', fontSize: 19, height: 1.55, fontVariations: const [FontVariation('wght', 420)]);
}

class AppTheme {
  static const ui = 'Manrope';
  static const radius = 18.0;

  static ThemeData build(Brightness b) {
    final p = b == Brightness.light ? AppPalette.light : AppPalette.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.accent,
      onSecondary: p.onPrimary,
      error: p.danger,
      onError: p.onPrimary,
      surface: p.surface,
      onSurface: p.ink,
      surfaceContainerHighest: p.surfaceAlt,
      surfaceContainerHigh: p.surfaceAlt,
      surfaceContainer: p.surface,
      surfaceContainerLow: p.surface,
      outline: p.line,
      outlineVariant: p.line,
      onSurfaceVariant: p.inkMuted,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: ui, brightness: b);
    TextStyle? w(TextStyle? s, int weightValue, {double? size, double? height, double? spacing}) => s == null
        ? null
        : weight(s, weightValue).copyWith(color: p.ink, fontSize: size, height: height, letterSpacing: spacing);
    final t = base.textTheme;
    final text = t.copyWith(
      displaySmall: w(t.displaySmall, 700, size: 34, height: 1.15, spacing: -0.5),
      headlineMedium: w(t.headlineMedium, 700, size: 28, height: 1.2, spacing: -0.3),
      headlineSmall: w(t.headlineSmall, 700, size: 23, height: 1.25, spacing: -0.2),
      titleLarge: w(t.titleLarge, 700, size: 20, height: 1.3),
      titleMedium: w(t.titleMedium, 600, size: 16.5, height: 1.35),
      titleSmall: w(t.titleSmall, 600, size: 14.5),
      bodyLarge: w(t.bodyLarge, 400, size: 16.5, height: 1.5),
      bodyMedium: w(t.bodyMedium, 400, size: 15, height: 1.45),
      bodySmall: w(t.bodySmall, 500, size: 13, height: 1.4)?.copyWith(color: p.inkMuted),
      labelLarge: w(t.labelLarge, 600, size: 15),
      labelMedium: w(t.labelMedium, 600, size: 13),
      labelSmall: w(t.labelSmall, 600, size: 11.5, spacing: 0.4)?.copyWith(color: p.inkMuted),
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return base.copyWith(
      scaffoldBackgroundColor: p.paper,
      textTheme: text,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(side: BorderSide(color: p.line)),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: p.ink,
          side: BorderSide(color: p.line, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.primary, minimumSize: const Size(48, 44), textStyle: text.labelLarge),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accentSoft,
        side: BorderSide(color: p.line),
        labelStyle: text.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.primary, width: 2)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall!.copyWith(color: p.ink)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.ink : p.inkMuted)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: p.ink, contentTextStyle: text.bodyMedium!.copyWith(color: p.paper)),
      dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: p.line)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accentSoft : p.surface),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.surfaceAlt),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onPrimary : p.inkMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceAlt),
      ),
    );
  }
}
