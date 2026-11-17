import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../desktop_agent/desktop_window_bridge.dart';
import '../../ova_assistant/widgets/ova_fluid_voice_orb.dart';
import '../../shared/audio/ova_vertex_audio_engine.dart';
import '../../shared/theme/app_theme.dart';
import '../ova_agent_sync_controller.dart';
import '../ova_wispr_flow_service.dart';

/// Compact Holla / Spotlight-style floating desktop HUD that can be summoned
/// anywhere on macOS (`⌥Space`) or Windows (`Alt+Space`) over Logic Pro,
/// DaVinci Resolve, Adobe Suite, Terminal, or Browser.
class OvaDesktopHud extends ConsumerStatefulWidget {
  final VoidCallback onExpandStudio;
  final VoidCallback onHideHud;

  const OvaDesktopHud({
    super.key,
    required this.onExpandStudio,
    required this.onHideHud,
  });

  @override
  ConsumerState<OvaDesktopHud> createState() => _OvaDesktopHudState();
}

class _OvaDesktopHudState extends ConsumerState<OvaDesktopHud> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  final OvaWisprFlowService _wispr = OvaWisprFlowService();
  bool _recording = false;
  double _micLevel = 0.08;
  String? _lastSpokenId;

  @override
  void initState() {
    super.initState();
    DesktopWindowBridge.instance.summonTick.addListener(_onSummoned);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onSummoned() {
    if (!mounted) return;
    _focus.requestFocus();
  }

  @override
  void dispose() {
    DesktopWindowBridge.instance.summonTick.removeListener(_onSummoned);
    unawaited(_wispr.cancel());
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _input.text).trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    if (override == null) _input.clear();
    await ref.read(ovaAgentSyncProvider.notifier).sendPrompt(text);
  }

  Future<void> _toggleVoice() async {
    HapticFeedback.lightImpact();
    if (_recording) {
      setState(() => _recording = false);
      final res = await _wispr.stopAndTranscribe(
        activeWindow: ref.read(ovaAgentSyncProvider).workstationActiveWindow ?? 'Desktop',
        style: 'natural',
      );
      if (!mounted) return;
      if (res.polishedText.trim().isNotEmpty) {
        await _send(res.polishedText.trim());
      }
      return;
    }

    await OvaVertexAudioEngine.instance.stop();
    final start = await _wispr.startRecording(
      autoStopOnSilence: true,
      onLevel: (lvl) {
        if (mounted) setState(() => _micLevel = lvl);
      },
      onAutoSilenceCommit: () => unawaited(_toggleVoice()),
    );
    if (!mounted) return;
    if (start.started) {
      setState(() => _recording = true);
    }
  }

  void _speakLatestReply(OvaAgentWorkspaceState state) {
    if (state.turns.isEmpty) return;
    final last = state.turns.last;
    if (last.role != 'assistant' ||
        last.status != 'completed' ||
        last.id == _lastSpokenId ||
        last.text.trim().isEmpty) {
      return;
    }
    _lastSpokenId = last.id;
    unawaited(OvaVertexAudioEngine.instance.speak(last.text));
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(ovaAgentSyncProvider);
    final bridge = DesktopWindowBridge.instance;
    final lastReply = agent.turns.reversed
        .where((t) => t.role == 'assistant' && t.text.trim().isNotEmpty)
        .firstOrNull;
    _speakLatestReply(agent);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandBlue.withValues(alpha: 0.25),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top compact control bar
                Row(
                  children: [
                    OvaFluidVoiceOrb(
                      size: 26,
                      amplitude: _recording ? _micLevel : 0.2,
                      mode: _recording
                          ? OvaOrbMode.listening
                          : (agent.sending ? OvaOrbMode.thinking : OvaOrbMode.idle),
                      onTap: _toggleVoice,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ova Desktop Assistant',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            _recording
                                ? 'Listening… speak naturally to control ${agent.workstationActiveWindow ?? "your computer"}'
                                : agent.sending
                                    ? 'Working on your computer…'
                                    : '${agent.workstationActiveWindow ?? "Ready"} · ${bridge.hotkeyLabel.value}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: bridge.startupEnabled,
                      builder: (_, on, _) => _tinyToggle(
                        context,
                        icon: Icons.power_settings_new_rounded,
                        label: on ? 'Boot On' : 'Auto-Start',
                        active: on,
                        onTap: () => unawaited(bridge.setStartupEnabled(!on)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _tinyToggle(
                      context,
                      icon: Icons.open_in_full_rounded,
                      label: 'Studio',
                      active: false,
                      onTap: widget.onExpandStudio,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Hide to tray (${bridge.hotkeyLabel.value})',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onHideHud,
                      icon: Icon(Icons.close_rounded, size: 17, color: context.textSecondary),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Quick studio & OS skill chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _skillChip(context, 'Color Grade Resolve', Icons.palette_rounded,
                          'In DaVinci Resolve, switch to Color page, add a grading node, and apply a warm cinematic film grade'),
                      _skillChip(context, 'Logic Pro Mix', Icons.graphic_eq_rounded,
                          'Inspect my Logic Pro session and prepare the mixer with clean balance'),
                      _skillChip(context, 'Premiere Cut', Icons.movie_creation_rounded,
                          'Cut at the playhead in Adobe Premiere Pro and inspect timeline'),
                      _skillChip(context, 'Photoshop Polish', Icons.brush_rounded,
                          'In Adobe Photoshop add a clean polish layer ready for export'),
                      _skillChip(context, 'Inspect Screen', Icons.screenshot_monitor_rounded,
                          'Look at what is currently on my computer screen and summarize it naturally'),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Natural reply snippet or prompt input
                if (lastReply != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      lastReply.text.replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.3,
                        color: context.textPrimary,
                      ),
                    ),
                  ),

                const Spacer(),

                // Prompt & Gemini Live Voice row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          onSubmitted: (_) => unawaited(_send()),
                          style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Ask Ova to edit, color grade, mix audio, or control any app…',
                            hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _recording ? 'Finish speaking' : 'Speak naturally (Vertex Live)',
                        visualDensity: VisualDensity.compact,
                        onPressed: _toggleVoice,
                        icon: Icon(
                          _recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                          size: 20,
                          color: _recording ? AppColors.brandPink : AppColors.brandBlue,
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: () => unawaited(_send()),
                        child: Text(
                          'Run',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 160.ms).slideY(begin: 0.06, end: 0),
      ),
    );
  }

  Widget _tinyToggle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppColors.brandBlue.withValues(alpha: 0.16)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active ? AppColors.brandBlue : context.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? AppColors.brandBlue : context.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.brandBlue : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skillChip(BuildContext context, String label, IconData icon, String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => unawaited(_send(prompt)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: context.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: AppColors.brandPink),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
