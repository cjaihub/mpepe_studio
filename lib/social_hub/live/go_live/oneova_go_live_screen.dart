import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../classic/live_classic_widgets.dart';
import '../widgets/oneova_live_creation_wizard.dart'
    show OneovaLiveCreationConfig;
import 'go_live_sheets.dart';
import 'go_live_platforms_sheet.dart';
import '../../../shared/widgets/linked_destinations_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GO LIVE — one screen, no steps.
//
// Camera preview fills the screen. A title card sits on top, a rail of
// animated icons on the right opens a pop-up sheet per setting, and the
// bottom switches between LIVE (classic full-screen) and STUDIO (guests as
// video windows on the Live Studio walls). Go LIVE → 3·2·1 → broadcast.
// ─────────────────────────────────────────────────────────────────────────────

class OneovaGoLiveScreen extends StatefulWidget {
  final CameraController? cameraController;
  final String initialLayoutMode;
  final Future<void> Function() onFlipCamera;
  final Future<void> Function(OneovaLiveCreationConfig config) onGoLive;
  final VoidCallback onClose;

  const OneovaGoLiveScreen({
    super.key,
    required this.cameraController,
    required this.onFlipCamera,
    required this.onGoLive,
    required this.onClose,
    this.initialLayoutMode = 'classic',
  });

  @override
  State<OneovaGoLiveScreen> createState() => _OneovaGoLiveScreenState();
}

class _OneovaGoLiveScreenState extends State<OneovaGoLiveScreen> {
  late OneovaLiveCreationConfig _cfg = OneovaLiveCreationConfig(
    category: 'Entertainment',
    layoutMode: widget.initialLayoutMode,
    atmospherePreset: widget.initialLayoutMode == 'studio'
        ? 'Executive Suite'
        : 'Cyber-Cinema 7.1',
  );
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  int _flipTurns = 0;
  int? _countdown;
  bool _starting = false;

  bool get _isStudio => _cfg.layoutMode == 'studio';
  bool get _isGaming => _cfg.layoutMode == 'gaming';

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _update(OneovaLiveCreationConfig next) => setState(() => _cfg = next);

  Future<void> _goLive() async {
    if (_starting) return;
    _titleFocus.unfocus();
    HapticFeedback.mediumImpact();
    setState(() => _starting = true);
    for (var i = 3; i >= 1; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      HapticFeedback.selectionClick();
      await Future.delayed(const Duration(milliseconds: 850));
    }
    if (!mounted) return;
    setState(() => _countdown = null);
    final cfg = _cfg.copyWith(
      title: _title.text.trim(),
      creatorConsentAgreed: true,
    );
    try {
      await widget.onGoLive(cfg);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _flip() async {
    setState(() => _flipTurns++);
    await widget.onFlipCamera();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.brandBlack,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _titleFocus.unfocus(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CameraLayer(
                controller: widget.cameraController,
                blur: _cfg.aiBackgroundBlur,
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.brandBlack.withValues(alpha: 0.45),
                        Colors.transparent,
                        Colors.transparent,
                        AppColors.brandBlack.withValues(alpha: 0.7),
                      ],
                      stops: const [0, 0.22, 0.55, 1],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Stack(
                  children: [
                    // ── Close ──
                    Positioned(
                      top: 6,
                      left: 10,
                      child: ClassicRoundButton(
                        icon: Icons.close_rounded,
                        size: 36,
                        tooltip: 'Close',
                        onTap: widget.onClose,
                      ),
                    ),

                    // ── Title card ──
                    Positioned(
                      top: 54,
                      left: 14,
                      right: 74,
                      child: _TitleCard(
                        avatarUrl: user?.photoURL ?? '',
                        controller: _title,
                        focusNode: _titleFocus,
                        category: _cfg.category,
                        audience: _cfg.audienceMode,
                        onTopic: () => GoLiveSheets.topic(context,
                            current: _cfg.category,
                            onPick: (c) => _update(_cfg.copyWith(category: c))),
                        onAudience: () => GoLiveSheets.audience(context,
                            config: _cfg, onChanged: _update),
                      ).animate().fadeIn(duration: 300.ms).slideY(
                          begin: -0.15, end: 0, curve: Curves.easeOut),
                    ),

                    // ── Right rail ──
                    Positioned(
                      top: 54,
                      right: 10,
                      child: Column(
                        children: [
                          _RailButton(
                            label: 'Flip',
                            onTap: _flip,
                            child: AnimatedRotation(
                              turns: _flipTurns * 0.5,
                              duration: 400.ms,
                              curve: Curves.easeOutBack,
                              child: const Icon(Icons.cameraswitch_rounded,
                                  color: AppColors.brandWhite, size: 22),
                            ),
                          ),
                          _RailButton(
                            label: 'Beauty',
                            onTap: () => GoLiveSheets.beauty(context,
                                config: _cfg, onChanged: _update),
                            child: const Icon(Icons.auto_awesome_rounded,
                                    color: AppColors.brandWhite, size: 22)
                                .animate(onPlay: (c) => c.repeat())
                                .shimmer(
                                    delay: 1800.ms,
                                    duration: 1100.ms,
                                    color: AppColors.brandPink),
                          ),
                          _RailButton(
                            label: _isStudio ? 'Scene' : 'Effects',
                            onTap: () => GoLiveSheets.scene(context,
                                config: _cfg, onChanged: _update),
                            child: const Icon(Icons.blur_on_rounded,
                                    color: AppColors.brandWhite, size: 22)
                                .animate(onPlay: (c) => c.repeat())
                                .rotate(duration: 6.seconds),
                          ),
                          _RailButton(
                            label: 'Audience',
                            onTap: () => GoLiveSheets.audience(context,
                                config: _cfg, onChanged: _update),
                            child: Icon(
                              _cfg.audienceMode == 'Private Room'
                                  ? Icons.lock_rounded
                                  : _cfg.audienceMode == 'Followers Only'
                                      ? Icons.group_rounded
                                      : Icons.public_rounded,
                              color: AppColors.brandWhite,
                              size: 22,
                            )
                                .animate(
                                    key: ValueKey(_cfg.audienceMode))
                                .scale(
                                    begin: const Offset(0.6, 0.6),
                                    duration: 250.ms,
                                    curve: Curves.easeOutBack),
                          ),
                          _RailButton(
                            label: 'Platforms',
                            onTap: () => GoLivePlatformsSheet.show(context),
                            child: Consumer(
                              builder: (context, ref, _) {
                                final n = ref
                                    .watch(activeDestinationsProvider(
                                        DestinationPurpose.live))
                                    .length;
                                return Badge(
                                  isLabelVisible: n > 0,
                                  label: Text('$n'),
                                  backgroundColor: AppColors.brandPink,
                                  child: const Icon(Icons.cell_tower_rounded,
                                      color: AppColors.brandWhite, size: 22),
                                );
                              },
                            ),
                          ),
                          _RailButton(
                            label: 'Settings',
                            onTap: () => GoLiveSheets.settings(context,
                                config: _cfg, onChanged: _update),
                            child: const Icon(Icons.tune_rounded,
                                    color: AppColors.brandWhite, size: 22)
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .moveY(
                                    begin: -1.5,
                                    end: 1.5,
                                    duration: 1200.ms,
                                    curve: Curves.easeInOut),
                          ),
                        ]
                            .animate(interval: 60.ms)
                            .fadeIn(duration: 250.ms)
                            .slideX(begin: 0.4, end: 0),
                      ),
                    ),

                    // ── Bottom: studio preview, Go LIVE, mode switch ──
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12 + bottomInset,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: 260.ms,
                            transitionBuilder: (c, a) => FadeTransition(
                              opacity: a,
                              child: SizeTransition(
                                  sizeFactor: a, child: c),
                            ),
                            child: _isStudio
                                ? _StudioPreviewCard(
                                    key: const ValueKey('studio'),
                                    preset: _cfg.atmospherePreset,
                                    onTap: () => GoLiveSheets.scene(context,
                                        config: _cfg, onChanged: _update),
                                  )
                                : const SizedBox(
                                    key: ValueKey('classic'), height: 0),
                          ),
                          const SizedBox(height: 12),
                          _GoLiveButton(
                            busy: _starting,
                            label: _isStudio
                                ? 'Go LIVE in Studio'
                                : (_isGaming ? 'Go LIVE with a game' : 'Go LIVE'),
                            onTap: _goLive,
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => GoLiveSheets.guidelines(context),
                            child: Text.rich(
                              TextSpan(
                                text: 'By going LIVE you agree to the ',
                                children: [
                                  TextSpan(
                                    text: 'Community Guidelines',
                                    style: GoogleFonts.inter(
                                        color: AppColors.brandWhite,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.underline,
                                        decorationColor: AppColors.brandWhite
                                            .withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: AppColors.brandWhite
                                      .withValues(alpha: 0.7),
                                  fontSize: 10.5),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ModeSwitch(
                            mode: _cfg.layoutMode,
                            onChanged: (m) {
                              HapticFeedback.selectionClick();
                              _update(_cfg.copyWith(
                                layoutMode: m,
                                hostingMode: m == 'studio'
                                    ? 'Multi-Guest Studio'
                                    : 'Solo Broadcast',
                                atmospherePreset: m == 'studio'
                                    ? 'Executive Suite'
                                    : _cfg.atmospherePreset,
                              ));
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── 3·2·1 countdown ──
              if (_countdown != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.brandBlack.withValues(alpha: 0.45),
                    child: Center(
                      child: Text(
                        '$_countdown',
                        key: ValueKey(_countdown),
                        style: GoogleFonts.inter(
                          color: AppColors.brandWhite,
                          fontSize: 120,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                          .animate()
                          .scale(
                              begin: const Offset(1.8, 1.8),
                              end: const Offset(1, 1),
                              duration: 380.ms,
                              curve: Curves.easeOutBack)
                          .fadeIn(duration: 200.ms)
                          .then(delay: 250.ms)
                          .fadeOut(duration: 200.ms),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIECES
// ─────────────────────────────────────────────────────────────────────────────

class _CameraLayer extends StatelessWidget {
  final CameraController? controller;
  final bool blur;
  const _CameraLayer({required this.controller, required this.blur});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return Container(
        color: AppColors.brandBlack,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_outlined,
                    color: AppColors.brandWhite, size: 34)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 0.35, end: 1, duration: 900.ms),
            const SizedBox(height: 10),
            Text('Starting camera…',
                style: GoogleFonts.inter(
                    color: AppColors.brandWhite.withValues(alpha: 0.7),
                    fontSize: 12.5)),
          ],
        ),
      );
    }
    final size = c.value.previewSize;
    Widget preview = c.buildPreview();
    if (size != null) {
      // previewSize is landscape; swap for portrait cover.
      preview = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
            width: size.height, height: size.width, child: preview),
      );
    }
    if (blur) {
      preview = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: preview,
      );
    }
    return ClipRect(child: preview);
  }
}

class _TitleCard extends StatelessWidget {
  final String avatarUrl;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String category;
  final String audience;
  final VoidCallback onTopic;
  final VoidCallback onAudience;

  const _TitleCard({
    required this.avatarUrl,
    required this.controller,
    required this.focusNode,
    required this.category,
    required this.audience,
    required this.onTopic,
    required this.onAudience,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.brandBlack.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
                color: AppColors.brandWhite.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: avatarUrl.isNotEmpty
                              ? Image.network(avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const _CoverFallback())
                              : const _CoverFallback(),
                        ),
                      ),
                      Positioned(
                        bottom: -4,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.brandBlack
                                  .withValues(alpha: 0.7),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text('Cover',
                                style: GoogleFonts.inter(
                                    color: AppColors.brandWhite,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLength: 60,
                      maxLines: 2,
                      minLines: 1,
                      cursorColor: AppColors.brandPink,
                      style: GoogleFonts.inter(
                          color: AppColors.brandWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Add a title to chat',
                        hintStyle: GoogleFonts.inter(
                            color:
                                AppColors.brandWhite.withValues(alpha: 0.6),
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _CardChip(
                    icon: GoLiveSheets.categoryIcon(category),
                    label: category,
                    onTap: onTopic,
                  ),
                  const SizedBox(width: 6),
                  _CardChip(
                    icon: audience == 'Private Room'
                        ? Icons.lock_outline_rounded
                        : audience == 'Followers Only'
                            ? Icons.group_outlined
                            : Icons.public_rounded,
                    label: audience == 'Followers Only'
                        ? 'Followers'
                        : audience == 'Private Room'
                            ? 'Private'
                            : 'Public',
                    onTap: onAudience,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [AppColors.brandBlue, AppColors.brandPink]),
        ),
        child: const Icon(Icons.sensors_rounded,
            color: AppColors.brandWhite, size: 24),
      );
}

class _CardChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CardChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: AppColors.brandWhite.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.brandWhite, size: 13),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.inter(
                    color: AppColors.brandWhite,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.brandWhite.withValues(alpha: 0.7),
                size: 14),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  final String label;
  final Widget child;
  final VoidCallback onTap;
  const _RailButton(
      {required this.label, required this.child, required this.onTap});

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.88 : 1,
          duration: const Duration(milliseconds: 150),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandBlack.withValues(alpha: 0.32),
                  shape: BoxShape.circle,
                ),
                child: widget.child,
              ),
              const SizedBox(height: 3),
              Text(widget.label,
                  style: GoogleFonts.inter(
                    color: AppColors.brandWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                          color: AppColors.brandBlack.withValues(alpha: 0.6),
                          blurRadius: 4),
                    ],
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioPreviewCard extends StatelessWidget {
  final String preset;
  final VoidCallback onTap;
  const _StudioPreviewCard(
      {super.key, required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 86,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/live_studio_1376.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.brandBlue)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.brandBlack.withValues(alpha: 0.75),
                  AppColors.brandBlack.withValues(alpha: 0.1),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.view_quilt_rounded,
                                color: AppColors.brandWhite, size: 14),
                            const SizedBox(width: 5),
                            Text('LIVE STUDIO',
                                style: GoogleFonts.inter(
                                    color: AppColors.brandWhite,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Guests appear as video windows on the studio walls.',
                          maxLines: 2,
                          style: GoogleFonts.inter(
                              color: AppColors.brandWhite
                                  .withValues(alpha: 0.85),
                              fontSize: 11.5,
                              height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(preset,
                        style: GoogleFonts.inter(
                            color: AppColors.brandWhite,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoLiveButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback onTap;
  const _GoLiveButton(
      {required this.busy, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 46,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.brandPink, AppColors.brandBlue]),
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
                color: AppColors.brandPink.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6)),
          ],
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.brandWhite))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sensors_rounded,
                          color: AppColors.brandWhite, size: 18)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1.12, 1.12),
                          duration: 800.ms),
                  const SizedBox(width: 8),
                  Text(label,
                      style: GoogleFonts.inter(
                          color: AppColors.brandWhite,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800)),
                ],
              ),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
            delay: 2500.ms,
            duration: 1200.ms,
            color: AppColors.brandWhite.withValues(alpha: 0.35));
  }
}

class _ModeSwitch extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(String value, String label) {
      final active = mode == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: 180.ms,
                style: GoogleFonts.inter(
                  color: active
                      ? AppColors.brandWhite
                      : AppColors.brandWhite.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.6,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: 220.ms,
                curve: Curves.easeOut,
                width: active ? 18 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.brandPink,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [tab('classic', 'LIVE'), tab('studio', 'STUDIO'), tab('gaming', 'GAME')],
    );
  }
}
