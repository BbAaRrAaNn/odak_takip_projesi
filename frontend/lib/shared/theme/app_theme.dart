import 'package:flutter/material.dart';

class AppTheme {
  static _ThemePalette _palette = _lightPalette;
  static String _themeMode = 'light';
  static String _colorVisionMode = 'standard';

  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceMuted => _palette.surfaceMuted;
  static Color get border => _palette.border;
  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textMuted => _palette.textMuted;
  static Color get focusGreen => _palette.focusGreen;
  static Color get focusStrongGreen => _palette.focusStrongGreen;
  static Color get focusAmber => _palette.focusAmber;
  static Color get focusOrange => _palette.focusOrange;
  static Color get dangerRed => _palette.dangerRed;
  static Color get warningOrange => _palette.warningOrange;
  static Color get calmBlue => _palette.calmBlue;
  static Color get onPrimary => foregroundFor(textPrimary);

  static bool get isDark => _themeMode == 'dark';
  static String get colorVisionMode => _colorVisionMode;

  static void configure({
    required String themeMode,
    required String colorVisionMode,
  }) {
    _themeMode = themeMode == 'dark' ? 'dark' : 'light';
    _colorVisionMode = _supportedColorVisionModes.contains(colorVisionMode)
        ? colorVisionMode
        : 'standard';

    final base = isDark ? _darkPalette : _lightPalette;
    _palette = _applyColorVisionMode(base, _colorVisionMode);
  }

  static ThemeData get lightTheme => _themeData(Brightness.light);

  static ThemeData get darkTheme => _themeData(Brightness.dark);

  static ThemeData get currentTheme =>
      _themeData(isDark ? Brightness.dark : Brightness.light);

  static ThemeMode get materialThemeMode =>
      isDark ? ThemeMode.dark : ThemeMode.light;

  static Color foregroundFor(Color background) {
    return background.computeLuminance() > 0.54
        ? const Color(0xFF111111)
        : Colors.white;
  }

  static const Set<String> _supportedColorVisionModes = {
    'standard',
    'protanopia',
    'deuteranopia',
    'tritanopia',
    'achromatopsia',
  };

  static ThemeData _themeData(Brightness brightness) {
    final onSurface = textPrimary;
    final selectedFill = calmBlue.withValues(alpha: isDark ? 0.22 : 0.14);
    final hoverFill = surfaceMuted.withValues(alpha: isDark ? 0.88 : 0.72);
    final pressedFill = calmBlue.withValues(alpha: isDark ? 0.28 : 0.18);
    final disabledFill = surfaceMuted.withValues(alpha: 0.56);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      fontFamily: 'SF Pro Display',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: textPrimary,
        onPrimary: onPrimary,
        secondary: calmBlue,
        onSecondary: foregroundFor(calmBlue),
        error: dangerRed,
        onError: foregroundFor(dangerRed),
        surface: surface,
        onSurface: onSurface,
      ),
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      dividerColor: border,
      cardColor: surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: background,
        foregroundColor: textPrimary,
        centerTitle: false,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.4,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        bodyLarge: TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w600,
          height: 1.55,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: calmBlue),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: textPrimary,
        inactiveTrackColor: border,
        thumbColor: textPrimary,
        overlayColor: textPrimary.withValues(alpha: 0.08),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: TextStyle(
          color: onPrimary,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: textPrimary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: textMuted,
          disabledForegroundColor: foregroundFor(textMuted),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return textMuted;
            if (states.contains(WidgetState.pressed)) return textPrimary;
            return textPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return disabledFill;
            if (states.contains(WidgetState.pressed)) return pressedFill;
            if (states.contains(WidgetState.hovered)) return hoverFill;
            return surface;
          }),
          overlayColor: WidgetStatePropertyAll(
            calmBlue.withValues(alpha: 0.08),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: border.withValues(alpha: 0.55));
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return BorderSide(color: calmBlue.withValues(alpha: 0.58));
            }
            return BorderSide(color: border);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(textPrimary),
          overlayColor: WidgetStatePropertyAll(
            calmBlue.withValues(alpha: 0.08),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(textSecondary),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return pressedFill;
            if (states.contains(WidgetState.hovered)) return hoverFill;
            return Colors.transparent;
          }),
          overlayColor: WidgetStatePropertyAll(
            calmBlue.withValues(alpha: 0.08),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return textMuted;
          if (states.contains(WidgetState.selected)) return textPrimary;
          return surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledFill;
          if (states.contains(WidgetState.selected)) {
            return calmBlue.withValues(alpha: isDark ? 0.42 : 0.34);
          }
          return textMuted.withValues(alpha: isDark ? 0.34 : 0.24);
        }),
        trackOutlineColor: WidgetStatePropertyAll(border),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return textMuted;
            if (states.contains(WidgetState.selected)) return textPrimary;
            return textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return disabledFill;
            if (states.contains(WidgetState.selected)) return selectedFill;
            if (states.contains(WidgetState.pressed)) return pressedFill;
            if (states.contains(WidgetState.hovered)) return hoverFill;
            return surface;
          }),
          overlayColor: WidgetStatePropertyAll(
            calmBlue.withValues(alpha: 0.08),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: calmBlue.withValues(alpha: 0.62));
            }
            return BorderSide(color: border);
          }),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: selectedFill,
        disabledColor: disabledFill,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
        checkmarkColor: textPrimary,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  static _ThemePalette _applyColorVisionMode(
    _ThemePalette base,
    String colorVisionMode,
  ) {
    switch (colorVisionMode) {
      case 'protanopia':
        return isDark
            ? base.copyWith(
                focusStrongGreen: const Color(0xFF7DD3FC),
                focusGreen: const Color(0xFF5EEAD4),
                focusAmber: const Color(0xFFFBBF24),
                focusOrange: const Color(0xFFFB923C),
                dangerRed: const Color(0xFFF0ABFC),
                warningOrange: const Color(0xFFFBBF24),
                calmBlue: const Color(0xFF93C5FD),
              )
            : base.copyWith(
                focusStrongGreen: const Color(0xFF0072B2),
                focusGreen: const Color(0xFF009E73),
                focusAmber: const Color(0xFFE69F00),
                focusOrange: const Color(0xFFD55E00),
                dangerRed: const Color(0xFFCC79A7),
                warningOrange: const Color(0xFFE69F00),
                calmBlue: const Color(0xFF0072B2),
              );
      case 'deuteranopia':
        return isDark
            ? base.copyWith(
                focusStrongGreen: const Color(0xFF7DD3FC),
                focusGreen: const Color(0xFF93C5FD),
                focusAmber: const Color(0xFFFBBF24),
                focusOrange: const Color(0xFFFB923C),
                dangerRed: const Color(0xFFF0ABFC),
                warningOrange: const Color(0xFFFBBF24),
                calmBlue: const Color(0xFF7DD3FC),
              )
            : base.copyWith(
                focusStrongGreen: const Color(0xFF0072B2),
                focusGreen: const Color(0xFF56B4E9),
                focusAmber: const Color(0xFFE69F00),
                focusOrange: const Color(0xFFD55E00),
                dangerRed: const Color(0xFFCC79A7),
                warningOrange: const Color(0xFFE69F00),
                calmBlue: const Color(0xFF0072B2),
              );
      case 'tritanopia':
        return isDark
            ? base.copyWith(
                focusStrongGreen: const Color(0xFF34D399),
                focusGreen: const Color(0xFF86EFAC),
                focusAmber: const Color(0xFFFBBF24),
                focusOrange: const Color(0xFFFB923C),
                dangerRed: const Color(0xFFF87171),
                warningOrange: const Color(0xFFFB923C),
                calmBlue: const Color(0xFFF0ABFC),
              )
            : base.copyWith(
                focusStrongGreen: const Color(0xFF008A5E),
                focusGreen: const Color(0xFF2CA25F),
                focusAmber: const Color(0xFFA66A00),
                focusOrange: const Color(0xFFD55E00),
                dangerRed: const Color(0xFFE41A1C),
                warningOrange: const Color(0xFFD55E00),
                calmBlue: const Color(0xFF9C4D91),
              );
      case 'achromatopsia':
        return base.copyWith(
          focusStrongGreen: isDark
              ? const Color(0xFFE5E7EB)
              : const Color(0xFF111827),
          focusGreen: isDark
              ? const Color(0xFFD1D5DB)
              : const Color(0xFF374151),
          focusAmber: isDark
              ? const Color(0xFF9CA3AF)
              : const Color(0xFF6B7280),
          focusOrange: isDark
              ? const Color(0xFF6B7280)
              : const Color(0xFF4B5563),
          dangerRed: isDark ? const Color(0xFFF9FAFB) : const Color(0xFF030712),
          warningOrange: isDark
              ? const Color(0xFF9CA3AF)
              : const Color(0xFF6B7280),
          calmBlue: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
        );
      default:
        return base;
    }
  }

  static const _ThemePalette _lightPalette = _ThemePalette(
    background: Color(0xFFF5F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F4F9),
    border: Color(0xFFE6EBF2),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textMuted: Color(0xFF9CA3AF),
    focusGreen: Color(0xFF22C55E),
    focusStrongGreen: Color(0xFF16A34A),
    focusAmber: Color(0xFFEAB308),
    focusOrange: Color(0xFFF97316),
    dangerRed: Color(0xFFEF4444),
    warningOrange: Color(0xFFF59E0B),
    calmBlue: Color(0xFF0EA5E9),
  );

  static const _ThemePalette _darkPalette = _ThemePalette(
    background: Color(0xFF121316),
    surface: Color(0xFF1C1D21),
    surfaceMuted: Color(0xFF27292F),
    border: Color(0xFF353842),
    textPrimary: Color(0xFFF5F7FA),
    textSecondary: Color(0xFFC1C7D0),
    textMuted: Color(0xFF8E96A3),
    focusGreen: Color(0xFF34D399),
    focusStrongGreen: Color(0xFF10B981),
    focusAmber: Color(0xFFFBBF24),
    focusOrange: Color(0xFFFB923C),
    dangerRed: Color(0xFFF87171),
    warningOrange: Color(0xFFF59E0B),
    calmBlue: Color(0xFF38BDF8),
  );
}

class _ThemePalette {
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color focusGreen;
  final Color focusStrongGreen;
  final Color focusAmber;
  final Color focusOrange;
  final Color dangerRed;
  final Color warningOrange;
  final Color calmBlue;

  const _ThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.focusGreen,
    required this.focusStrongGreen,
    required this.focusAmber,
    required this.focusOrange,
    required this.dangerRed,
    required this.warningOrange,
    required this.calmBlue,
  });

  _ThemePalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? focusGreen,
    Color? focusStrongGreen,
    Color? focusAmber,
    Color? focusOrange,
    Color? dangerRed,
    Color? warningOrange,
    Color? calmBlue,
  }) {
    return _ThemePalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      focusGreen: focusGreen ?? this.focusGreen,
      focusStrongGreen: focusStrongGreen ?? this.focusStrongGreen,
      focusAmber: focusAmber ?? this.focusAmber,
      focusOrange: focusOrange ?? this.focusOrange,
      dangerRed: dangerRed ?? this.dangerRed,
      warningOrange: warningOrange ?? this.warningOrange,
      calmBlue: calmBlue ?? this.calmBlue,
    );
  }
}
