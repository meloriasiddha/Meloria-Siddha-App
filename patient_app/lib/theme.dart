import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Meloria patient app – elegant ivory, slate, sage and gold.
/// Change a colour here and the whole app follows.
class Brand {
  static const ink = Color(0xFF1F2A33);
  static const slate = Color(0xFF2C3A45);
  static const teal = Color(0xFF3C5761);
  static const sage = Color(0xFF88A99A);
  static const sageDark = Color(0xFF5E7F70);
  static const ivory = Color(0xFFF5F3EE);
  static const line = Color(0xFFE7E4DC);
  static const muted = Color(0xFF8A938F);
  static const gold = Color(0xFFB39462);
  static const goldLight = Color(0xFFF3ECDF);
  static const danger = Color(0xFFB4533F);
  static const warning = Color(0xFFC08A2E);
  static const deepTeal = Color(0xFF1F3B45);
  static const background = ivory;
}

/// Serif display text (as in "Siddha Hospital" in the logo).
TextStyle serif(double size, {FontWeight weight = FontWeight.w600, Color color = Brand.ink, double height = 1.1}) =>
    GoogleFonts.cormorantGaramond(fontSize: size, fontWeight: weight, color: color, height: height);

/// Small spaced capitals used for section labels.
TextStyle eyebrow({Color color = Brand.muted, double size = 10.5}) => GoogleFonts.montserrat(
    fontSize: size, fontWeight: FontWeight.w600, letterSpacing: 2.0, color: color);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.slate,
      primary: Brand.slate,
      secondary: Brand.sageDark,
      surface: Colors.white,
      error: Brand.danger,
    ),
    scaffoldBackgroundColor: Brand.ivory,
  );
  final text = base.textTheme.apply(
    fontFamily: GoogleFonts.montserrat().fontFamily,
    bodyColor: Brand.ink,
    displayColor: Brand.ink,
  );
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.ivory,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: serif(26),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: Brand.muted, letterSpacing: 0.4),
      floatingLabelStyle: const TextStyle(color: Brand.sageDark),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Brand.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Brand.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Brand.sageDark, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.slate,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600, letterSpacing: 1.6, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.slate,
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: Brand.line),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: Brand.slate,
      secondarySelectedColor: Brand.slate,
      labelStyle: const TextStyle(color: Brand.ink),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      side: const BorderSide(color: Brand.line),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Brand.goldLight,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Brand.slate : Brand.muted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? Brand.slate : Brand.muted)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Brand.slate : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : Brand.muted),
        side: const WidgetStatePropertyAll(BorderSide(color: Brand.line)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 14)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Brand.line, space: 1),
  );
}

/// Soft card shadow used across the app.
const softShadow = [
  BoxShadow(color: Color(0x0A1F2A33), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x101F2A33), blurRadius: 24, offset: Offset(0, 8)),
];

/// Appointment colours (same families as the staff calendar).
class ApptStyle {
  static const types = {
    'initial': 'Initial consultation',
    'review': 'Review',
    'therapy': 'Therapy',
    'procedure': 'Procedure',
    'program': 'Program visit',
  };
  static const modes = {'offline': 'In clinic', 'video': 'Video call', 'phone': 'Phone call'};
  static const statuses = {
    'booked': 'Confirmed',
    'pending_payment': 'Waiting for payment',
    'arrived': 'Checked in',
    'done': 'Completed',
    'no_show': 'Missed',
    'cancelled': 'Cancelled',
  };
  static IconData modeIcon(String m) => switch (m) {
        'video' => Icons.videocam_outlined,
        'phone' => Icons.call_outlined,
        _ => Icons.local_hospital_outlined,
      };
  static Color modeColor(String m) => switch (m) {
        'video' => Brand.teal,
        'phone' => Brand.sageDark,
        _ => Brand.slate,
      };
}
