import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../agent_workspace/ova_agent_models.dart';
import '../../agent_workspace/ova_agent_sync_controller.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/audio/ova_vertex_audio_engine.dart';
import '../../shared/audio/speech_hub.dart';
import '../../shared/theme/app_theme.dart';

/// Ova, docked inside Online Control: chat or talk to Ova and it works the
/// connected computer (apps, Terminal, files, web, mouse and keys) while the
/// live screen stays visible above.
///
/// Uses the shared account agent session, so the same conversation shows on
/// the computer. Voice mode is a hands-free loop: listen → send → read the
/// reply aloud → listen again, through the app-wide mic coordinator.
class OvaLiveCopilot extends ConsumerStatefulWidget {
  const OvaLiveCopilot({
    super.key,
    required this.computerName,
    this.activeWindow,
    this.docked = false,
    required this.onClose,
  });

  /// Landscape: full-height side panel instead of a bottom sheet.
  final bool docked;
  final String computerName;
  final String? activeWindow;
  final VoidCallback onClose;

  @override
  ConsumerState<OvaLiveCopilot> createState() => _OvaLiveCopilotState();
}

enum _VoicePhase { off, listening, waiting, speaking }

class _OvaLiveCopilotState extends ConsumerState<OvaLiveCopilot> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final SpeechHub _speech = SpeechHub.instance;

  bool _expanded = false;
  bool _voiceMode = false;
  _VoicePhase _phase = _VoicePhase.off;
  bool _dictating = false;
  String _heard = '';
  MicLease? _lease;
  String? _awaitingReplyAfterTurnId;
  String? _lastSpokenTurnId;

  static const _suggestions = [
    "What's on my screen right now?",
    'Open Safari and search for today’s news',
    'Tidy up my Desktop into folders',
    'How much storage do I have left?',
  ];

  @override
  void dispose() {
    unawaited(_stopMic());
    unawaited(OvaVertexAudioEngine.instance.stop());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Sending ──────────────────────────────────────────────────────────────

  Future<void> _send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty) return;
    HapticFeedback.lightImpact();
    _input.clear();
    final turns = ref.read(ovaAgentSyncProvider).turns;
    _awaitingReplyAfterTurnId = turns.isNotEmpty ? turns.last.id : '';
    await ref.read(ovaAgentSyncProvider.notifier).sendPrompt(
          prompt,
          contextChips: [
            'Online Control',
            widget.computerName,
            if (widget.activeWindow != null && widget.activeWindow!.isNotEmpty)
              'Window: ${widget.activeWindow}',
          ],
          screenContextLabel:
              'The user is watching ${widget.computerName} live from their phone and wants it done there.',
        );
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // ── Microphone (dictation and voice mode) ───────────────────────────────

  Future<bool> _startMic() async {
    final got = await MicCoordinator.instance.acquire(
      MicUser.assistant,
      onPreempted: () async {
        await _speech.cancel(this);
        _lease = null;
        if (mounted) {
          setState(() {
            _dictating = false;
            _voiceMode = false;
            _phase = _VoicePhase.off;
          });
        }
      },
    );
    if (got is MicBusy) {
      _toast(got.message);
      return false;
    }
    _lease = got as MicLease;
    await OvaVertexAudioEngine.instance.stop();
    setState(() => _heard = '');
    final ok = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult) unawaited(_finishHearing());
      },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') unawaited(_finishHearing());
      },
      onError: (_) => unawaited(_finishHearing()),
    );
    if (!ok) {
      await _stopMic();
      _toast('Microphone is not available right now.');
    }
    return ok;
  }

  Future<void> _stopMic() async {
    await _speech.stop(this);
    await _lease?.release();
    _lease = null;
  }

  bool _finishing = false;
  Future<void> _finishHearing() async {
    if (_finishing) return;
    if (!_dictating && _phase != _VoicePhase.listening) return;
    _finishing = true;
    try {
      await _stopMic();
      final words = _heard.trim();
      if (!mounted) return;
      if (_dictating) {
        setState(() => _dictating = false);
        if (words.isNotEmpty) {
          _input.text = words;
          _input.selection = TextSelection.collapsed(offset: words.length);
        }
        return;
      }
      if (words.isEmpty) {
        // Nothing heard: keep the loop alive with a fresh listen.
        if (_voiceMode) await _listenForVoiceMode();
        return;
      }
      setState(() => _phase = _VoicePhase.waiting);
      await _send(words);
    } finally {
      _finishing = false;
    }
  }

  Future<void> _toggleDictation() async {
    if (_voiceMode) return;
    if (_dictating) {
      await _finishHearing();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _dictating = true);
    if (!await _startMic() && mounted) setState(() => _dictating = false);
  }

  Future<void> _toggleVoiceMode() async {
    HapticFeedback.mediumImpact();
    if (_voiceMode) {
      setState(() {
        _voiceMode = false;
        _phase = _VoicePhase.off;
      });
      await _stopMic();
      await OvaVertexAudioEngine.instance.stop();
      return;
    }
    setState(() {
      _voiceMode = true;
      _dictating = false;
    });
    await _listenForVoiceMode();
  }

  Future<void> _listenForVoiceMode() async {
    if (!_voiceMode || !mounted) return;
    setState(() => _phase = _VoicePhase.listening);
    if (!await _startMic() && mounted) {
      setState(() {
        _voiceMode = false;
        _phase = _VoicePhase.off;
      });
    }
  }

  void _maybeSpeakReply(List<OvaAgentTurn> turns) {
    if (!_voiceMode || _phase != _VoicePhase.waiting || turns.isEmpty) return;
    final last = turns.last;
    if (last.role != 'assistant' || last.id == _lastSpokenTurnId) return;
    if (last.id == _awaitingReplyAfterTurnId) return;
    if (last.status == 'awaiting_approval') {
      _lastSpokenTurnId = last.id;
      _speak('I need your OK on the screen before I do that.');
      return;
    }
    if (last.status != 'completed' && last.status != 'error') return;
    _lastSpokenTurnId = last.id;
    final text = plainReply(last.text);
    _speak(text.isEmpty ? 'Done.' : text);
  }

  void _speak(String text) {
    setState(() => _phase = _VoicePhase.speaking);
    final clipped = text.length > 600 ? '${text.substring(0, 600)}…' : text;
    unawaited(
      OvaVertexAudioEngine.instance.speak(
        clipped,
        onComplete: _onSpeechDone,
      ),
    );
  }

  void _onSpeechDone() {
    if (!mounted || !_voiceMode) return;
    unawaited(_listenForVoiceMode());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(ovaAgentSyncProvider);
    final turns = agent.turns;
    ref.listen(ovaAgentSyncProvider.select((s) => s.turns.length), (_, _) => _scrollToEnd());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSpeakReply(turns));

    final screenH = MediaQuery.sizeOf(context).height;
    final height = screenH * (_expanded ? 0.72 : 0.42);
    final busy = agent.sending ||
        (turns.isNotEmpty &&
            turns.last.role == 'assistant' &&
            const {'thinking', 'running_tools', 'synthesizing'}.contains(turns.last.status));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: widget.docked ? null : height,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: widget.docked
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(22)),
        border: widget.docked
            ? Border.symmetric(vertical: BorderSide(color: context.border))
            : Border(top: BorderSide(color: context.border)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: Column(
        children: [
          if (widget.docked)
            SizedBox(height: MediaQuery.paddingOf(context).top + 8)
          else
            _handle(),
          _header(busy, agent),
          Expanded(
            child: _voiceMode
                ? _voiceStage(busy)
                : (turns.isEmpty ? _emptyState() : _conversation(turns)),
          ),
          if (!_voiceMode) _composer(busy),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  Widget _handle() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) setState(() => _expanded = true);
          if (v > 200) {
            if (_expanded) {
              setState(() => _expanded = false);
            } else {
              widget.onClose();
            }
          }
        },
        child: SizedBox(
          height: 18,
          child: Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.textMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );

  Widget _header(bool busy, OvaAgentWorkspaceState agent) {
    final status = _voiceMode
        ? switch (_phase) {
            _VoicePhase.listening => 'Listening…',
            _VoicePhase.waiting => 'On it…',
            _VoicePhase.speaking => 'Talking',
            _VoicePhase.off => 'Voice mode',
          }
        : busy
            ? 'Working on ${widget.computerName}…'
            : 'Ready to help on ${widget.computerName}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ova',
                    style: GoogleFonts.inter(
                        fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
                Text(status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
              ],
            ),
          ),
          if (busy && !_voiceMode)
            IconButton(
              tooltip: 'Stop',
              onPressed: () => ref.read(ovaAgentSyncProvider.notifier).stopCurrentTurn(),
              icon: Icon(Icons.stop_circle_outlined, color: context.textSecondary),
            ),
          _pillButton(
            icon: _voiceMode ? Icons.chat_bubble_outline_rounded : Icons.graphic_eq_rounded,
            label: _voiceMode ? 'Chat' : 'Voice',
            highlighted: _voiceMode,
            onTap: _toggleVoiceMode,
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: widget.onClose,
            icon: Icon(Icons.close_rounded, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: highlighted ? AppColors.brandPink.withValues(alpha: 0.16) : context.surfaceMid,
          border: Border.all(color: highlighted ? AppColors.brandPink : context.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: highlighted ? AppColors.brandPink : context.textPrimary),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Text(
          'Tell me what you want done on ${widget.computerName} — in your own words. '
          'I can open apps, find files, run commands, search the web and more.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: context.textSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              ActionChip(
                label: Text(s, style: GoogleFonts.inter(fontSize: 12.5)),
                onPressed: () => _send(s),
                backgroundColor: context.surfaceMid,
                side: BorderSide(color: context.border),
              ),
          ],
        ),
      ],
    );
  }

  Widget _conversation(List<OvaAgentTurn> turns) {
    final recent = turns.length > 30 ? turns.sublist(turns.length - 30) : turns;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: recent.length,
      itemBuilder: (_, i) => _turn(recent[i]),
    );
  }

  Widget _turn(OvaAgentTurn t) {
    final mine = t.role == 'user';
    if (mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 8, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.brandBlue,
            borderRadius: BorderRadius.circular(16).copyWith(bottomRight: const Radius.circular(4)),
          ),
          child: Text(t.text,
              style: GoogleFonts.inter(fontSize: 14, height: 1.35, color: Colors.white)),
        ),
      );
    }

    final working = const {'thinking', 'running_tools', 'synthesizing'}.contains(t.status);
    final reply = plainReply(t.text);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8, right: 36),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(16).copyWith(bottomLeft: const Radius.circular(4)),
          border: Border.all(color: context.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in t.toolCalls) _toolRow(t, c),
            if (t.toolCalls.isNotEmpty && (reply.isNotEmpty || working)) const SizedBox(height: 6),
            if (reply.isNotEmpty)
              SelectableText(reply,
                  style: GoogleFonts.inter(fontSize: 14, height: 1.4, color: context.textPrimary))
            else if (working)
              _typingDots()
            else if (t.status == 'error')
              Text("Sorry — that didn't work. Want me to try again?",
                  style: GoogleFonts.inter(fontSize: 14, color: context.textPrimary)),
            if (t.followUps.isNotEmpty && t.status == 'completed') ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in t.followUps.take(3))
                  GestureDetector(
                    onTap: () => _send(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                      ),
                      child: Text(f,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: context.textPrimary, fontWeight: FontWeight.w500)),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolRow(OvaAgentTurn turn, OvaAgentToolCall c) {
    final (icon, color) = switch (c.status) {
      OvaToolCallStatus.completed => (Icons.check_circle_rounded, const Color(0xFF2EBD6B)),
      OvaToolCallStatus.error => (Icons.error_outline_rounded, AppColors.brandPink),
      OvaToolCallStatus.denied => (Icons.block_rounded, context.textMuted),
      OvaToolCallStatus.awaitingApproval => (Icons.pan_tool_alt_rounded, const Color(0xFFF5A623)),
      _ => (Icons.autorenew_rounded, AppColors.brandBlue),
    };
    final title = c.title.isNotEmpty ? c.title : c.name.replaceAll('_', ' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary)),
            ),
          ]),
          if (c.status == OvaToolCallStatus.awaitingApproval)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 6),
              child: Row(children: [
                _approvalButton('Allow', true, turn, c),
                const SizedBox(width: 8),
                _approvalButton('Skip', false, turn, c),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _approvalButton(String label, bool approve, OvaAgentTurn turn, OvaAgentToolCall c) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final sessionId = ref.read(ovaAgentSyncProvider).activeSessionId;
        if (sessionId == null) return;
        ref.read(ovaAgentSyncProvider.notifier).decideToolApproval(
              sessionId: sessionId,
              turn: turn,
              toolCallId: c.id,
              approved: approve,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: approve ? AppColors.brandBlue : Colors.transparent,
          border: Border.all(color: approve ? AppColors.brandBlue : context.border),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: approve ? Colors.white : context.textPrimary)),
      ),
    );
  }

  Widget _typingDots() {
    return SizedBox(
      height: 18,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          _Dot(delayMs: i * 160, color: context.textMuted),
      ]),
    );
  }

  Widget _voiceStage(bool busy) {
    final words = _heard;
    final label = switch (_phase) {
      _VoicePhase.listening => words.isEmpty ? 'Go ahead, I’m listening' : words,
      _VoicePhase.waiting => words.isEmpty ? 'Working on it…' : '“$words”',
      _VoicePhase.speaking => _lastReplyText(),
      _VoicePhase.off => 'Tap the orb to talk',
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () {
            if (_phase == _VoicePhase.speaking) {
              unawaited(OvaVertexAudioEngine.instance.stop());
              _onSpeechDone();
            } else if (_phase == _VoicePhase.listening) {
              unawaited(_finishHearing());
            }
          },
          child: _VoiceOrb(active: _phase == _VoicePhase.listening, speaking: _phase == _VoicePhase.speaking),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 15, height: 1.4, color: context.textPrimary),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _phase == _VoicePhase.speaking ? 'Tap the orb to interrupt' : 'Tap the orb when you’re done',
          style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
        ),
      ],
    );
  }

  String _lastReplyText() {
    final turns = ref.read(ovaAgentSyncProvider).turns;
    for (final t in turns.reversed) {
      if (t.role == 'assistant') return plainReply(t.text);
    }
    return '';
  }

  Widget _composer(bool busy) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 14, right: 4),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _dictating ? AppColors.brandPink : context.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      style: GoogleFonts.inter(fontSize: 14.5, color: context.textPrimary),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: _dictating
                            ? (_heard.isEmpty ? 'Listening…' : _heard)
                            : 'Ask Ova to do something…',
                        hintStyle: GoogleFonts.inter(fontSize: 14, color: context.textMuted),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _dictating ? 'Stop dictation' : 'Dictate',
                    onPressed: _toggleDictation,
                    icon: Icon(
                      _dictating ? Icons.stop_rounded : Icons.mic_none_rounded,
                      color: _dictating ? AppColors.brandPink : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _input,
            builder: (_, v, _) {
              final canSend = v.text.trim().isNotEmpty && !busy;
              return GestureDetector(
                onTap: canSend ? () => _send(v.text) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canSend ? AppColors.brandBlue : context.surfaceMid,
                  ),
                  child: Icon(Icons.arrow_upward_rounded,
                      color: canSend ? Colors.white : context.textMuted),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Turns the agent's Markdown reply into plain, readable text.
String plainReply(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
  s = s.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
  s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'(?<!\w)\*([^*\n]+)\*(?!\w)'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delayMs, required this.color});
  final int delayMs;
  final Color color;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _VoiceOrb extends StatefulWidget {
  const _VoiceOrb({required this.active, required this.speaking});
  final bool active;
  final bool speaking;
  @override
  State<_VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<_VoiceOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.active ? AppColors.brandPink : AppColors.brandBlue;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final pulse = (widget.active || widget.speaking) ? _c.value : 0.15;
        return Container(
          width: 108 + pulse * 14,
          height: 108 + pulse * 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF2B6FD6), AppColors.brandBlue, Color(0xFF3A1458)],
              stops: [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.35 + pulse * 0.3),
                blurRadius: 30 + pulse * 20,
                spreadRadius: 2 + pulse * 6,
              ),
            ],
          ),
          child: Icon(
            widget.speaking ? Icons.volume_up_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: 40,
          ),
        );
      },
    );
  }
}
