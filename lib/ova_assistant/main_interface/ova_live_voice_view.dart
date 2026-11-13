import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/theme/app_theme.dart';
import '../services/ova_shared_history_service.dart';
import '../services/ova_tool_registry.dart';
import '../services/ova_voice_session_controller.dart';
import '../widgets/ova_fluid_voice_orb.dart';

/// Full dedicated Live Voice screen inside the Ova Main Interface (`/hub/ai`).
class OvaLiveVoiceView extends ConsumerStatefulWidget {
  final OvaWorkspaceId workspace;
  final VoidCallback onBack;

  const OvaLiveVoiceView({
    super.key,
    required this.workspace,
    required this.onBack,
  });

  @override
  ConsumerState<OvaLiveVoiceView> createState() => _OvaLiveVoiceViewState();
}

class _OvaLiveVoiceViewState extends ConsumerState<OvaLiveVoiceView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(ovaMainVoiceSessionProvider.notifier);
      notifier.configureContext(
        workspace: widget.workspace,
        permissionContext: context,
      );
      if (!ref.read(ovaMainVoiceSessionProvider).isActive) {
        notifier.startSession(
          workspace: widget.workspace,
          permissionContext: context,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaMainVoiceSessionProvider);
    final notifier = ref.read(ovaMainVoiceSessionProvider.notifier);

    ref.listen<OvaVoiceSessionState>(ovaMainVoiceSessionProvider, (prev, next) {
      if (next.pendingRoute != null && next.pendingRoute != prev?.pendingRoute) {
        final route = next.pendingRoute!;
        notifier.consumePendingRoute();
        if (mounted) context.push(route);
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: context.bg,
        gradient: RadialGradient(
          center: const Alignment(0, -0.22),
          radius: 1.15,
          colors: [
            const Color(0xFF818CF8).withValues(alpha: context.isDark ? 0.16 : 0.08),
            AppColors.brandBlue.withValues(alpha: context.isDark ? 0.08 : 0.04),
            context.bg,
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
      ),
      child: Column(
        children: [
          // 1. Sleek Modern Header (48px)
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      notifier.endSession();
                      widget.onBack();
                    },
                    icon: Icon(Icons.chevron_left_rounded, size: 26, color: context.textPrimary),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Live Voice',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: context.isDark ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            'Advanced',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Voice settings',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showVoiceSettingsSheet(context, ref, isOverlay: false),
                    icon: Icon(Icons.tune_rounded, size: 20, color: context.textPrimary),
                  ),
                ],
              ),
            ),
          ),

          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _VoiceErrorBanner(
                message: state.errorMessage!,
                onRetry: notifier.retryMicrophone,
              ),
            ),

          // 2. Center Status, Fluid Orb & Transcripts
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = constraints.maxHeight < 480;
                final orbSize = compactHeight ? 134.0 : 178.0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Status indicator: ● Listening...
                        _VoiceStatusPill(state: state),

                        // Fluid Luminous Celestial Voice Orb
                        OvaFluidVoiceOrb(
                          size: orbSize,
                          amplitude: state.amplitude,
                          mode: state.orbMode,
                          onTap: notifier.toggleMic,
                        ),

                        // Live Speech & Intelligent Response Bubbles
                        if (state.captionsEnabled)
                          _LiveVoiceTranscriptStack(
                            userTranscript: state.userTranscript,
                            assistantReply: state.assistantReply,
                            workspace: widget.workspace,
                            onQuickPrompt: notifier.submitSpokenUtterance,
                          )
                        else
                          Text(
                            'Captions hidden · Tap CC below to show live text',
                            style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. Bottom Control Bar + Toggles + Privacy Lock
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pause / Mic / End buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _VoiceCircleButton(
                      size: 46,
                      icon: state.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      tooltip: state.isPaused ? 'Resume voice' : 'Pause voice',
                      fillColor: context.surface,
                      iconColor: context.textPrimary,
                      hasBorder: true,
                      onTap: notifier.togglePause,
                    ),
                    const SizedBox(width: 24),
                    _VoiceCircleButton(
                      size: 64,
                      icon: state.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      tooltip: state.isMicMuted ? 'Unmute microphone' : 'Microphone active',
                      fillColor: state.isMicMuted ? context.surfaceMid : AppColors.brandBlue,
                      iconColor: state.isMicMuted ? AppColors.brandPink : AppColors.brandWhite,
                      hasBorder: state.isMicMuted,
                      glowColor: state.isMicMuted ? null : AppColors.brandBlue,
                      onTap: notifier.toggleMic,
                    ),
                    const SizedBox(width: 24),
                    _VoiceCircleButton(
                      size: 46,
                      icon: Icons.call_end_rounded,
                      tooltip: 'End voice session',
                      fillColor: AppColors.brandPink,
                      iconColor: AppColors.brandWhite,
                      glowColor: AppColors.brandPink,
                      onTap: () {
                        notifier.endSession();
                        widget.onBack();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Captions & Audio dropdown toggles
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _VoiceMicroToggle(
                      icon: state.captionsEnabled
                          ? Icons.closed_caption_rounded
                          : Icons.closed_caption_disabled_outlined,
                      label: 'Captions',
                      active: state.captionsEnabled,
                      trailingIcon: Icons.keyboard_arrow_down_rounded,
                      onTap: notifier.toggleCaptions,
                    ),
                    _VoiceMicroToggle(
                      icon: state.audioEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: state.audioEnabled ? 'Audio' : 'Muted',
                      active: state.audioEnabled,
                      trailingIcon: Icons.keyboard_arrow_down_rounded,
                      onTap: notifier.toggleAudioOutput,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Private session indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 12, color: context.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      'You\'re in a private voice session',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact Voice Mode embedded directly inside the Ova Overlay Assistant Sheet.
class OvaOverlayVoiceCard extends ConsumerStatefulWidget {
  final OvaInvocationContext invocation;
  final VoidCallback onSwitchToText;
  final VoidCallback onCloseOverlay;
  final ValueChanged<String>? onNavigateRoute;

  const OvaOverlayVoiceCard({
    super.key,
    this.invocation = const OvaInvocationContext(),
    required this.onSwitchToText,
    required this.onCloseOverlay,
    this.onNavigateRoute,
  });

  @override
  ConsumerState<OvaOverlayVoiceCard> createState() => _OvaOverlayVoiceCardState();
}

class _OvaOverlayVoiceCardState extends ConsumerState<OvaOverlayVoiceCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(ovaOverlayVoiceSessionProvider.notifier);
      notifier.configureContext(
        invocation: widget.invocation,
        permissionContext: context,
      );
      if (!ref.read(ovaOverlayVoiceSessionProvider).isActive) {
        notifier.startSession(
          invocation: widget.invocation,
          permissionContext: context,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaOverlayVoiceSessionProvider);
    final notifier = ref.read(ovaOverlayVoiceSessionProvider.notifier);

    ref.listen<OvaVoiceSessionState>(ovaOverlayVoiceSessionProvider, (prev, next) {
      if (next.pendingRoute != null && next.pendingRoute != prev?.pendingRoute) {
        final route = next.pendingRoute!;
        notifier.consumePendingRoute();
        widget.onNavigateRoute?.call(route);
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top status & private session pill
          Row(
            children: [
              _VoiceStatusPill(state: state, compact: true),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 10, color: context.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'Overlay Voice',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            _VoiceErrorBanner(
              message: state.errorMessage!,
              compact: true,
              onRetry: notifier.retryMicrophone,
            ),
          ],

          const SizedBox(height: 6),

          // Mini Fluid Voice Orb
          OvaFluidVoiceOrb(
            size: 92,
            amplitude: state.amplitude,
            mode: state.orbMode,
            onTap: notifier.toggleMic,
          ),

          const SizedBox(height: 6),

          // Compact Captions Box
          if (state.captionsEnabled)
            _LiveVoiceTranscriptStack(
              userTranscript: state.userTranscript,
              assistantReply: state.assistantReply,
              workspace: OvaWorkspaceId.personal,
              compact: true,
              onQuickPrompt: notifier.submitSpokenUtterance,
            ),

          const SizedBox(height: 12),

          // Compact Controls Row: Pause / Mic / End
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _VoiceCircleButton(
                size: 38,
                icon: state.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                tooltip: state.isPaused ? 'Resume' : 'Pause',
                fillColor: context.surfaceMid,
                iconColor: context.textPrimary,
                hasBorder: true,
                onTap: notifier.togglePause,
              ),
              const SizedBox(width: 18),
              _VoiceCircleButton(
                size: 48,
                icon: state.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                tooltip: state.isMicMuted ? 'Unmute mic' : 'Mic active',
                fillColor: state.isMicMuted ? context.surfaceMid : AppColors.brandBlue,
                iconColor: state.isMicMuted ? AppColors.brandPink : AppColors.brandWhite,
                hasBorder: state.isMicMuted,
                glowColor: state.isMicMuted ? null : AppColors.brandBlue,
                onTap: notifier.toggleMic,
              ),
              const SizedBox(width: 18),
              _VoiceCircleButton(
                size: 38,
                icon: Icons.call_end_rounded,
                tooltip: 'End voice mode',
                fillColor: AppColors.brandPink,
                iconColor: AppColors.brandWhite,
                onTap: () {
                  notifier.endSession();
                  widget.onSwitchToText();
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Compact Bottom Toggles: Captions | Audio | Type instead
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _VoiceMicroToggle(
                icon: state.captionsEnabled
                    ? Icons.closed_caption_rounded
                    : Icons.closed_caption_disabled_outlined,
                label: 'Captions',
                active: state.captionsEnabled,
                onTap: notifier.toggleCaptions,
              ),
              _VoiceMicroToggle(
                icon: Icons.keyboard_alt_outlined,
                label: 'Type instead',
                active: false,
                onTap: () {
                  notifier.endSession();
                  widget.onSwitchToText();
                },
              ),
              _VoiceMicroToggle(
                icon: state.audioEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                label: state.audioEnabled ? 'Audio' : 'Muted',
                active: state.audioEnabled,
                onTap: notifier.toggleAudioOutput,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceStatusPill extends StatelessWidget {
  final OvaVoiceSessionState state;
  final bool compact;

  const _VoiceStatusPill({
    required this.state,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final (dotColor, statusText) = switch (state.phase) {
      OvaVoicePhase.listening => (
          const Color(0xFF8B5CF6),
          state.isMicMuted ? 'Muted' : 'Listening...',
        ),
      OvaVoicePhase.thinking => (
          AppColors.brandPink,
          'Thinking...',
        ),
      OvaVoicePhase.speaking => (
          const Color(0xFF38BDF8),
          'Speaking...',
        ),
      OvaVoicePhase.paused => (
          context.textMuted,
          'Paused',
        ),
      OvaVoicePhase.idle => (
          const Color(0xFF8B5CF6),
          'Listening...',
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: 0.55),
                blurRadius: 7,
              ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          statusText,
          style: GoogleFonts.inter(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LiveVoiceTranscriptStack extends StatelessWidget {
  final String userTranscript;
  final String assistantReply;
  final OvaWorkspaceId workspace;
  final bool compact;
  final ValueChanged<String> onQuickPrompt;

  const _LiveVoiceTranscriptStack({
    required this.userTranscript,
    required this.assistantReply,
    required this.workspace,
    this.compact = false,
    required this.onQuickPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final hasUserWords = userTranscript.trim().isNotEmpty;
    final hasAiWords = assistantReply.trim().isNotEmpty;
    final displayedUserText = hasUserWords
        ? userTranscript
        : 'Help me plan a focused week around my priorities.';
    final displayedAiText = hasAiWords
        ? assistantReply
        : 'Absolutely. I\'m organizing your priorities now.';

    final samplePrompts = compact
        ? const ['Flashlight on', 'Set a 5 min timer', 'Draft a reel hook']
        : const [
            'Help me plan a focused week around my priorities.',
            'Give me 3 viral reel hooks',
            'Check system health',
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User spoken transcript card
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border, width: 1.0),
            boxShadow: context.isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: compact ? 16 : 18,
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  displayedUserText,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Quick spoken prompt pills when user hasn't spoken yet
        if (!hasUserWords) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in samplePrompts)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onQuickPrompt(p);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Text(
                          p.length > 34 ? '${p.substring(0, 34)}…' : p,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: context.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Ova spoken reply row
        SizedBox(height: compact ? 8 : 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  displayedAiText,
                  maxLines: compact ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.38,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceCircleButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final String tooltip;
  final Color fillColor;
  final Color iconColor;
  final bool hasBorder;
  final Color? glowColor;
  final VoidCallback onTap;

  const _VoiceCircleButton({
    required this.size,
    required this.icon,
    required this.tooltip,
    required this.fillColor,
    required this.iconColor,
    this.hasBorder = false,
    this.glowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fillColor,
              border: hasBorder ? Border.all(color: context.border, width: 1.0) : null,
              boxShadow: glowColor != null
                  ? [
                      BoxShadow(
                        color: glowColor!.withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, size: size * 0.44, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _VoiceMicroToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final IconData? trailingIcon;
  final VoidCallback onTap;

  const _VoiceMicroToggle({
    required this.icon,
    required this.label,
    required this.active,
    this.trailingIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? AppColors.brandBlue : context.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? context.textPrimary : context.textSecondary,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 2),
              Icon(trailingIcon, size: 14, color: context.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceErrorBanner extends StatelessWidget {
  final String message;
  final bool compact;
  final VoidCallback? onRetry;

  const _VoiceErrorBanner({
    required this.message,
    this.compact = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isPerm = message.toLowerCase().contains('settings') ||
        message.toLowerCase().contains('permission');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: AppColors.brandPink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35), width: 1.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic_off_rounded, size: 14, color: AppColors.brandPink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textPrimary),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, size: 12, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      'Retry Mic',
                      style: GoogleFonts.inter(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (isPerm) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: openAppSettings,
              child: Text(
                'Settings',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _showVoiceSettingsSheet(BuildContext context, WidgetRef ref, {required bool isOverlay}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final state = isOverlay
              ? ref.watch(ovaOverlayVoiceSessionProvider)
              : ref.watch(ovaMainVoiceSessionProvider);
          final notifier = isOverlay
              ? ref.read(ovaOverlayVoiceSessionProvider.notifier)
              : ref.read(ovaMainVoiceSessionProvider.notifier);

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
              border: Border(top: BorderSide(color: context.border, width: 1.0)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.border,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Live Voice Settings',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _VoiceSettingSwitchTile(
                    icon: Icons.noise_aware_rounded,
                    title: 'Clean up voice audio',
                    subtitle: 'Suppress background noise & echo',
                    value: state.voiceEnhanced,
                    onChanged: (_) => notifier.toggleVoiceEnhance(),
                  ),
                  _VoiceSettingSwitchTile(
                    icon: Icons.closed_caption_outlined,
                    title: 'Live captions',
                    subtitle: 'Show real-time spoken & AI text on screen',
                    value: state.captionsEnabled,
                    onChanged: (_) => notifier.toggleCaptions(),
                  ),
                  _VoiceSettingSwitchTile(
                    icon: Icons.volume_up_outlined,
                    title: 'Spoken voice replies',
                    subtitle: 'Read Ova\'s answers aloud automatically',
                    value: state.audioEnabled,
                    onChanged: (_) => notifier.toggleAudioOutput(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.speed_rounded, size: 16, color: context.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Speech pace',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.brandBlue,
                            thumbColor: AppColors.brandBlue,
                            inactiveTrackColor: context.border,
                          ),
                          child: Slider(
                            value: state.speechRate,
                            min: 0.35,
                            max: 0.75,
                            onChanged: notifier.setSpeechRate,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.border, width: 1.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        notifier.endSession();
                        context.push('/ova/live');
                      },
                      icon: const Icon(Icons.graphic_eq_rounded, size: 16, color: AppColors.brandPink),
                      label: Text(
                        'Open Gemini Native PCM Stream',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _VoiceSettingSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _VoiceSettingSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.brandBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

