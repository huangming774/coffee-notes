import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppAccentPalette {
  coffee,
  ocean,
  forest,
  violet,
  rose,
  sunset,
  amber,
  mint,
  teal,
  sky,
}

extension AppAccentPaletteX on AppAccentPalette {
  String get id {
    switch (this) {
      case AppAccentPalette.coffee:
        return 'coffee';
      case AppAccentPalette.ocean:
        return 'ocean';
      case AppAccentPalette.forest:
        return 'forest';
      case AppAccentPalette.violet:
        return 'violet';
      case AppAccentPalette.rose:
        return 'rose';
      case AppAccentPalette.sunset:
        return 'sunset';
      case AppAccentPalette.amber:
        return 'amber';
      case AppAccentPalette.mint:
        return 'mint';
      case AppAccentPalette.teal:
        return 'teal';
      case AppAccentPalette.sky:
        return 'sky';
    }
  }

  String get label {
    switch (this) {
      case AppAccentPalette.coffee:
        return '咖啡';
      case AppAccentPalette.ocean:
        return '海洋';
      case AppAccentPalette.forest:
        return '森林';
      case AppAccentPalette.violet:
        return '紫罗兰';
      case AppAccentPalette.rose:
        return '玫瑰';
      case AppAccentPalette.sunset:
        return '落日';
      case AppAccentPalette.amber:
        return '琥珀';
      case AppAccentPalette.mint:
        return '薄荷';
      case AppAccentPalette.teal:
        return '青绿';
      case AppAccentPalette.sky:
        return '晴空';
    }
  }

  Color get color {
    switch (this) {
      case AppAccentPalette.coffee:
        return const Color(0xFF8C6C42);
      case AppAccentPalette.ocean:
        return const Color(0xFF2B7BBE);
      case AppAccentPalette.forest:
        return const Color(0xFF2E8B57);
      case AppAccentPalette.violet:
        return const Color(0xFF7B61FF);
      case AppAccentPalette.rose:
        return const Color(0xFFE0567A);
      case AppAccentPalette.sunset:
        return const Color(0xFFFF7A45);
      case AppAccentPalette.amber:
        return const Color(0xFFF59E0B);
      case AppAccentPalette.mint:
        return const Color(0xFF2CC6A3);
      case AppAccentPalette.teal:
        return const Color(0xFF14B8A6);
      case AppAccentPalette.sky:
        return const Color(0xFF38BDF8);
    }
  }

  static AppAccentPalette fromId(String? id) {
    for (final palette in AppAccentPalette.values) {
      if (palette.id == id) return palette;
    }
    return AppAccentPalette.coffee;
  }
}

class AppAccentTheme extends ThemeExtension<AppAccentTheme> {
  const AppAccentTheme({required this.accent});

  final Color accent;

  @override
  AppAccentTheme copyWith({Color? accent}) {
    return AppAccentTheme(accent: accent ?? this.accent);
  }

  @override
  AppAccentTheme lerp(ThemeExtension<AppAccentTheme>? other, double t) {
    if (other is! AppAccentTheme) return this;
    return AppAccentTheme(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
    );
  }
}

class AppTheme {
  static const Color lightBackground = Color(0xFFF6F1EC);
  static const Color darkBackground = Color(0xFF1E1B17);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color darkCard = Color(0xFF2A2520);
  static const Color accent = Color(0xFF8C6C42);
  static const Color textPrimaryLight = Color(0xFF2B2B2B);
  static const Color textSecondaryLight = Color(0xFF9D958D);
  static const Color textPrimaryDark = Color(0xFFF3EEE9);
  static const Color textSecondaryDark = Color(0xFFB7AEA6);

  static Color accentOf(BuildContext context) {
    return Theme.of(context).extension<AppAccentTheme>()?.accent ?? accent;
  }

  static ThemeData lightTheme({Color? accentColor}) {
    final baseTextTheme = GoogleFonts.notoSansTextTheme();
    final resolvedAccent = accentColor ?? accent;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: ColorScheme.light(
        primary: resolvedAccent,
        surface: lightCard,
        onSurface: textPrimaryLight,
      ),
      extensions: [
        AppAccentTheme(accent: resolvedAccent),
      ],
      textTheme: baseTextTheme.copyWith(
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimaryLight,
          height: 1.1,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimaryLight,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textSecondaryLight,
        ),
      ),
    );
  }

  static ThemeData darkTheme({Color? accentColor}) {
    final baseTextTheme =
        GoogleFonts.notoSansTextTheme(ThemeData.dark().textTheme);
    final resolvedAccent = accentColor ?? accent;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.dark(
        primary: resolvedAccent,
        surface: darkCard,
        onSurface: textPrimaryDark,
      ),
      extensions: [
        AppAccentTheme(accent: resolvedAccent),
      ],
      textTheme: baseTextTheme.copyWith(
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimaryDark,
          height: 1.1,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimaryDark,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textSecondaryDark,
        ),
      ),
    );
  }
}
