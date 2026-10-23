import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Obsidian Telemetry" design tokens (DESIGN.md), scoped to the Live Studio.
///
/// The global Oneova theme (`AppColors`) is unchanged. These tokens exist so
/// the studio can follow DESIGN.md exactly without leaking its palette into
/// the rest of the app. Do not add colors here that are not in DESIGN.md.
class OTColors {
  OTColors._();

  // Surfaces
  static const Color obsidianBase = Color(0xFF08080A);
  static const Color surface1 = Color(0xFF111115);
  static const Color surface2 = Color(0xFF191920);
  static const Color surface3 = Color(0xFF23232C);
  static const Color inputWell = Color(0xFF0E0E12);

  // Accents
  static const Color neonPink = Color(0xFFFF2D75);
  static const Color neonPinkHover = Color(0xFFFF4D8D);
  static const Color telemetryCyan = Color(0xFF00F0FF);
  static const Color liveCrimson = Color(0xFFFF1744);

  // Text hierarchy
  static const Color textHigh = Color(0xFFFFFFFF);
  static const Color textMedium = Color(0xFFA3A3B2);
  static const Color textMuted = Color(0xFF525263);

  // Alpha variants used by DESIGN.md / the studio brief
  static const Color pinkGlow35 = Color(0x59FF2D75); // rgba(255,45,117,.35)
  static const Color pinkGlow45 = Color(0x73FF2D75); // rgba(255,45,117,.45)
  static const Color pinkStroke55 = Color(0x8CFF2D75); // rgba(255,45,117,.55)
  static const Color pinkBorder30 = Color(0x4DFF2D75); // rgba(255,45,117,.30)
  static const Color pinkFocus20 = Color(0x33FF2D75); // rgba(255,45,117,.20)
  static const Color pinkTint15 = Color(0x26FF2D75); // rgba(255,45,117,.15)
  static const Color pinkHover08 = Color(0x14FF2D75); // rgba(255,45,117,.08)
  static const Color glass85 = Color(0xD9111115); // rgba(17,17,21,.85)
  static const Color namePill72 = Color(0xB808080A); // rgba(8,8,10,.72)
  static const Color hairline08 = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const Color hairline10 = Color(0x1AFFFFFF); // rgba(255,255,255,.10)
  static const Color hairline12 = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const Color hairline16 = Color(0x29FFFFFF); // rgba(255,255,255,.16)
}

class OTRadius {
  OTRadius._();
  static const double sm = 4; // 0.25rem
  static const double base = 8; // 0.5rem
  static const double md = 12; // 0.75rem
  static const double lg = 16; // 1rem
  static const double xl = 24; // 1.5rem
  static const double full = 9999;
}

class OTSpace {
  OTSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double xl = 32;
  static const double gutter = 12;
  static const double gutterDesktop = 16;
  static const double margin = 16;
  static const double marginDesktop = 24;
}

class OTShadows {
  OTShadows._();

  /// Active speaker glow from the studio brief.
  static const List<BoxShadow> activeSpeaker = [
    BoxShadow(color: OTColors.pinkGlow45, blurRadius: 18),
  ];

  /// DESIGN.md "Luminous Bloom".
  static const List<BoxShadow> bloom = [
    BoxShadow(color: OTColors.pinkGlow35, blurRadius: 20),
  ];
}

/// DESIGN.md type scale. All numeric styles use tabular figures.
class OTType {
  OTType._();

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle headlineMd({Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: 20, fontWeight: FontWeight.w600, height: 28 / 20, color: color);

  static TextStyle headlineSm({Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: 16, fontWeight: FontWeight.w600, height: 24 / 16, color: color);

  static TextStyle displayName({double size = 22, Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: size, fontWeight: FontWeight.w700, height: 1.2, color: color);

  static TextStyle labelMd({Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 16 / 12,
          letterSpacing: 12 * 0.04,
          color: color,
          fontFeatures: _tabular);

  static TextStyle labelSm({Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 14 / 10,
          letterSpacing: 10 * 0.06,
          color: color,
          fontFeatures: _tabular);

  static TextStyle bodyMd({Color color = OTColors.textHigh}) =>
      GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14, color: color);

  static TextStyle bodySm({Color color = OTColors.textMedium}) =>
      GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, color: color);

  static TextStyle chat({Color color = OTColors.textHigh, FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: 13, fontWeight: weight, height: 18 / 13, color: color);

  /// Space Grotesk 600 label sized freely (used for in-world name pills).
  static TextStyle pill(double size, {Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: color,
          fontFeatures: _tabular);

  static TextStyle metricMd({Color color = OTColors.textHigh}) =>
      GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 28 / 24,
          color: color,
          fontFeatures: _tabular);
}
