// LIVE SETUP WIZARD — visual mock-ups: each step shows, on a phone frame,
// what the setting it edits will look like on air. Pure drawing (no data):
// skeleton bars stand in for comments, silhouettes for people.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../shared/theme/app_theme.dart';
import 'live_setup_config.dart';

/// A rounded phone-shaped frame (9:16) holding a preview.
class SetupPhoneFrame extends StatelessWidget {
  const SetupPhoneFrame({super.key, required this.child, this.height = 300, this.dark = true});
  final Widget child;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: height,
        width: height * 9 / 16,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppColors.brandBlack,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.28), blurRadius: 30, offset: const Offset(0, 12)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: ColoredBox(color: dark ? AppColors.darkBackground : AppColors.lightSurface, child: child),
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
            style: GoogleFonts.inter(fontSize: small ? 8 : 10, fontWeight: FontWeight.w900, color: AppColors.brandWhite)),
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
        return Center(child: Icon(Icons.person_rounded, size: s * 0.7, color: color));
      });
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.ring, this.light = false, this.label});
  final Widget child;
  final Color? ring;
  final bool light;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: light ? AppColors.lightSurfaceHighlight : AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ring ?? (light ? AppColors.lightBorder : AppColors.outline), width: ring == null ? 1 : 2),
        ),
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(7), child: child),
          if (label != null)
            Positioned(
              left: 3,
              bottom: 3,
              right: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.brandBlack.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 6.5, fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
              ),
            ),
        ]),
      );
}

/// Skeleton lines where comments will appear.
class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton({this.lines = 3, this.light = false});
  final int lines;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final c = (light ? AppColors.lightTextMuted : AppColors.textMuted).withValues(alpha: 0.45);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < lines; i++)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Container(
              width: 38.0 + (i * 23 % 40),
              height: 7,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 9, color: AppColors.brandWhite),
          const SizedBox(width: 3),
          Text(label, style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w800, color: AppColors.brandWhite)),
        ]),
      );
}

/// The on-air studio mock: center screen + guest walls, by mode and settings.
class SetupStudioMock extends StatelessWidget {
  const SetupStudioMock({super.key, required this.config, this.showChrome = true, this.highlightRequests = false});
  final LiveSetupConfig config;
  final bool showChrome;
  final bool highlightRequests;

  @override
  Widget build(BuildContext context) {
    final light = config.settings.theme == StudioTheme.light;
    final names = config.settings.showNames;
    final pinned = config.settings.speakerMode == SpeakerMode.hostPinned || !config.multiPanel;
    final guestScale = switch (config.settings.guestSize) {
      GuestSize.s => 0.22,
      GuestSize.m => 0.28,
      GuestSize.l => 0.34,
    };
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final children = <Widget>[];
      switch (config.mode) {
        case LiveSetupMode.solo:
          children.add(Positioned.fill(child: _Tile(light: light, ring: AppColors.brandBlue, label: names ? 'You' : null, child: const _Silhouette(host: true))));
        case LiveSetupMode.game:
          children.add(Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandBlue, AppColors.darkBackground],
                ),
              ),
              child: Center(child: Icon(Icons.sports_esports_rounded, size: w * 0.32, color: AppColors.brandWhite.withValues(alpha: 0.85))),
            ),
          ));
          children.add(Positioned(
            right: 8,
            top: h * 0.16,
            width: w * 0.3,
            height: w * 0.3,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkSurfaceHighlight,
                border: Border.all(color: AppColors.brandPink, width: 2),
              ),
              child: const _Silhouette(host: true),
            ),
          ));
        case LiveSetupMode.studio:
          final tile = w * guestScale;
          final centerW = w - tile * 2 - 16;
          final centerH = h * 0.42;
          final top = h * 0.14;
          children.add(Positioned(
            left: tile + 8,
            top: top,
            width: centerW,
            height: centerH,
            child: _Tile(
              light: light,
              ring: AppColors.brandBlue,
              label: names ? 'You · host' : null,
              child: const _Silhouette(host: true),
            ),
          ));
          for (var i = 0; i < 4; i++) {
            final left = i.isEven;
            final row = i ~/ 2;
            final speaking = !pinned && i == 1;
            children.add(Positioned(
              left: left ? 4 : null,
              right: left ? null : 4,
              top: top + row * (tile + 6),
              width: tile,
              height: tile,
              child: _Tile(
                light: light,
                ring: speaking ? AppColors.brandPink : null,
                label: names ? 'Guest ${i + 1}' : null,
                child: _Silhouette(dim: i > 1),
              ),
            ));
          }
      }
      if (showChrome) {
        children.add(const Positioned(left: 8, top: 10, child: SetupLiveBadge(small: true)));
        children.add(Positioned(
          left: 8,
          bottom: 30,
          child: _CommentSkeleton(lines: config.chatMode == LiveChatMode.open ? 3 : 2, light: light && config.mode != LiveSetupMode.game),
        ));
        if (config.acceptsRequests) {
          children.add(Positioned(
            right: 8,
            bottom: 8,
            child: AnimatedScale(
              scale: highlightRequests ? 1.15 : 1,
              duration: const Duration(milliseconds: 250),
              child: const _Chip(Icons.front_hand_rounded, 'Request to join', color: AppColors.brandPink),
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
        dark: config.settings.theme == StudioTheme.dark || config.mode == LiveSetupMode.game,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: SetupStudioMock(key: ValueKey(config.mode), config: config, highlightRequests: config.multiPanel),
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
            child: Center(child: Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.textSecondary)),
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
        const Positioned(left: 10, top: 12, child: SetupLiveBadge()),
        Positioned(
          left: 10,
          right: 10,
          bottom: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Chip(Icons.local_offer_rounded, config.mode == LiveSetupMode.game ? 'Gaming' : config.category),
            const SizedBox(height: 6),
            Text(config.effectiveTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brandWhite, height: 1.2)),
            const SizedBox(height: 4),
            Text(hostName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

/// Step 3 — real camera preview in the frame, with device chips.
class SetupCameraPreview extends StatelessWidget {
  const SetupCameraPreview({super.key, required this.config, required this.video, required this.micLevel});
  final LiveSetupConfig config;
  final Widget? video;
  final Stream<double>? micLevel;

  @override
  Widget build(BuildContext context) {
    return SetupPhoneFrame(
      height: 340,
      child: Stack(fit: StackFit.expand, children: [
        if (config.cameraOn && video != null)
          video!
        else
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(config.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(config.cameraOn ? 'Starting camera…' : 'Camera off',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        const Positioned(left: 10, top: 12, child: SetupLiveBadge(small: true)),
        Positioned(
          left: 10,
          bottom: 12,
          child: Row(children: [
            _Chip(config.micOn ? Icons.mic_rounded : Icons.mic_off_rounded, config.micOn ? 'Mic on' : 'Muted',
                color: config.micOn ? AppColors.brandBlue : AppColors.textMuted),
            const SizedBox(width: 6),
            if (config.beautyOn) const _Chip(Icons.auto_awesome_rounded, 'Beauty', color: AppColors.brandPink),
          ]),
        ),
        if (config.micOn && micLevel != null)
          Positioned(
            right: 10,
            bottom: 12,
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
              width: 4,
              height: 6.0 + i * 3,
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
      LiveChatMode.slow => 'Slow mode · ${config.slowSeconds}s',
      LiveChatMode.followers => 'Followers-only chat',
    };
    return SetupPhoneFrame(
      dark: config.settings.theme == StudioTheme.dark || config.mode == LiveSetupMode.game,
      child: Stack(fit: StackFit.expand, children: [
        SetupStudioMock(config: config, highlightRequests: config.acceptsRequests),
        Positioned(
          right: 8,
          top: 9,
          child: _Chip(config.audience.icon, config.audience.label,
              color: config.audience == LiveAudience.public ? AppColors.brandBlue : AppColors.brandPink),
        ),
        if (chat != null)
          Positioned(
            left: 8,
            bottom: 82,
            child: _Chip(config.chatMode.icon, chat, color: AppColors.brandBlue),
          ),
      ]),
    );
  }
}
