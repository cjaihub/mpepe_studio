import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STUDIO v2 TOKENS — docs/live-studio/SPEC.md §1 (integrator-owned).
//
// The only place Live Studio colors live. Widgets read `LiveStudioTokens.of`
// (or the tokens passed down) and never use color literals. The studio blue
// #2F7BFF is scoped here by decision (SPEC §1.4); app-wide branding keeps
// AppColors.brandBlue.
//
// In-world surfaces (host screen, tiles, nameplates, table, pop-out body) are
// dark in BOTH themes — see [LiveStudioWorld].
// ─────────────────────────────────────────────────────────────────────────────

/// Theme-independent accents.
class LiveStudioAccent {
  LiveStudioAccent._();
  static const Color pink = Color(0xFFFF2D75);
  static const Color pinkHover = Color(0xFFFF4D8D);
  static const Color pinkLight = Color(0xFFFF6FA3);
  static const Color blue = Color(0xFF2F7BFF);
  static const Color blueHover = Color(0xFF4D8FFF);
  static const Color liveRed = Color(0xFFFF1744);
  static const Color cyan = Color(0xFF00F0FF);
  static const Color teal = Color(0xFF0FA3B1);
  static const Color muteIcon = Color(0xFFFF5A7A);
  static const Color inWindowIcon = Color(0xFF8FB6FF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color clear = Color(0x00000000);

  static Color pinkA(double a) => pink.withValues(alpha: a);
  static Color blueA(double a) => blue.withValues(alpha: a);
  static Color cyanA(double a) => cyan.withValues(alpha: a);
  static Color redA(double a) => liveRed.withValues(alpha: a);
}

/// In-world (always dark) surfaces.
class LiveStudioWorld {
  LiveStudioWorld._();
  static const Color screen = Color(0xFF0B0B0F);
  static const Color surface2 = Color(0xFF191920);
  static const Color surface3 = Color(0xFF23232C);
  static const Color textHigh = Color(0xFFFFFFFF);
  static const Color textMedium = Color(0xFFA3A3B2);
  static const Color textDim = Color(0xFF525263);
  static const Color nameplate = Color(0x9E0A0C14); // rgba(10,12,20,.62)
  static const Color nameplateBorder = Color(0x24FFFFFF); // .14
  static const Color inWindow = Color(0xC70A0C14); // rgba(10,12,20,.78)
  static const Color expandButton = Color(0xB808080A); // rgba(8,8,10,.72)
  static const Color tagPill = Color(0xBF08080A); // rgba(8,8,10,.75)
  static const Color watchingCta = Color(0xFF191920);
  static const Color popHeader = Color(0xF0111115); // rgba(17,17,21,.94)
  static const Color popIcon = Color(0xFFE5E1E6);
  static const Color avatarSkin = Color(0xFFFFF4EC);
  static const Color avatarInk = Color(0xFF1B1B24);
  static const Color avatarBlush = Color(0x99FF8FB1);
  static const Color hostSilhouetteHead = Color(0xFF3A3A48);
  static const Color hostSilhouetteBody = Color(0xFF2B2B36);

  /// Host screen background: radial(120% 90% at 50% 20%, #3a1830, #15121c 55%, #0b0b0f).
  static const RadialGradient hostBg = RadialGradient(
    center: Alignment(0, -0.6),
    radius: 1.2,
    colors: [Color(0xFF3A1830), Color(0xFF15121C), Color(0xFF0B0B0F)],
    stops: [0, 0.55, 1],
  );

  /// Tile background tint for a guest accent (prototype per-guest radial).
  static RadialGradient guestBg(Color accent) => RadialGradient(
        center: const Alignment(0, -0.7),
        radius: 1.2,
        colors: [Color.lerp(const Color(0xFF121218), accent, 0.22)!, const Color(0xFF121218), screen],
        stops: const [0, 0.6, 1],
      );

  /// Glass sheen: linear 118deg, white .16 → .04 @28% → 0 @42%.
  static const LinearGradient sheen = LinearGradient(
    begin: Alignment(-1, -0.53),
    end: Alignment(1, 0.53),
    colors: [Color(0x29FFFFFF), Color(0x0AFFFFFF), Color(0x00FFFFFF)],
    stops: [0, 0.28, 0.42],
  );

  static const Color pinkRim = Color(0xBFFF2D75); // rgba(255,45,117,.75)

  /// Guest tile rim + depth shadows (landscape; phone uses [tileShadowPhone]).
  static const List<BoxShadow> tileShadow = [
    BoxShadow(color: Color(0xD92F7BFF), spreadRadius: 1.5),
    BoxShadow(color: Color(0xBF000000), blurRadius: 26, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x592F7BFF), blurRadius: 16),
  ];
  static const List<BoxShadow> tileShadowPhone = [
    BoxShadow(color: Color(0xD92F7BFF), spreadRadius: 2),
    BoxShadow(color: Color(0xBF000000), blurRadius: 30, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x592F7BFF), blurRadius: 20),
  ];
  static const List<BoxShadow> tileHover = [
    BoxShadow(color: LiveStudioAccent.pink, spreadRadius: 2),
    BoxShadow(color: Color(0x99FF2D75), blurRadius: 22),
    BoxShadow(color: Color(0xBF000000), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const List<BoxShadow> tableShadow = [
    BoxShadow(color: Color(0xD92F7BFF), spreadRadius: 1.5),
    BoxShadow(color: Color(0xCC000000), blurRadius: 36, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x662F7BFF), blurRadius: 32),
  ];
  static const List<BoxShadow> popShadow = [
    BoxShadow(color: Color(0xD92F7BFF), spreadRadius: 1.5),
    BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24)),
  ];

  /// Wall layer drop shadows: (0 14 22 .75 black) + (0 0 16 pink .3).
  static const List<BoxShadow> wallLayer = [
    BoxShadow(color: Color(0xBF000000), blurRadius: 22, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x4DFF2D75), blurRadius: 16),
  ];
}

/// Chrome (UI layer) tokens per theme.
@immutable
class LiveStudioTokens {
  final StudioTheme theme;
  final Color base; // artboard + fades
  final Color glass; // capsules / groups
  final Color glassBorderLandscape;
  final Color glassBorderPhone;
  final double glassShadowAlpha;
  final Color ghostFill;
  final Color ghostBorder;
  final Color textHigh;
  final Color textMedium;
  final Color textDim;
  final Color placeholder;
  final Color ringOnGlass; // avatar/badge ring
  final Color commentBubble;
  final Color commentAvatar;
  final Color systemText;
  final Color shareToTableText;
  final Color modeIdleFill;
  final Color modeIdleBorder;
  final Color modeIdleText;
  final Color modeIdleIcon;
  final double activeFillAlpha;
  final Color followingFill;
  final Color followingBorder;
  final Color drawerTop;
  final Color drawerBottom;
  final Color drawerBorder;
  final Color focusRing;
  final Color standDisc;
  final double defaultDim;
  final List<String> frameColors;

  const LiveStudioTokens._({
    required this.theme,
    required this.base,
    required this.glass,
    required this.glassBorderLandscape,
    required this.glassBorderPhone,
    required this.glassShadowAlpha,
    required this.ghostFill,
    required this.ghostBorder,
    required this.textHigh,
    required this.textMedium,
    required this.textDim,
    required this.placeholder,
    required this.ringOnGlass,
    required this.commentBubble,
    required this.commentAvatar,
    required this.systemText,
    required this.shareToTableText,
    required this.modeIdleFill,
    required this.modeIdleBorder,
    required this.modeIdleText,
    required this.modeIdleIcon,
    required this.activeFillAlpha,
    required this.followingFill,
    required this.followingBorder,
    required this.drawerTop,
    required this.drawerBottom,
    required this.drawerBorder,
    required this.focusRing,
    required this.standDisc,
    required this.defaultDim,
    required this.frameColors,
  });

  static const LiveStudioTokens dark = LiveStudioTokens._(
    theme: StudioTheme.dark,
    base: Color(0xFF08080A),
    glass: Color(0xB8111115), // rgba(17,17,21,.72)
    glassBorderLandscape: Color(0x1AFFFFFF), // .10
    glassBorderPhone: Color(0x1FFFFFFF), // .12
    glassShadowAlpha: 0.35,
    ghostFill: Color(0x0FFFFFFF), // .06
    ghostBorder: Color(0x1AFFFFFF),
    textHigh: Color(0xFFFFFFFF),
    textMedium: Color(0xFFA3A3B2),
    textDim: Color(0xFF525263),
    placeholder: Color(0xFF6B6B7E),
    ringOnGlass: Color(0xFF111115),
    commentBubble: Color(0x8C0E1C40), // rgba(14,28,64,.55)
    commentAvatar: Color(0xFF16213F),
    systemText: Color(0xFFFFB0CA),
    shareToTableText: Color(0xFF8FB6FF),
    modeIdleFill: Color(0xD9122452), // rgba(18,36,82,.85)
    modeIdleBorder: Color(0x662F7BFF), // .4
    modeIdleText: Color(0xFFC9D8FF),
    modeIdleIcon: Color(0xFF8FB6FF),
    activeFillAlpha: 0.15,
    followingFill: Color(0x0FFFFFFF), // landscape .06 (phone .08)
    followingBorder: Color(0x1AFFFFFF),
    drawerTop: Color(0xFF13214A),
    drawerBottom: Color(0xFF111115),
    drawerBorder: Color(0x732F7BFF), // .45
    focusRing: Color(0xFF00F0FF),
    standDisc: Color(0xEB111115), // rgba(17,17,21,.92)
    defaultDim: 0.15,
    frameColors: ['#15151B', '#2A3550', '#2F7BFF', '#FF2D75'],
  );

  static const LiveStudioTokens light = LiveStudioTokens._(
    theme: StudioTheme.light,
    base: Color(0xFFD3DAE6),
    glass: Color(0xD1E8EDF6), // rgba(232,237,246,.82)
    glassBorderLandscape: Color(0x1A141E3C), // rgba(20,30,60,.10)
    glassBorderPhone: Color(0x1F141E3C), // .12
    glassShadowAlpha: 0.12,
    ghostFill: Color(0x0F141E3C),
    ghostBorder: Color(0x1A141E3C),
    textHigh: Color(0xFF14141A),
    textMedium: Color(0xFF5A6072),
    textDim: Color(0xFFC3C9D6),
    placeholder: Color(0xFF7A8194),
    ringOnGlass: Color(0xFFE8EDF6),
    commentBubble: Color(0xCCE8EDF6), // rgba(232,237,246,.8)
    commentAvatar: Color(0xFFCBD5E6),
    systemText: Color(0xFFD61F5C),
    shareToTableText: Color(0xFF1F4FB8),
    modeIdleFill: Color(0x142F7BFF), // rgba(47,123,255,.08)
    modeIdleBorder: Color(0x592F7BFF), // .35
    modeIdleText: Color(0xFF1F4FB8),
    modeIdleIcon: Color(0xFF2F7BFF),
    activeFillAlpha: 0.12,
    followingFill: Color(0x0F141E3C), // rgba(20,30,60,.06)
    followingBorder: Color(0x1F141E3C),
    drawerTop: Color(0xFFC9D6EE),
    drawerBottom: Color(0xFFDDE3EC),
    drawerBorder: Color(0x732F7BFF),
    focusRing: Color(0xFF2F7BFF),
    standDisc: Color(0xCCE4E9F2), // rgba(228,233,242,.8)
    defaultDim: 0,
    frameColors: ['#3B4763', '#8C97AE', '#2F7BFF', '#FF2D75'],
  );

  static LiveStudioTokens forTheme(StudioTheme t) => t == StudioTheme.light ? light : dark;

  Color get activeFill => LiveStudioAccent.pinkA(activeFillAlpha);
  Color glassShadow() => Color.fromRGBO(0, 0, 0, glassShadowAlpha);

  /// Studio dim tint over the photo: rgba(8,8,10,dim) in both themes.
  static Color dimTint(double dim) => Color.fromRGBO(8, 8, 10, dim);

  /// Glass blur sigma for capsules (CSS blur(20px) ≈ sigma 10).
  static const double glassBlurSigma = 10;
  static const double railBlurSigma = 8;
}

/// Parses "#RRGGBB" settings colors (frame color) into a [Color].
Color studioHex(String hex, {Color fallback = const Color(0xFF15151B)}) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Typography: the system font stack (no fontFamily → SF on iOS, Roboto on
/// Android), per SPEC §1.3. Numbers use tabular figures.
class LiveStudioType {
  LiveStudioType._();
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle s(double size, FontWeight w, Color c, {double? height, double letter = 0}) =>
      TextStyle(
        fontSize: size,
        fontWeight: w,
        color: c,
        height: height == null ? null : height / size,
        letterSpacing: letter * size,
        fontFeatures: tabular,
      );
}

/// Motion (SPEC §1.3). Transform/opacity only.
class LiveStudioMotion {
  LiveStudioMotion._();
  static const Duration pulse = Duration(milliseconds: 1400);
  static const Duration rise = Duration(milliseconds: 450);
  static const Curve riseCurve = Cubic(0.2, 0.8, 0.2, 1);
  static const Duration heartFloat = Duration(milliseconds: 3200);
  static const Duration eq = Duration(milliseconds: 900);
  static const Duration eqStagger = Duration(milliseconds: 250);
  static const Duration drawerUp = Duration(milliseconds: 320);
  static const Duration press = Duration(milliseconds: 100);
  static const double pressScale = 0.98;
  static const Duration hover = Duration(milliseconds: 200);
}
