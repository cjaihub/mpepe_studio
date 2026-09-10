import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Premium Dark Mode Colors (Studio Aesthetic)
  static const Color darkBackground = Color(0xFF0A0A0A); // True deep black
  static const Color darkSurface = Color(0xFF141414); // Elevated dark surface
  static const Color darkSurfaceHighlight = Color(0xFF1F1F1F);
  
  // Text Colors
  static const Color textPrimary = Color(0xFFF3F4F6); // Soft white
  static const Color textSecondary = Color(0xFF9CA3AF); // Subdued gray
  static const Color textMuted = Color(0xFF4B5563);
  
  // Brand Colors
  static const Color mpepeMaroon = Color(0xFF990000); // Brand core (Classic Dark Red)
  static const Color mpepeGold = Color(0xFF990000); // Changed to match
  static const Color mpepeBrown = Color(0xFF990000); // Changed to match
  
  // Legacy Aliases mapped to brand colors to prevent UI breaks
  static const Color neonPurple = mpepeMaroon; 
  static const Color neonPink = mpepeMaroon;
  static const Color neonBlue = mpepeMaroon;
  static const Color neonGreen = Color(0xFF00FF66); // Kept for success metrics/stats
  
  static const Color outline = Color(0xFF262626); // Subtle borders
  
  // Card UI aliases
  static const Color cardDark = darkSurface;
  static const Color cardBorder = outline;
  
  // Solid Colors (Gradients removed as requested)
  static const LinearGradient aiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mpepeMaroon, mpepeMaroon],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mpepeMaroon, mpepeMaroon],
  );
}

class AppTheme {
  // Reusable text styles with GoogleFonts.inter for a modern, geometric look
  static TextStyle get h1Style => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
  );

  static TextStyle get h2Style => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.3,
  );

  static TextStyle get h3Style => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );

  static TextStyle get bodyStyle => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700, // Enhanced bold body text
  );

  // Premium Dark Theme - Default for the App
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.mpepeMaroon,
        secondary: AppColors.mpepeGold,
        surface: AppColors.darkSurface,
        onSurface: AppColors.textPrimary,
        outline: AppColors.outline,
        error: Colors.redAccent,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ).copyWith(
        bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900, // enhanced bold
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.outline, width: 2.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.mpepeMaroon,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
    );
  }

  // Light Theme (Optional fallback, but the app is heavily dark-mode tailored)
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: const Color(0xFFF9FAFB),
      colorScheme: const ColorScheme.light(
        primary: AppColors.mpepeMaroon,
        secondary: AppColors.mpepeGold,
        surface: Colors.white,
        onSurface: Color(0xFF111827),
        outline: Color(0xFFE5E7EB),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
    );
  }
}
