import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Meloria brand colours (taken from the clinic logo).
/// Change a value here and the whole app updates.
class Brand {
  static const slate = Color(0xFF2C3A45); // primary – deep slate
  static const teal = Color(0xFF3C5761); // secondary – slate teal
  static const sage = Color(0xFF88A99A); // accent – sage green
  static const sageDark = Color(0xFF678778); // accent dark
  static const background = Color(0xFFF7F8F6); // soft white
  static const surface = Colors.white;
  static const muted = Color(0xFF7A8A92);
  static const danger = Color(0xFFB4533F);
  static const warning = Color(0xFFC08A2E);
  static const line = Color(0xFFE4E8E5);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.slate,
      primary: Brand.slate,
      secondary: Brand.sageDark,
      tertiary: Brand.sage,
      surface: Brand.surface,
      error: Brand.danger,
    ),
    scaffoldBackgroundColor: Brand.background,
  );

  final text = base.textTheme.apply(
    fontFamily: GoogleFonts.montserrat().fontFamily,
    bodyColor: Brand.slate,
    displayColor: Brand.slate,
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.background,
      foregroundColor: Brand.slate,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.montserrat(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Brand.slate,
        letterSpacing: 0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.sageDark, width: 1.6),
      ),
      labelStyle: const TextStyle(color: Brand.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.slate,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.slate,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Brand.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: Brand.sage.withValues(alpha: 0.25),
      side: const BorderSide(color: Brand.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Brand.sage.withValues(alpha: 0.3),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w500, color: Brand.slate),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.slate,
      foregroundColor: Colors.white,
    ),
    dividerTheme: const DividerThemeData(color: Brand.line, space: 1),
  );
}

/// Serif style used for "Siddha Hospital" under the MELORIA wordmark.
TextStyle serifStyle({double size = 16, Color color = Brand.slate}) =>
    GoogleFonts.cormorantGaramond(fontSize: size, fontWeight: FontWeight.w600, color: color);
