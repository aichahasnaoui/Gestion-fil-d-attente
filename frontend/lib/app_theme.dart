import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary palette
  static const primary = Color(0xFF2D6BE4); // vibrant blue
  static const primaryLight = Color(0xFFEDF2FD);
  static const primaryDark = Color(0xFF1A4BAA);

  // Medical green
  static const medical = Color(0xFF1BA87A);
  static const medicalLight = Color(0xFFE4F7F0);

  // Queue orange
  static const queue = Color(0xFFF57C2B);
  static const queueLight = Color(0xFFFFF1E6);

  // Status
  static const success = Color(0xFF22C55E);
  static const successLight = Color(0xFFDCFCE7);
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);
  static const danger = Color(0xFFEF4444);
  static const dangerLight = Color(0xFFFEE2E2);
  static const info = Color(0xFF3B82F6);
  static const infoLight = Color(0xFFDBEAFE);

  // Neutrals
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF3F4F6);
  static const grey200 = Color(0xFFE5E7EB);
  static const grey400 = Color(0xFF9CA3AF);
  static const grey600 = Color(0xFF4B5563);
  static const grey800 = Color(0xFF1F2937);
  static const grey900 = Color(0xFF111827);

  static const background = Color(0xFFF5F7FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF0F4FF);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.soraTextTheme().copyWith(
        displayLarge: GoogleFonts.sora(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.grey900),
        displayMedium: GoogleFonts.sora(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.grey900),
        headlineLarge: GoogleFonts.sora(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.grey900),
        headlineMedium: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.grey900),
        titleLarge: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.grey900),
        titleMedium: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.grey800),
        bodyLarge: GoogleFonts.sora(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppColors.grey800),
        bodyMedium: GoogleFonts.sora(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.grey600),
        labelLarge: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.grey900),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.grey900),
        titleTextStyle: GoogleFonts.sora(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.grey900,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.grey200, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.grey50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.sora(color: AppColors.grey400, fontSize: 14),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.grey100, thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.grey400,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// ── Shared spacing / radius constants ────────────────────────
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class AppRadius {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(12);
  static const lg = Radius.circular(16);
  static const xl = Radius.circular(24);
  static const full = Radius.circular(999);
}
