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
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Brand.slate : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : Brand.slate),
        side: const WidgetStatePropertyAll(BorderSide(color: Brand.line)),
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

/// Appointment colours: type = colour family, mode = shade.
/// In clinic (offline) = solid dark shade, online (video / phone) = light shade.
class ApptStyle {
  static const types = <String, String>{
    'initial': 'Initial consultation',
    'review': 'Review',
    'therapy': 'Therapy',
    'procedure': 'External procedure',
    'program': 'Program visit',
  };
  static const shortTypes = <String, String>{
    'initial': 'Initial',
    'review': 'Review',
    'therapy': 'Therapy',
    'procedure': 'Procedure',
    'program': 'Program',
  };
  static const modes = <String, String>{
    'offline': 'In clinic',
    'video': 'Video call',
    'phone': 'Phone call',
  };

  static const _solid = <String, Color>{
    'initial': Color(0xFF2C3A45),
    'review': Color(0xFF4F7564),
    'therapy': Color(0xFFB0693E),
    'procedure': Color(0xFF6E5A80),
    'program': Color(0xFF2F7480),
  };
  static const _light = <String, Color>{
    'initial': Color(0xFF9AA9B4),
    'review': Color(0xFFB9D1C4),
    'therapy': Color(0xFFE8C3A6),
    'procedure': Color(0xFFCBBFD8),
    'program': Color(0xFFA8D2D9),
  };

  static Color solid(String type) => _solid[type] ?? Brand.slate;

  static Color background(String type, String mode) =>
      mode == 'offline' ? solid(type) : (_light[type] ?? Brand.line);

  static Color foreground(String mode) => mode == 'offline' ? Colors.white : Brand.slate;

  static IconData modeIcon(String mode) => switch (mode) {
        'video' => Icons.videocam_outlined,
        'phone' => Icons.call_outlined,
        _ => Icons.local_hospital_outlined,
      };

  /// Default length in minutes for each type.
  static int defaultMinutes(String type) => switch (type) {
        'initial' => 20,
        'review' => 10,
        'therapy' => 30,
        'procedure' => 30,
        _ => 15,
      };

  static const statuses = <String, String>{
    'booked': 'Booked',
    'pending_payment': 'Waiting for payment',
    'arrived': 'Arrived',
    'done': 'Done',
    'no_show': 'No-show',
    'cancelled': 'Cancelled',
  };
}
