// LIVE SETUP WIZARD — compact studio stage mock-ups & live camera preview.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../looks/live/live_look_presets.dart';
import '../../../shared/theme/app_theme.dart';
import 'live_setup_config.dart';

Color _parseHexColor(String hex, {Color fallback = AppColors.brandBlue}) {
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length == 6) {
    final v = int.tryParse('FF$clean', radix: 16);
    if (v != null) return Color(v);
  }
  return fallback;
}

/// A compact rounded phone-shaped frame (9:16) holding a preview.
class SetupPhoneFrame extends StatelessWidget {
  const SetupPhoneFrame({super.key, required this.child, this.height = 188, this.dark = true});
  final Widget child;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: height,
        width: height * 9 / 16,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.brandBlack,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: dark ? AppColors.darkBackground : AppColors.lightSurface,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pink "LIVE" badge.
class SetupLiveBadge extends StatelessWidget {
  const SetupLiveBadge({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 1.5 : 3),
        decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(4)),
        child: Text('LIVE',
            style: GoogleFonts.inter(fontSize: small ? 7.5 : 9.5, fontWeight: FontWeight.w900, color: AppColors.brandWhite)),
      );
}

/// Person silhouette inside a tile.
class _Silhouette extends StatelessWidget {
  const _Silhouette({this.host = false, this.dim = false});
  final bool host;
  final bool dim;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final s = c.biggest.shortestSide;
        final color = (host ? AppColors.brandBlue : AppColors.textMuted).withValues(alpha: dim ? 0.35 : 0.9);
        return Center(child: Icon(Icons.person_rounded, size: s * 0.65, color: color));
      });
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.ring, this.light = false, this.label, this.borderWidth = 1.5});
  final Widget child;
  final Color? ring;
  final bool light;
  final String? label;
  final double borderWidth;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: light ? AppColors.lightSurfaceHighlight : AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: ring ?? (light ? AppColors.lightBorder : AppColors.outline),
            width: ring == null ? 1 : borderWidth,
          ),
        ),
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
          if (label != null)
            Positioned(
              left: 3,
              bottom: 3,
              right: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.brandBlack.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 6, fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
              ),
            ),
        ]),
      );
}

/// Skeleton lines where comments will appear.
class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton({this.lines = 2, this.light = false});
  final int lines;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final c = (light ? AppColors.lightTextMuted : AppColors.textMuted).withValues(alpha: 0.45);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < lines; i++)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
              width: 30.0 + (i * 18 % 30),
              height: 5.5,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
            ),
          ]),
        ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label, {this.color = AppColors.brandBlue});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.5),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 8.5, color: AppColors.brandWhite),
          const SizedBox(width: 3),
          Text(label, style: GoogleFonts.inter(fontSize: 7, fontWeight: FontWeight.w800, color: AppColors.brandWhite)),
        ]),
      );
}

/// The unified on-air Studio Stage mock: curved studio environment, floor glow,
/// center host screen, guest walls (in both Solo Studio and Multi-Guest Studio),
/// and interactive studio table.
class SetupStudioMock extends StatelessWidget {
  const SetupStudioMock({super.key, required this.config, this.showChrome = true, this.highlightRequests = false});
  final LiveSetupConfig config;
  final bool showChrome;
  final bool highlightRequests;

  @override
  Widget build(BuildContext context) {
    final light = config.settings.theme == StudioTheme.light;
    final names = config.settings.showNames;
    final pinned = config.settings.speakerMode == SpeakerMode.hostPinned;
    final frameAccent = _parseHexColor(config.settings.frameColor);
    final dimAlpha = config.settings.studioDim.clamp(0.0, 0.6);
    final guestScale = switch (config.settings.guestSize) {
      GuestSize.s => 0.21,
      GuestSize.m => 0.26,
      GuestSize.l => 0.30,
    };

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final children = <Widget>[];

      if (config.mode == LiveSetupMode.game) {
        children.add(Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandBlue, AppColors.darkBackground],
              ),
            ),
            child: Center(
              child: Icon(Icons.sports_esports_rounded, size: w * 0.32, color: AppColors.brandWhite.withValues(alpha: 0.85)),
            ),
          ),
        ));
        children.add(Positioned(
          right: 7,
          top: h * 0.16,
          width: w * 0.28,
          height: w * 0.28,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkSurfaceHighlight,
              border: Border.all(color: AppColors.brandPink, width: 2),
            ),
            child: const _Silhouette(host: true),
          ),
        ));
      } else {
        // Unified 3D Broadcast Studio Stage for BOTH Solo Studio & Multi-Guest Studio
        final isSolo = config.mode == LiveSetupMode.solo;
        final tile = w * (isSolo ? 0.20 : guestScale);
        final centerW = w - tile * 2 - 14;
        final centerH = h * (isSolo ? 0.44 : 0.40);
        final top = h * 0.14;

        // 1. Curved studio wall environment + dim layer
        children.add(Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.25),
                radius: 0.95,
                colors: light
                    ? [
                        AppColors.brandBlue.withValues(alpha: 0.14),
                        AppColors.lightSurface,
                        AppColors.lightSurfaceHighlight,
                      ]
                    : [
                        AppColors.brandBlue.withValues(alpha: 0.28),
                        const Color(0xFF0E1422),
                        AppColors.darkBackground,
                      ],
              ),
            ),
          ),
        ));
        if (dimAlpha > 0) {
          children.add(Positioned.fill(
            child: ColoredBox(color: AppColors.brandBlack.withValues(alpha: dimAlpha * 0.65)),
          ));
        }

        // 2. Studio Stage Floor Glow under center screen
        children.add(Positioned(
          left: w * 0.15,
          right: w * 0.15,
          top: top + centerH - 4,
          height: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: frameAccent.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.28),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        ));

        // 3. Host Center Broadcast Screen
        children.add(Positioned(
          left: tile + 7,
          top: top,
          width: centerW,
          height: centerH,
          child: _Tile(
            light: light,
            ring: frameAccent,
            borderWidth: 2,
            label: names ? (isSolo ? 'You · Studio Stage' : 'You · Host') : null,
            child: const _Silhouette(host: true),
          ),
        ));

        // 4. Studio Side Wall Panels (active guests in Multi-Guest, or sleek studio stage wing slots in Solo)
        for (var i = 0; i < 4; i++) {
          final left = i.isEven;
          final row = i ~/ 2;
          final speaking = !isSolo && !pinned && i == 1;
          children.add(Positioned(
            left: left ? 3.5 : null,
            right: left ? null : 3.5,
            top: top + row * (tile + 5),
            width: tile,
            height: tile,
            child: _Tile(
              light: light,
              ring: speaking ? AppColors.brandPink : (isSolo ? frameAccent.withValues(alpha: 0.35) : null),
              label: names ? (isSolo ? (i == 0 ? 'Seat' : null) : 'G${i + 1}') : null,
              child: isSolo ? const _Silhouette(dim: true) : _Silhouette(dim: i > 1),
            ),
          ));
        }

        // 5. Interactive Studio Table at the base of the stage
        children.add(Positioned(
          left: w * 0.20,
          right: w * 0.20,
          bottom: h * 0.22,
          height: h * 0.11,
          child: Container(
            decoration: BoxDecoration(
              color: (light ? AppColors.lightSurfaceHighlight : const Color(0xFF151C2C)).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: frameAccent.withValues(alpha: 0.65), width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_restaurant_rounded, size: 9, color: frameAccent),
                const SizedBox(width: 3),
                Text(
                  'STUDIO TABLE',
                  style: GoogleFonts.inter(
                    fontSize: 5.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: light ? AppColors.lightTextSecondary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ));
      }

      if (showChrome) {
        children.add(const Positioned(left: 7, top: 8, child: SetupLiveBadge(small: true)));
        children.add(Positioned(
          left: 7,
          bottom: 22,
          child: _CommentSkeleton(
            lines: config.chatMode == LiveChatMode.open ? 2 : 1,
            light: light && config.mode != LiveSetupMode.game,
          ),
        ));
        if (config.acceptsRequests) {
          children.add(Positioned(
            right: 6,
            bottom: 6,
            child: AnimatedScale(
              scale: highlightRequests ? 1.1 : 1,
              duration: const Duration(milliseconds: 220),
              child: const _Chip(Icons.front_hand_rounded, 'Join', color: AppColors.brandPink),
            ),
          ));
        }
      }
      return Stack(children: children);
    });
  }
}

/// Step 1 — how each mode looks.
class SetupModePreview extends StatelessWidget {
  const SetupModePreview({super.key, required this.config});
  final LiveSetupConfig config;

  @override
  Widget build(BuildContext context) => SetupPhoneFrame(
        height: 185,
        dark: config.settings.theme == StudioTheme.dark || config.mode == LiveSetupMode.game,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: SetupStudioMock(key: ValueKey(config.mode), config: config, highlightRequests: config.acceptsRequests),
        ),
      );
}

/// Step 2 — the live card followers see in the feed.
class SetupDetailsPreview extends StatelessWidget {
  const SetupDetailsPreview({super.key, required this.config, required this.hostName});
  final LiveSetupConfig config;
  final String hostName;

  @override
  Widget build(BuildContext context) {
    final cover = config.coverPath;
    return SetupPhoneFrame(
      height: 180,
      child: Stack(fit: StackFit.expand, children: [
        if (cover != null)
          Image.file(File(cover), fit: BoxFit.cover)
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.brandBlue, AppColors.darkBackground],
              ),
            ),
            child: Center(child: Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.textSecondary)),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), AppColors.brandBlack],
            ),
          ),
        ),
        const Positioned(left: 8, top: 8, child: SetupLiveBadge(small: true)),
        Positioned(
          left: 8,
          right: 8,
          bottom: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Chip(Icons.local_offer_rounded, config.mode == LiveSetupMode.game ? 'Gaming' : config.category),
            const SizedBox(height: 4),
            Text(config.effectiveTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.brandWhite, height: 1.15)),
            const SizedBox(height: 2),
            Text(hostName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

/// Step 3 — real camera preview in the frame, with live Look, Lighting & Beauty chips.
class SetupCameraPreview extends StatelessWidget {
  const SetupCameraPreview({super.key, required this.config, required this.video, required this.micLevel});
  final LiveSetupConfig config;
  final Widget? video;
  final Stream<double>? micLevel;

  @override
  Widget build(BuildContext context) {
    final look = lookPresetById(config.lookId);
    final light = lightingPresetById(config.lightingId);
    return SetupPhoneFrame(
      height: 210,
      child: Stack(fit: StackFit.expand, children: [
        if (config.cameraOn && video != null)
          video!
        else
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(config.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, size: 30, color: AppColors.textMuted),
            const SizedBox(height: 6),
            Text(config.cameraOn ? 'Starting camera…' : 'Camera off',
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
          ]),
        const Positioned(left: 8, top: 8, child: SetupLiveBadge(small: true)),
        if (config.lookId != 'neutral' || config.lightingId != 'natural')
          Positioned(
            right: 6,
            top: 8,
            child: _Chip(
              Icons.palette_rounded,
              config.lookId != 'neutral' ? look.name : light.name,
              color: AppColors.brandBlue,
            ),
          ),
        Positioned(
          left: 6,
          bottom: 8,
          child: Row(children: [
            _Chip(config.micOn ? Icons.mic_rounded : Icons.mic_off_rounded, config.micOn ? 'Mic' : 'Muted',
                color: config.micOn ? AppColors.brandBlue : AppColors.textMuted),
            if (config.beautyOn) ...[
              const SizedBox(width: 4),
              const _Chip(Icons.auto_awesome_rounded, 'Beauty', color: AppColors.brandPink),
            ],
          ]),
        ),
        if (config.micOn && micLevel != null)
          Positioned(
            right: 8,
            bottom: 8,
            child: StreamBuilder<double>(
              stream: micLevel,
              builder: (context, snap) => SetupMicMeter(level: snap.data ?? 0),
            ),
          ),
      ]),
    );
  }
}

/// Five-bar mic level meter.
class SetupMicMeter extends StatelessWidget {
  const SetupMicMeter({super.key, required this.level});
  final double level;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 5; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              margin: const EdgeInsets.only(left: 2),
              width: 3.5,
              height: 5.0 + i * 2.5,
              decoration: BoxDecoration(
                color: level * 5 > i ? AppColors.brandPink : AppColors.brandWhite.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      );
}

/// Step 5 — who can watch, comment rules, join requests on the mock.
class SetupAudiencePreview extends StatelessWidget {
  const SetupAudiencePreview({super.key, required this.config});
  final LiveSetupConfig config;

  @override
  Widget build(BuildContext context) {
    final chat = switch (config.chatMode) {
      LiveChatMode.open => null,
      LiveChatMode.slow => 'Slow · ${config.slowSeconds}s',
      LiveChatMode.followers => 'Followers chat',
    };
    return SetupPhoneFrame(
      height: 176,
      dark: config.settings.theme == StudioTheme.dark || config.mode == LiveSetupMode.game,
      child: Stack(fit: StackFit.expand, children: [
        SetupStudioMock(config: config, highlightRequests: config.acceptsRequests),
        Positioned(
          right: 6,
          top: 8,
          child: _Chip(config.audience.icon, config.audience.label,
              color: config.audience == LiveAudience.public ? AppColors.brandBlue : AppColors.brandPink),
        ),
        if (chat != null)
          Positioned(
            left: 6,
            bottom: 64,
            child: _Chip(config.chatMode.icon, chat, color: AppColors.brandBlue),
          ),
      ]),
    );
  }
}
