import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../desktop_agent/macos_mouse_ffi.dart';
import '../../shared/theme/app_theme.dart';
import '../ova_agent_models.dart';
import '../ova_agent_sync_controller.dart';
import '../ova_wispr_flow_service.dart';

/// Executive Wispr-Flow-style AI Dictation, Voice-to-Mac-Cursor & Clipboard
/// Transformation Studio (synced across Desktop and Mobile).
class OvaWisprStudioView extends ConsumerStatefulWidget {
  final bool isRecording;
  final bool isProcessing;
  final List<double> waveformBars;
  final int recordingSeconds;
  final VoidCallback onToggleMic;
  final VoidCallback onCancelMic;
  final ValueChanged<String> onInsertToComposer;
  final ValueChanged<String> onSendToAgent;
  final OvaWisprFlowService wisprService;

  const OvaWisprStudioView({
    super.key,
    required this.isRecording,
    required this.isProcessing,
    required this.waveformBars,
    required this.recordingSeconds,
    required this.onToggleMic,
    required this.onCancelMic,
    required this.onInsertToComposer,
    required this.onSendToAgent,
    required this.wisprService,
  });

  @override
  ConsumerState<OvaWisprStudioView> createState() => _OvaWisprStudioViewState();
}

class _OvaWisprStudioViewState extends ConsumerState<OvaWisprStudioView> {
  String _selectedStyle = 'auto';
  bool _runningMacro = false;

  static const List<({String id, String label, IconData icon})> _styles = [
    (id: 'auto', label: 'Auto (Active App)', icon: Icons.auto_fix_high_rounded),
    (id: 'code', label: 'Code & Terminal', icon: Icons.code_rounded),
    (id: 'email', label: 'Executive Email', icon: Icons.mail_outline_rounded),
    (id: 'chat', label: 'Chat & Notes', icon: Icons.chat_bubble_outline_rounded),
  ];

  Future<void> _runClipboardMacro(
    String title,
    String instruction, {
    required bool pasteOnMac,
  }) async {
    if (_runningMacro) return;
    HapticFeedback.lightImpact();
    setState(() => _runningMacro = true);
    try {
      String clipText = '';
      if (!kIsWeb && Platform.isMacOS) {
        clipText = await MacOSMouseController.readClipboard();
      } else {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        clipText = data?.text ?? '';
      }
      if (clipText.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                'Copy text to your clipboard first to run "$title".',
                style: GoogleFonts.inter(fontSize: 12),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.brandPink,
            ),
          );
        }
        return;
      }

      final state = ref.read(ovaAgentSyncProvider);
      final transformed = await widget.wisprService.tidyOrTransformText(
        text: clipText,
        style: _selectedStyle,
        activeWindow: state.workstationActiveWindow ?? '',
        deviceId: state.workstationDeviceId,
        commandInstruction: instruction,
      );

      if (transformed.isEmpty) return;
      final notifier = ref.read(ovaAgentSyncProvider.notifier);
      if (pasteOnMac && state.workstationOnline) {
        await notifier.injectWisprToMacCursor(transformed);
      } else {
        await Clipboard.setData(ClipboardData(text: transformed));
        notifier.recordWisprHistoryItem(
          text: transformed,
          targetLabel: 'Clipboard Macro',
        );
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              pasteOnMac && state.workstationOnline
                  ? '$title → Pasted directly into ${state.workstationActiveWindow ?? "Mac"}!'
                  : '$title → Copied polished output to clipboard!',
              style: GoogleFonts.inter(fontSize: 12),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.brandBlue,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _runningMacro = false);
    }
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaAgentSyncProvider);
    final notifier = ref.read(ovaAgentSyncProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: [
        // 1. Hero Wispr Flow Voice Command Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: widget.isRecording
                  ? AppColors.brandPink.withValues(alpha: 0.65)
                  : context.border,
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      gradient: const LinearGradient(
                        colors: [AppColors.brandBlue, AppColors.brandPink],
                      ),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 17,
                      color: AppColors.brandWhite,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ova Wispr Flow • AI Voice Anywhere',
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          state.workstationOnline
                              ? 'Speak naturally → AI removes filler words & types straight into ${state.workstationActiveWindow ?? "your Mac"} or Agent.'
                              : 'Speak naturally → AI auto-polishes punctuation, code terms & structure in real time.',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      notifier.setHandsFreeWispr(!state.handsFreeWispr);
                    },
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: state.handsFreeWispr
                            ? AppColors.brandPink.withValues(alpha: 0.14)
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: state.handsFreeWispr
                              ? AppColors.brandPink
                              : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hearing_rounded,
                            size: 12,
                            color: state.handsFreeWispr
                                ? AppColors.brandPink
                                : context.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.handsFreeWispr ? 'Hands-Free ON' : 'Hands-Free',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: state.handsFreeWispr
                                  ? AppColors.brandPink
                                  : context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Output Destination Selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final target in OvaWisprTarget.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.setWisprTarget(target);
                          },
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: state.wisprTarget == target
                                  ? AppColors.brandBlue
                                  : context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(
                                color: state.wisprTarget == target
                                    ? AppColors.brandBlue
                                    : context.border,
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  target.icon,
                                  size: 14,
                                  color: state.wisprTarget == target
                                      ? AppColors.brandWhite
                                      : context.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  target.label,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: state.wisprTarget == target
                                        ? AppColors.brandWhite
                                        : context.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Style Selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final st in _styles)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedStyle = st.id);
                          },
                          child: Container(
                            height: 25,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: _selectedStyle == st.id
                                  ? AppColors.brandBlue.withValues(alpha: 0.14)
                                  : context.surfaceMid,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                color: _selectedStyle == st.id
                                    ? AppColors.brandBlue
                                    : context.border,
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  st.icon,
                                  size: 11.5,
                                  color: _selectedStyle == st.id
                                      ? AppColors.brandBlue
                                      : context.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  st.label,
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: _selectedStyle == st.id
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _selectedStyle == st.id
                                        ? AppColors.brandBlue
                                        : context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Live Waveform + Mic Trigger Deck
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.isProcessing ? null : widget.onToggleMic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isRecording
                              ? AppColors.brandPink
                              : AppColors.brandBlue,
                          boxShadow: [
                            BoxShadow(
                              color: (widget.isRecording
                                      ? AppColors.brandPink
                                      : AppColors.brandBlue)
                                  .withValues(alpha: 0.32),
                              blurRadius: widget.isRecording ? 14 : 8,
                              spreadRadius: widget.isRecording ? 2 : 0,
                            ),
                          ],
                        ),
                        child: widget.isProcessing
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: AppColors.brandWhite,
                                ),
                              )
                            : Icon(
                                widget.isRecording
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                size: 22,
                                color: AppColors.brandWhite,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.isProcessing
                                    ? 'Polishing speech with Ova Wispr AI…'
                                    : widget.isRecording
                                        ? 'Listening (${_formatDuration(widget.recordingSeconds)}) • ${state.wisprTarget.label}'
                                        : 'Tap Mic to dictate (${state.wisprTarget.label})',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: widget.isRecording
                                      ? AppColors.brandPink
                                      : context.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 24,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                for (var i = 0;
                                    i < widget.waveformBars.length;
                                    i++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 1.2),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 80),
                                        height: widget.isRecording
                                            ? (4.0 +
                                                widget.waveformBars[i] * 20.0)
                                            : 4.0,
                                        decoration: BoxDecoration(
                                          color: widget.isRecording
                                              ? (i.isEven
                                                  ? AppColors.brandPink
                                                  : AppColors.brandBlue)
                                              : context.border,
                                          borderRadius: BorderRadius.circular(
                                              AppRadius.full),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isRecording) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(color: context.border, width: 1.0),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          onPressed: widget.onCancelMic,
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Instant Clipboard & Cursor AI Rewrite Macros
        Text(
          'INSTANT WISPR CLIPBOARD & CURSOR TRANSFORMS',
          style: GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: context.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _MacroActionChip(
              icon: Icons.auto_fix_high_rounded,
              label: state.workstationOnline
                  ? 'Polish Clipboard → Paste on Mac'
                  : 'Polish Clipboard',
              busy: _runningMacro,
              onTap: () => _runClipboardMacro(
                'Wispr Polish',
                'Clean up grammar, punctuation, and clarity while preserving exact meaning.',
                pasteOnMac: true,
              ),
            ),
            _MacroActionChip(
              icon: Icons.format_list_bulleted_rounded,
              label: 'Clipboard → Crisp Bullets',
              busy: _runningMacro,
              onTap: () => _runClipboardMacro(
                'Bullet Summary',
                'Turn this text into concise, high-impact executive bullet points.',
                pasteOnMac: true,
              ),
            ),
            _MacroActionChip(
              icon: Icons.business_center_outlined,
              label: 'Executive Tone Rewrite',
              busy: _runningMacro,
              onTap: () => _runClipboardMacro(
                'Executive Rewrite',
                'Rewrite into a sharp, concise executive message ready to send.',
                pasteOnMac: true,
              ),
            ),
            _MacroActionChip(
              icon: Icons.translate_rounded,
              label: 'Translate → English',
              busy: _runningMacro,
              onTap: () => _runClipboardMacro(
                'Translate to English',
                'Translate accurately into natural, fluent English.',
                pasteOnMac: false,
              ),
            ),
          ],
        ),

        if (state.wisprHistory.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'RECENT WISPR DICTATIONS',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in state.wisprHistory.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            '${item.targetLabel} • ${item.activeApp}',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: item.text));
                            HapticFeedback.selectionClick();
                          },
                          child: Icon(
                            Icons.content_copy_rounded,
                            size: 13.5,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      item.text,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.38,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (state.workstationOnline)
                          _MiniTextAction(
                            icon: Icons.desktop_mac_rounded,
                            label: 'Type on Mac',
                            color: AppColors.brandBlue,
                            onTap: () =>
                                notifier.injectWisprToMacCursor(item.text),
                          ),
                        if (state.workstationOnline) const SizedBox(width: 10),
                        _MiniTextAction(
                          icon: Icons.auto_awesome_rounded,
                          label: 'Send to Agent',
                          color: AppColors.brandPink,
                          onTap: () => widget.onSendToAgent(item.text),
                        ),
                        const SizedBox(width: 10),
                        _MiniTextAction(
                          icon: Icons.edit_note_rounded,
                          label: 'Composer',
                          color: context.textSecondary,
                          onTap: () => widget.onInsertToComposer(item.text),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Unified Remote Multi-Touch Trackpad, Live Keyboard Stream, macOS Shortcut
/// Matrix, and Real-Time Action Receiver Deck.
class OvaLiveInputDeck extends ConsumerStatefulWidget {
  final VoidCallback? onOpenPairWorkstation;

  const OvaLiveInputDeck({
    super.key,
    this.onOpenPairWorkstation,
  });

  @override
  ConsumerState<OvaLiveInputDeck> createState() => _OvaLiveInputDeckState();
}

class _OvaLiveInputDeckState extends ConsumerState<OvaLiveInputDeck> {
  final TextEditingController _directTypeController = TextEditingController();
  double _sensitivity = 1.65;
  bool _dragLocked = false;
  bool _pressEnterAfterPaste = false;
  bool _liveKeystrokeStream = false;
  String _prevLiveValue = '';
  DateTime _lastMoveSent = DateTime.fromMillisecondsSinceEpoch(0);
  double _accumDx = 0;
  double _accumDy = 0;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void dispose() {
    _directTypeController.dispose();
    super.dispose();
  }

  void _handleTrackpadPanUpdate(DragUpdateDetails d) {
    _accumDx += d.delta.dx * _sensitivity;
    _accumDy += d.delta.dy * _sensitivity;
    final now = DateTime.now();
    // Throttle cloud packets on mobile while keeping local FFI 60fps
    final minGapMs = _isDesktop ? 8 : 38;
    if (now.difference(_lastMoveSent).inMilliseconds < minGapMs) return;
    _lastMoveSent = now;
    final dx = _accumDx;
    final dy = _accumDy;
    _accumDx = 0;
    _accumDy = 0;
    ref.read(ovaAgentSyncProvider.notifier).dispatchDirectMacCommand(
          'mouse_move',
          payload: {'dx': dx, 'dy': dy},
          logCategory: 'mouse',
        );
  }

  void _handleTrackpadPanEnd(DragEndDetails _) {
    if (_accumDx.abs() > 0.4 || _accumDy.abs() > 0.4) {
      final dx = _accumDx;
      final dy = _accumDy;
      _accumDx = 0;
      _accumDy = 0;
      ref.read(ovaAgentSyncProvider.notifier).dispatchDirectMacCommand(
            'mouse_move',
            payload: {'dx': dx, 'dy': dy},
            logCategory: 'mouse',
          );
    }
  }

  void _handleLiveKeystrokeChanged(String next) {
    if (!_liveKeystrokeStream) {
      _prevLiveValue = next;
      return;
    }
    final notifier = ref.read(ovaAgentSyncProvider.notifier);
    if (next.length < _prevLiveValue.length) {
      final diff = _prevLiveValue.length - next.length;
      for (var i = 0; i < diff.clamp(1, 5); i++) {
        notifier.dispatchDirectMacCommand(
          'key_tap',
          payload: const {'key': 'backspace'},
          logCategory: 'keyboard',
          logSummary: 'Live key: ⌫',
        );
      }
    } else if (next.length > _prevLiveValue.length &&
        next.startsWith(_prevLiveValue)) {
      final delta = next.substring(_prevLiveValue.length);
      if (delta == '\n') {
        notifier.dispatchDirectMacCommand(
          'key_tap',
          payload: const {'key': 'enter'},
          logCategory: 'keyboard',
          logSummary: 'Live key: Return',
        );
      } else {
        notifier.dispatchDirectMacCommand(
          'paste_text',
          payload: {'text': delta, 'pressEnter': false},
          logCategory: 'keyboard',
          logSummary: 'Live keystrokes: "$delta"',
        );
      }
    }
    _prevLiveValue = next;
  }

  Future<void> _sendInstantText() async {
    final txt = _directTypeController.text;
    if (txt.isEmpty) return;
    HapticFeedback.lightImpact();
    _directTypeController.clear();
    _prevLiveValue = '';
    await ref.read(ovaAgentSyncProvider.notifier).dispatchDirectMacCommand(
          'paste_text',
          payload: {
            'text': txt,
            'pressEnter': _pressEnterAfterPaste,
          },
          logCategory: 'keyboard',
          logSummary:
              'Injected "${txt.length > 32 ? "${txt.substring(0, 32)}…" : txt}"${_pressEnterAfterPaste ? " + ⏎" : ""}',
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaAgentSyncProvider);
    final notifier = ref.read(ovaAgentSyncProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: [
        // Workstation Status Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              Icon(
                Icons.desktop_mac_rounded,
                size: 16,
                color: state.workstationOnline
                    ? AppColors.brandBlue
                    : AppColors.brandPink,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.workstationOnline
                      ? '${state.workstationName ?? "Mac"} • Active Focus: ${state.workstationActiveWindow ?? "Desktop"}'
                      : 'Mac workstation offline — pair or open OneOva on your Mac.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
              if (!state.workstationOnline &&
                  !_isDesktop &&
                  widget.onOpenPairWorkstation != null)
                InkWell(
                  onTap: widget.onOpenPairWorkstation,
                  child: Text(
                    'Connect →',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 1. Multi-Gesture Precision Trackpad + Vertical 2-Finger Scroll Strip
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.touch_app_rounded,
                    size: 15,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PRECISION TRACKPAD & SCROLL',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  for (final s in const [1.0, 1.65, 2.4])
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        onTap: () => setState(() => _sensitivity = s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _sensitivity == s
                                ? AppColors.brandBlue
                                : context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border:
                                Border.all(color: context.border, width: 1.0),
                          ),
                          child: Text(
                            '${s.toStringAsFixed(1)}x',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: _sensitivity == s
                                  ? AppColors.brandWhite
                                  : context.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 176,
                child: Row(
                  children: [
                    // Main Trackpad Surface
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: _handleTrackpadPanUpdate,
                        onPanEnd: _handleTrackpadPanEnd,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          notifier.dispatchDirectMacCommand(
                            'mouse_left_click',
                            logCategory: 'mouse',
                            logSummary: 'Trackpad Left Click',
                          );
                        },
                        onDoubleTap: () {
                          HapticFeedback.mediumImpact();
                          notifier.dispatchDirectMacCommand(
                            'mouse_double_click',
                            logCategory: 'mouse',
                            logSummary: 'Trackpad Double Click',
                          );
                        },
                        onSecondaryTap: () {
                          HapticFeedback.mediumImpact();
                          notifier.dispatchDirectMacCommand(
                            'mouse_right_click',
                            logCategory: 'mouse',
                            logSummary: 'Trackpad Right Click',
                          );
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          notifier.dispatchDirectMacCommand(
                            'mouse_right_click',
                            logCategory: 'mouse',
                            logSummary: 'Trackpad Right Click',
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.surfaceMid,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border:
                                Border.all(color: context.border, width: 1.0),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_with_rounded,
                                  size: 22,
                                  color: context.textMuted,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Glide to move Mac cursor • Tap = Click • Double-Tap = Open • Hold = Right Click',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: context.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Dedicated Vertical Scroll Rail
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) {
                        notifier.dispatchDirectMacCommand(
                          'mouse_scroll',
                          payload: {'dy': -d.delta.dy * 3.0},
                          logCategory: 'mouse',
                        );
                      },
                      child: Container(
                        width: 40,
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.keyboard_arrow_up_rounded,
                                size: 16, color: context.textMuted),
                            const SizedBox(height: 6),
                            RotatedBox(
                              quarterTurns: 3,
                              child: Text(
                                'SCROLL',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: context.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                size: 16, color: context.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Physical Click Bar
              Row(
                children: [
                  Expanded(
                    child: _DeckKeyButton(
                      label: 'Left Click',
                      icon: Icons.ads_click_rounded,
                      onTap: () => notifier.dispatchDirectMacCommand(
                        'mouse_left_click',
                        logCategory: 'mouse',
                        logSummary: 'Left Click',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _DeckKeyButton(
                      label: _dragLocked ? 'Release Drag' : 'Drag Lock',
                      icon: Icons.pan_tool_alt_rounded,
                      highlighted: _dragLocked,
                      onTap: () {
                        setState(() => _dragLocked = !_dragLocked);
                        notifier.dispatchDirectMacCommand(
                          _dragLocked ? 'mouse_left_down' : 'mouse_left_up',
                          logCategory: 'mouse',
                          logSummary:
                              _dragLocked ? 'Drag Lock ON' : 'Drag Released',
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _DeckKeyButton(
                      label: 'Right Click',
                      icon: Icons.more_horiz_rounded,
                      onTap: () => notifier.dispatchDirectMacCommand(
                        'mouse_right_click',
                        logCategory: 'mouse',
                        logSummary: 'Right Click',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Direct Mac Keyboard & Instant Text Injection Bridge
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.keyboard_rounded,
                    size: 15,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'DIRECT KEYBOARD & INSTANT PASTE',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _liveKeystrokeStream = !_liveKeystrokeStream;
                        _prevLiveValue = _directTypeController.text;
                      });
                    },
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: _liveKeystrokeStream
                            ? AppColors.brandPink.withValues(alpha: 0.14)
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: _liveKeystrokeStream
                              ? AppColors.brandPink
                              : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _liveKeystrokeStream
                              ? 'Live Keystrokes ON'
                              : 'Live Keystrokes OFF',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _liveKeystrokeStream
                                ? AppColors.brandPink
                                : context.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _directTypeController,
                      onChanged: _handleLiveKeystrokeChanged,
                      onSubmitted: (_) => _sendInstantText(),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: context.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: context.surfaceMid,
                        hintText: _liveKeystrokeStream
                            ? 'Every keystroke streams live to your Mac…'
                            : 'Type text, URL, or code to paste instantly on Mac…',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: context.textMuted,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 9,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide:
                              BorderSide(color: context.border, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: const BorderSide(
                              color: AppColors.brandBlue, width: 1.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => setState(
                        () => _pressEnterAfterPaste = !_pressEnterAfterPaste),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: _pressEnterAfterPaste
                            ? AppColors.brandBlue.withValues(alpha: 0.14)
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: _pressEnterAfterPaste
                              ? AppColors.brandBlue
                              : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '+⏎',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _pressEnterAfterPaste
                                ? AppColors.brandBlue
                                : context.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: AppColors.brandWhite,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      onPressed: _sendInstantText,
                      child: Text(
                        'Type on Mac',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // macOS Pro Shortcut Ribbon
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final sc in const [
                    (label: '⌘Space', combo: 'cmd+space'),
                    (label: '⌘Tab', combo: 'cmd+tab'),
                    (label: '⌘C', combo: 'cmd+c'),
                    (label: '⌘V', combo: 'cmd+v'),
                    (label: '⌘Z', combo: 'cmd+z'),
                    (label: '⌘S', combo: 'cmd+s'),
                    (label: '⌘A', combo: 'cmd+a'),
                  ])
                    _CompactKeyCap(
                      label: sc.label,
                      onTap: () => notifier.dispatchDirectMacCommand(
                        'key_combination',
                        payload: {'combo': sc.combo},
                        logCategory: 'keyboard',
                        logSummary: 'Shortcut ${sc.label}',
                      ),
                    ),
                  for (final k in const [
                    (label: 'Esc', key: 'escape'),
                    (label: 'Tab', key: 'tab'),
                    (label: '⌫', key: 'backspace'),
                    (label: 'Return', key: 'enter'),
                    (label: '←', key: 'left'),
                    (label: '↑', key: 'up'),
                    (label: '↓', key: 'down'),
                    (label: '→', key: 'right'),
                  ])
                    _CompactKeyCap(
                      label: k.label,
                      onTap: () => notifier.dispatchDirectMacCommand(
                        'key_tap',
                        payload: {'key': k.key},
                        logCategory: 'keyboard',
                        logSummary: 'Key ${k.label}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // System & Quick Launch Bar
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _CompactKeyCap(
                    label: 'Mute',
                    icon: Icons.volume_off_rounded,
                    onTap: () => notifier.dispatchDirectMacCommand(
                      'system_control',
                      payload: const {'action': 'mute_toggle'},
                      logCategory: 'system',
                      logSummary: 'Toggled Mac audio mute',
                    ),
                  ),
                  _CompactKeyCap(
                    label: 'Play/Pause',
                    icon: Icons.play_arrow_rounded,
                    onTap: () => notifier.dispatchDirectMacCommand(
                      'system_control',
                      payload: const {'action': 'media_play_pause'},
                      logCategory: 'system',
                      logSummary: 'Media Play/Pause',
                    ),
                  ),
                  _CompactKeyCap(
                    label: 'Screenshot',
                    icon: Icons.camera_alt_outlined,
                    onTap: () => notifier.dispatchDirectMacCommand(
                      'system_control',
                      payload: const {'action': 'screenshot_to_desktop'},
                      logCategory: 'system',
                      logSummary: 'Saved Mac screenshot to Desktop',
                    ),
                  ),
                  _CompactKeyCap(
                    label: 'Finder',
                    icon: Icons.folder_open_rounded,
                    onTap: () => notifier.dispatchDirectMacCommand(
                      'open_mac_app',
                      payload: const {'appName': 'Finder'},
                      logCategory: 'system',
                      logSummary: 'Focused Finder',
                    ),
                  ),
                  _CompactKeyCap(
                    label: 'Safari',
                    icon: Icons.public_rounded,
                    onTap: () => notifier.dispatchDirectMacCommand(
                      'open_mac_app',
                      payload: const {'appName': 'Safari'},
                      logCategory: 'system',
                      logSummary: 'Focused Safari',
                    ),
                  ),
                  _CompactKeyCap(
                    label: 'Wake',
                    icon: Icons.wb_sunny_outlined,
                    onTap: () => notifier.dispatchDirectMacCommand(
                      'system_control',
                      payload: const {'action': 'wake_display'},
                      logCategory: 'system',
                      logSummary: 'Woke Mac display',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Live Incoming Action & NLP Telemetry Feed
        if (state.recentActions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'LIVE INPUT, VOICE & AGENT TELEMETRY STREAM',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              children: [
                for (final evt in state.recentActions.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          evt.icon,
                          size: 13.5,
                          color: evt.category == 'wispr'
                              ? AppColors.brandPink
                              : AppColors.brandBlue,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            evt.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          evt.origin.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MacroActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _MacroActionChip({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: busy ? null : onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5, color: AppColors.brandBlue),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTextAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniTextAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckKeyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool highlighted;
  final VoidCallback onTap;

  const _DeckKeyButton({
    required this.label,
    required this.icon,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.brandPink.withValues(alpha: 0.14)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: highlighted ? AppColors.brandPink : context.border,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13.5,
              color: highlighted ? AppColors.brandPink : context.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: highlighted ? AppColors.brandPink : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactKeyCap extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _CompactKeyCap({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12.5, color: AppColors.brandBlue),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

