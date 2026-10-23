import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../design_system/oneova_touch_feedback.dart';

class AppColors {
  // Premium Dark Mode Colors (Studio Aesthetic)
  static const Color darkBackground = Color(0xFF0A0A0A); // True deep black
  static const Color darkSurface = Color(0xFF141414); // Elevated dark surface
  static const Color darkSurfaceHighlight = Color(0xFF1F1F1F);
  
  // Premium Light Mode Colors (Clean Corporate Luxury)
  static const Color lightBackground = Color(0xFFFFFFFF); // Crisp clean white
  static const Color lightSurface = Color(0xFFF8FAFC); // Soft elevated slate white
  static const Color lightSurfaceHighlight = Color(0xFFF1F5F9); // Light pill/accent container
  static const Color lightBorder = Color(0xFFE2E8F0); // Crisp light hairline outline

  // Text Colors - Dark Mode
  static const Color textPrimary = Color(0xFFF3F4F6); // Soft white
  static const Color textSecondary = Color(0xFF9CA3AF); // Subdued gray
  static const Color textMuted = Color(0xFF6B7280); // Muted gray

  // Text Colors - Light Mode
  static const Color lightTextPrimary = Color(0xFF0F172A); // Deep slate high-contrast
  static const Color lightTextSecondary = Color(0xFF475569); // Slate secondary
  static const Color lightTextMuted = Color(0xFF94A3B8); // Slate muted

  // Rebranding to Oneova (Deep Facebook Blue)
  static const Color brandBlue = Color(0xFF0C4FA8); // PRIMARY brand color (Deep Facebook Blue)
  static const Color brandPink = Color(0xFFFF2D87); // SECONDARY accent (badges, highlights, remix, live)
  static const Color brandWhite = Color(0xFFFFFFFF);
  static const Color brandBlack = Color(0xFF000000);

  // Legacy Aliases mapped to brand colors to prevent UI breaks
  static const Color neonPurple = brandBlue; 
  static const Color neonPink = brandPink;
  static const Color neonBlue = brandBlue;
  static const Color neonGreen = brandBlue; // Metrics mapped strictly to brandBlue
  static const Color oneovaGold = brandPink; // Pro effects mapped strictly to brandPink
  static const Color onerovaGold = brandPink; // Legacy alias mapped to brandPink
  
  static const Color outline = Color(0xFF262626); // Subtle borders in dark mode

  // Theme-aware helpers (dark = studio aesthetic, light = clean white)
  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static bool _dark(BuildContext c) => isDark(c);
  static Color background(BuildContext c) => _dark(c) ? darkBackground : lightBackground;
  static Color surface(BuildContext c) => _dark(c) ? darkSurface : lightSurface;
  static Color surfaceMid(BuildContext c) => _dark(c) ? darkSurfaceHighlight : lightSurfaceHighlight;
  static Color border(BuildContext c) => _dark(c) ? outline : lightBorder;
  static Color textPrimaryOf(BuildContext c) => _dark(c) ? textPrimary : lightTextPrimary;
  static Color textSecondaryOf(BuildContext c) => _dark(c) ? textSecondary : lightTextSecondary;
  static Color textMutedOf(BuildContext c) => _dark(c) ? textMuted : lightTextMuted;
  static Color topBarBackground(BuildContext c) => brandBlue;
  static Color topBarForeground(BuildContext c) => _dark(c) ? Colors.white : brandPink;
  
  // Card UI aliases
  static const Color cardDark = darkSurface;
  static const Color cardBorder = outline;
  
  // Brand Gradients (Strictly Blue & Pink)
  static const LinearGradient aiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlue, brandPink],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlue, brandPink],
  );
}

/// Compact design radii for modern high-density luxury interfaces
class AppRadius {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double full = 999.0;
}

/// Refined corporate typography scale (compact, elegant, high legibility)
class AppTypography {
  static TextStyle title1(Color color) => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.4,
      );

  static TextStyle title2(Color color) => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.3,
      );

  static TextStyle title3(Color color) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.2,
      );

  static TextStyle pageTitle(Color color) => GoogleFonts.inter(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.3,
      );

  static TextStyle sectionTitle(Color color) => GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.1,
      );

  static TextStyle callout(Color color) => GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.1,
      );

  static TextStyle sub(Color color) => GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle body(Color color) => GoogleFonts.inter(
        fontSize: 13.0,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.35,
      );

  static TextStyle bodyMedium(Color color) => GoogleFonts.inter(
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.35,
      );

  static TextStyle small(Color color) => GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle caption(Color color) => GoogleFonts.inter(
        fontSize: 11.0,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle micro(Color color) => GoogleFonts.inter(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.8,
      );

  static TextStyle navigation(Color color) => GoogleFonts.inter(
        fontSize: 11.0,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle applicationTitle(Color color) => GoogleFonts.inter(
        fontSize: 14.0,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 1.0,
      );

  static TextStyle metric(Color color) => GoogleFonts.inter(
        fontSize: 20.0,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: -0.5,
      );
}

/// Crisp, subtle shadows calibrated for light and dark modes
class AppShadows {
  static List<BoxShadow> get brand => [
        BoxShadow(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ];

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get ambient => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> glow(Color color, {double radius = 12, double spread = 1}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: radius,
          spreadRadius: spread,
        ),
      ];
}

/// Universal decorated containers adhering to global Light/Dark mode
class AppDecorations {
  static BoxDecoration groupedSection(BuildContext context, {double radius = AppRadius.lg}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? AppColors.outline : AppColors.lightBorder,
        width: 1.0,
      ),
    );
  }

  static BoxDecoration card(BuildContext context, {double radius = AppRadius.md, bool border = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(radius),
      border: border
          ? Border.all(
              color: isDark ? AppColors.outline : AppColors.lightBorder,
              width: 1.0,
            )
          : null,
    );
  }
}

/// BuildContext extension for effortless, universal access to theme tokens
extension OneovaThemeExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  Color get bg => AppColors.background(this);
  Color get surface => AppColors.surface(this);
  Color get surfaceMid => AppColors.surfaceMid(this);
  Color get border => AppColors.border(this);
  Color get textPrimary => AppColors.textPrimaryOf(this);
  Color get textSecondary => AppColors.textSecondaryOf(this);
  Color get textMuted => AppColors.textMutedOf(this);
  Color get brandBlue => AppColors.brandBlue;
  Color get brandPink => AppColors.brandPink;
  Color get topBarBg => AppColors.brandBlue;
  // Top bars always sit on solid brand blue, so the foreground stays white in
  // both modes for legibility (pink-on-blue failed contrast in light mode).
  Color get topBarFg => Colors.white;
}

class AppTheme {
  // Instagram/Linear style compact, breathable typography using GoogleFonts.inter
  static TextStyle get h1Style => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        height: 1.25,
      );

  static TextStyle get h2Style => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle get h3Style => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.35,
      );

  static TextStyle get bodyStyle => GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.4,
      );

  static TextStyle get captionStyle => GoogleFonts.inter(
        fontSize: 11.0,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.3,
        color: AppColors.textSecondary,
      );

  // Premium Dark Theme - Calibrated compact scale
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandBlue,
        secondary: AppColors.brandPink,
        surface: AppColors.darkSurface,
        onSurface: AppColors.textPrimary,
        outline: AppColors.outline,
        error: AppColors.brandPink,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ).copyWith(
        displayLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 26, color: AppColors.textPrimary, letterSpacing: -0.5),
        headlineLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 21, color: AppColors.textPrimary, letterSpacing: -0.4),
        headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary, letterSpacing: -0.3),
        titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.textPrimary, letterSpacing: -0.2),
        titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
        titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
        bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13.5, color: AppColors.textPrimary, height: 1.35),
        bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 12.5, color: AppColors.textPrimary, height: 1.35),
        bodySmall: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 11.0, color: AppColors.textSecondary),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.textPrimary),
        labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11.0, color: AppColors.textSecondary),
        labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 9.5, color: AppColors.textSecondary, letterSpacing: 0.8),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 50,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 20),
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 16.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.outline, width: 1.0),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.darkSurfaceHighlight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.outline, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.outline, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.0, letterSpacing: -0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, 38),
          side: const BorderSide(color: AppColors.outline, width: 1.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.0),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1.0,
        space: 1.0,
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        horizontalTitleGap: 10,
        minLeadingWidth: 20,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      splashFactory: const OneovaGlowSplashFactory(),
      splashColor: AppColors.brandBlue.withValues(alpha: 0.12),
      highlightColor: AppColors.brandPink.withValues(alpha: 0.06),
      hoverColor: AppColors.brandBlue.withValues(alpha: 0.04),
      focusColor: AppColors.brandBlue.withValues(alpha: 0.08),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.windows: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.linux: OneovaSmoothPageTransitionsBuilder(),
        },
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.brandBlue, width: 2.2),
          borderRadius: BorderRadius.all(Radius.circular(2.0)),
        ),
        dividerColor: Colors.transparent,
      ),
    );
  }

  // Premium Light Theme (Clean, breathable high-contrast modern UI)
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandBlue,
        secondary: AppColors.brandPink,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightTextPrimary,
        outline: AppColors.lightBorder,
        error: AppColors.brandPink,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: AppColors.lightTextPrimary,
        displayColor: AppColors.lightTextPrimary,
      ).copyWith(
        displayLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 26, color: AppColors.lightTextPrimary, letterSpacing: -0.5),
        headlineLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 21, color: AppColors.lightTextPrimary, letterSpacing: -0.4),
        headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.lightTextPrimary, letterSpacing: -0.3),
        titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.lightTextPrimary, letterSpacing: -0.2),
        titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.lightTextPrimary),
        titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.lightTextPrimary),
        bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13.5, color: AppColors.lightTextPrimary, height: 1.35),
        bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 12.5, color: AppColors.lightTextSecondary, height: 1.35),
        bodySmall: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 11.0, color: AppColors.lightTextMuted),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.lightTextPrimary),
        labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11.0, color: AppColors.lightTextSecondary),
        labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 9.5, color: AppColors.lightTextMuted, letterSpacing: 0.8),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: AppColors.brandPink,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 50,
        iconTheme: const IconThemeData(color: AppColors.brandPink, size: 20),
        actionsIconTheme: const IconThemeData(color: AppColors.brandPink, size: 20),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.brandPink,
          fontSize: 16.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.lightSurfaceHighlight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: GoogleFonts.inter(color: AppColors.lightTextMuted, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.0, letterSpacing: -0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightTextPrimary,
          minimumSize: const Size(0, 38),
          side: const BorderSide(color: AppColors.lightBorder, width: 1.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.0),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1.0,
        space: 1.0,
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        horizontalTitleGap: 10,
        minLeadingWidth: 20,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      splashFactory: const OneovaGlowSplashFactory(),
      splashColor: AppColors.brandBlue.withValues(alpha: 0.12),
      highlightColor: AppColors.brandPink.withValues(alpha: 0.06),
      hoverColor: AppColors.brandBlue.withValues(alpha: 0.04),
      focusColor: AppColors.brandBlue.withValues(alpha: 0.08),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.iOS: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.macOS: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.windows: OneovaSmoothPageTransitionsBuilder(),
          TargetPlatform.linux: OneovaSmoothPageTransitionsBuilder(),
        },
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.brandBlue,
        unselectedLabelColor: AppColors.lightTextSecondary,
        labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.brandBlue, width: 2.2),
          borderRadius: BorderRadius.all(Radius.circular(2.0)),
        ),
        dividerColor: Colors.transparent,
      ),
    );
  }
}
