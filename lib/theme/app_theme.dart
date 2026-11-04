import 'package:flutter/material.dart';

/// Tema de color. Cada uno tiene versión clara y oscura.
class AppPalette {
  final String id;
  final String name;
  final Color accent;
  final Color accentDark;
  final Color lightBackground;
  final Color darkBackground;
  final Color lightSurface;
  final Color darkSurface;

  const AppPalette({
    required this.id,
    required this.name,
    required this.accent,
    required this.accentDark,
    required this.lightBackground,
    required this.darkBackground,
    required this.lightSurface,
    required this.darkSurface,
  });

  static const all = <AppPalette>[
    AppPalette(
      id: 'tinta',
      name: 'Tinta',
      accent: Color(0xFF2B4ACB),
      accentDark: Color(0xFF8DA2FF),
      lightBackground: Color(0xFFF6F6F3),
      darkBackground: Color(0xFF121316),
      lightSurface: Color(0xFFFFFFFF),
      darkSurface: Color(0xFF1B1D21),
    ),
    AppPalette(
      id: 'papel',
      name: 'Papel',
      accent: Color(0xFFB4532A),
      accentDark: Color(0xFFE59A73),
      lightBackground: Color(0xFFF4EFE6),
      darkBackground: Color(0xFF181512),
      lightSurface: Color(0xFFFBF8F2),
      darkSurface: Color(0xFF221E1A),
    ),
    AppPalette(
      id: 'bosque',
      name: 'Bosque',
      accent: Color(0xFF2D6A4F),
      accentDark: Color(0xFF7CC4A0),
      lightBackground: Color(0xFFF1F3EF),
      darkBackground: Color(0xFF111512),
      lightSurface: Color(0xFFFFFFFF),
      darkSurface: Color(0xFF1A201C),
    ),
    AppPalette(
      id: 'grafito',
      name: 'Grafito',
      accent: Color(0xFF26282C),
      accentDark: Color(0xFFE4E5E7),
      lightBackground: Color(0xFFF2F2F2),
      darkBackground: Color(0xFF0F0F10),
      lightSurface: Color(0xFFFFFFFF),
      darkSurface: Color(0xFF1A1A1C),
    ),
    AppPalette(
      id: 'ciruela',
      name: 'Ciruela',
      accent: Color(0xFF7A2E5C),
      accentDark: Color(0xFFE19AC4),
      lightBackground: Color(0xFFF6F1F3),
      darkBackground: Color(0xFF161114),
      lightSurface: Color(0xFFFFFFFF),
      darkSurface: Color(0xFF21191E),
    ),
  ];

  static AppPalette byId(String id) => all.firstWhere((p) => p.id == id, orElse: () => all.first);

  Color accentFor(Brightness b) => b == Brightness.dark ? accentDark : accent;

  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = accentFor(brightness);
    final bg = dark ? darkBackground : lightBackground;
    final surface = dark ? darkSurface : lightSurface;
    final onSurface = dark ? const Color(0xFFE8E8E6) : const Color(0xFF1C1C1E);
    final muted = dark ? const Color(0xFF9A9A9F) : const Color(0xFF6E6E73);
    final line = dark ? const Color(0xFF2C2D31) : const Color(0xFFE3E2DE);

    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF111111) : Colors.white,
      primaryContainer: primary.withValues(alpha: dark ? 0.22 : 0.12),
      onPrimaryContainer: primary,
      secondaryContainer: primary.withValues(alpha: dark ? 0.22 : 0.12),
      onSecondaryContainer: primary,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      outline: dark ? const Color(0xFF55565B) : const Color(0xFFB9B8B3),
      outlineVariant: line,
      surfaceContainerHighest: dark ? const Color(0xFF26272B) : const Color(0xFFEDECE8),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
    );
    final text = base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface);
    const radius = 12.0;
    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.05),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : muted, size: 24),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: s.contains(WidgetState.selected) ? primary : muted,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: BorderSide(color: line),
          selectedBackgroundColor: primary,
          selectedForegroundColor: scheme.onPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: line)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: line),
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: dark ? 0.25 : 0.12),
        labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    );
  }
}

/// Números de ancho fijo para que las horas queden alineadas.
const tabularFigures = [FontFeature.tabularFigures()];
