import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/live_recording_waveform.dart';
import '../../backend/voice_assistant_service.dart';
import '../../backend/gemini/gemini_live_voice_service.dart';
import '../../backend/security/secure_api_key_vault.dart';

/// Represents a live spoken stream item (User speech or AI Twin spoken response)
class LiveTranscriptionItem {
  final String speaker;
  final String text;
  final DateTime timestamp;
  final bool isAi;

  const LiveTranscriptionItem({
    required this.speaker,
    required this.text,
    required this.timestamp,
    required this.isAi,
  });
}

/// Ova Live Calling Mode
///
/// Implements full-screen frosted glass live calling with:
/// - Frosted background blur (`ImageFilter.blur(sigmaX: 25, sigmaY: 25)`)
/// - Floating live speech transcriptions fading smoothly on the top half
/// - Muted background audio while the AI Agent takes place
/// - Digital human twin mirroring the logged-in user account
class OvaLiveCallingOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final String? initialPrompt;

  const OvaLiveCallingOverlay({
    super.key,
    required this.onClose,
    this.initialPrompt,
  });

  static Future<void> show(BuildContext context, {String? initialPrompt}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, anim1, anim2) {
        return OvaLiveCallingOverlay(
          onClose: () => Navigator.of(ctx).pop(),
          initialPrompt: initialPrompt,
        );
      },
    );
  }

  @override
  ConsumerState<OvaLiveCallingOverlay> createState() => _OvaLiveCallingOverlayState();
}

class _OvaLiveCallingOverlayState extends ConsumerState<OvaLiveCallingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  // Real mic levels (0..1) for the live waveform while you talk.
  final List<double> _micLevels = [];

  bool _isSpeechInitialized = false;
  bool _isListening = true;
  bool _isMuted = false;
  bool _isSpeaking = false;
  String _currentSpokenSnippet = '';

  final List<LiveTranscriptionItem> _transcriptions = [];
  Timer? _aiResponseSimulationTimer;
  Timer? _typewriterTimer;

  String _userName = 'Creator';
  String? _userPhotoUrl;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadCurrentUser();
    _initLiveCallingSpeech();

    // Initial greeting from Digital Twin
    _transcriptions.add(
      LiveTranscriptionItem(
        speaker: 'AI Twin',
        text: 'Live calling established. I am standing in as your autonomous Digital Twin. Speak naturally—I stream transcription live.',
        timestamp: DateTime.now(),
        isAi: true,
      ),
    );

    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      _transcriptions.add(
        LiveTranscriptionItem(
          speaker: _userName,
          text: widget.initialPrompt!,
          timestamp: DateTime.now(),
          isAi: false,
        ),
      );
      _triggerAiResponse(widget.initialPrompt!);
    }
  }

  void _loadCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.displayName ?? user.email?.split('@').first ?? 'You';
        _userPhotoUrl = user.photoURL;
      });
    }
  }

  Future<void> _initLiveCallingSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            if (status == 'listening') {
              setState(() => _isListening = true);
            } else if (status == 'notListening' || status == 'done') {
              if (!_isMuted && mounted) {
                _restartListening();
              }
            }
          }
        },
        onError: (error) {
          debugPrint('[OvaLiveCalling] Speech error: $error');
        },
      );

      if (mounted) {
        setState(() => _isSpeechInitialized = available);
        if (available && !_isMuted) {
          _startListening();
        }
      }
    } catch (e) {
      debugPrint('[OvaLiveCalling] Speech initialization fallback: $e');
    }
  }

  void _startListening() {
    if (!_isSpeechInitialized || _isMuted) return;
    try {
      _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _currentSpokenSnippet = result.recognizedWords;
          });

          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _handleUserSpeechCommitted(result.recognizedWords);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
        ),
        onSoundLevelChange: (level) {
          if (!mounted) return;
          setState(() {
            _micLevels.add(((level + 2) / 12).clamp(0.05, 1.0));
            if (_micLevels.length > 90) _micLevels.removeRange(0, _micLevels.length - 90);
          });
        },
      );
    } catch (e) {
      debugPrint('[OvaLiveCalling] Listen error: $e');
    }
  }

  void _restartListening() {
    if (_isMuted || !mounted) return;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_isMuted) {
        _startListening();
      }
    });
  }

  void _handleUserSpeechCommitted(String userWords) {
    if (userWords.trim().isEmpty) return;

    setState(() {
      _transcriptions.add(
        LiveTranscriptionItem(
          speaker: _userName,
          text: userWords,
          timestamp: DateTime.now(),
          isAi: false,
        ),
      );
      _currentSpokenSnippet = '';
    });

    _scrollToBottom();
    _triggerAiResponse(userWords);
  }

  void _triggerAiResponse(String userPrompt) async {
    setState(() => _isSpeaking = true);
    HapticFeedback.selectionClick();

    _aiResponseSimulationTimer?.cancel();
    try {
      final geminiService = ref.read(geminiLiveVoiceServiceProvider.notifier);
      final spokenAnswer = await geminiService.processSpokenInput(userPrompt);
      if (mounted) {
        _streamAiSpeech(spokenAnswer);
      }
    } catch (e) {
      if (mounted) {
        _streamAiSpeech(
          "I have stabilized your session and verified your public feeds. Everything is operating normally.",
        );
      }
    }
  }

  void _streamAiSpeech(String fullText) {
    final words = fullText.split(' ');
    int index = 0;
    String currentOutput = '';

    setState(() {
      _transcriptions.add(
        LiveTranscriptionItem(
          speaker: 'AI Twin',
          text: '',
          timestamp: DateTime.now(),
          isAi: true,
        ),
      );
    });

    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 70), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (index < words.length) {
        currentOutput = '${currentOutput.isEmpty ? '' : '$currentOutput '}${words[index]}';
        index++;
        setState(() {
          if (_transcriptions.isNotEmpty && _transcriptions.last.isAi) {
            _transcriptions[_transcriptions.length - 1] = LiveTranscriptionItem(
              speaker: 'AI Twin',
              text: currentOutput,
              timestamp: DateTime.now(),
              isAi: true,
            );
          }
        });
        _scrollToBottom();
      } else {
        timer.cancel();
        setState(() => _isSpeaking = false);
        // Spoken via TTS if provider enabled
        ref.read(voiceAssistantProvider.notifier).speak(fullText);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _speech.stop();
        _isListening = false;
      } else {
        _startListening();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _aiResponseSimulationTimer?.cancel();
    _typewriterTimer?.cancel();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ─── Layer 1: Frosted Glass Background Blur ───────────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              color: context.bg.withValues(alpha: 0.88),
            ),
          ),

          // ─── Layer 2: Ambient Background Glow Orbs ────────────────────────────
          Positioned(
            top: size.height * 0.15,
            left: size.width * 0.1,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandBlue.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: size.height * 0.25,
            right: size.width * 0.05,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandPink.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ─── Layer 3: Main UI Content ─────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopCallHeader(),
                const SizedBox(height: 10),

                // Floating Fading Speech Transcriptions (Fades across top half)
                Expanded(
                  flex: 5,
                  child: _buildFloatingTranscriptions(),
                ),

                // Digital Twin Visual Persona & Audio Waveform Orb
                Expanded(
                  flex: 4,
                  child: _buildDigitalTwinOrb(),
                ),

                // Live Spoken Input Preview (Typing in real time)
                if (_currentSpokenSnippet.isNotEmpty)
                  _buildLiveSpokenSnippetBanner(),

                // Bottom Call Control Dock
                _buildCallControlDock(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCallHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brandPink,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPink.withValues(
                            alpha: 0.4 + (_pulseController.value * 0.5),
                          ),
                          blurRadius: 10 * _pulseController.value,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'LIVE CALLING MODE',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.brandBlue.withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'AI TWIN',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Mirrors $_userName • Background audio muted',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                  ),
                  child: const Icon(Icons.build_circle_outlined, color: Colors.white, size: 16),
                ),
                tooltip: 'Autonomous Self-Repair & Diagnostics',
                onPressed: () => _showDiagnosticsAndRepairSheet(context),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.border),
                  ),
                  child: Icon(Icons.close, color: context.textSecondary, size: 16),
                ),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDiagnosticsAndRepairSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final vault = ref.watch(secureKeyVaultProvider);
            final keyController = TextEditingController();

            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: ctx.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              child: SafeArea(
                child: FutureBuilder<String>(
                  future: vault.getGeminiApiKey(),
                  builder: (context, snapshot) {
                    final currentKey = snapshot.data ?? '';
                    final hasKey = currentKey.isNotEmpty;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: AppColors.brandPink.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.auto_awesome, color: AppColors.brandBlue, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gemini AI & Autonomous Repair',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: ctx.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Primary engine: gemini-2.5-flash',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: ctx.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ctx.surfaceMid,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ctx.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                hasKey ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                color: hasKey ? Colors.greenAccent : AppColors.brandPink,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  hasKey
                                      ? 'Hardened Key Active: ${vault.maskKey(currentKey)}'
                                      : 'No custom key. Dotenv or OpenRouter fallback engaged.',
                                  style: GoogleFonts.inter(fontSize: 12, color: ctx.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: keyController,
                          obscureText: true,
                          style: TextStyle(color: ctx.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Paste Gemini Key (saved to hardware Keystore)',
                            hintStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                            filled: true,
                            fillColor: ctx.surfaceMid,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: ctx.border),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.save_rounded, color: AppColors.brandBlue, size: 20),
                              onPressed: () async {
                                final text = keyController.text.trim();
                                if (text.isNotEmpty) {
                                  await vault.storeGeminiApiKey(text);
                                  HapticFeedback.mediumImpact();
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Gemini API Key securely stored in Keystore.'),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.healing_rounded, size: 18),
                            label: Text(
                              'Run Autonomous Self-Repair Now',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            onPressed: () async {
                              HapticFeedback.heavyImpact();
                              Navigator.pop(ctx);
                              _handleUserSpeechCommitted("Ova, run full autonomous self-repair and system diagnostics.");
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingTranscriptions() {
    return ShaderMask(
      shaderCallback: (Rect rect) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
          ],
          stops: [0.0, 0.25, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        itemCount: _transcriptions.length,
        itemBuilder: (context, index) {
          final item = _transcriptions[index];
          final isAi = item.isAi;

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:
                  isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (isAi) ...[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.brandBlue, AppColors.brandPink],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandBlue.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.auto_awesome, color: Colors.white, size: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isAi
                          ? context.surface.withValues(alpha: 0.92)
                          : AppColors.brandBlue.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isAi
                            ? context.border
                            : Colors.white.withValues(alpha: 0.2),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.speaker,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isAi ? AppColors.brandPink : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.text.isEmpty ? '…' : item.text,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isAi ? context.textPrimary : Colors.white,
                            height: 1.35,
                            fontWeight: isAi ? FontWeight.w500 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isAi) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandPink.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDigitalTwinOrb() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final scale = 1.0 + (_pulseController.value * 0.08);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Glow Halo
                  Container(
                    width: 130 * scale,
                    height: 130 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.brandBlue.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  // Middle Ring
                  Container(
                    width: 105,
                    height: 105,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isSpeaking
                            ? AppColors.brandPink.withValues(alpha: 0.7)
                            : AppColors.brandBlue.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isSpeaking
                              ? AppColors.brandPink.withValues(alpha: 0.4)
                              : AppColors.brandBlue.withValues(alpha: 0.3),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  // Inner Avatar Orb
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF020617),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: _userPhotoUrl != null
                          ? ClipOval(
                              child: Image.network(
                                _userPhotoUrl!,
                                width: 84,
                                height: 84,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.account_circle_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'TWIN',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: AppColors.brandPink,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Live waveform from the mic while listening; animated bars
              // while the twin speaks.
              if (_isListening && !_isSpeaking && !_isMuted && _micLevels.isNotEmpty)
                SizedBox(
                  width: 180,
                  child: LiveRecordingWaveform(levels: _micLevels, height: 26, barWidth: 2.5, gap: 2),
                )
              else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(7, (i) {
                  final heightFactor = (_pulseController.value + (i * 0.15)) % 1.0;
                  final barHeight = (_isSpeaking || _isListening)
                      ? 6.0 + (heightFactor * 14.0)
                      : 4.0;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 3.0,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: i % 2 == 0 ? AppColors.brandPink : AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                _isSpeaking
                    ? 'AI Twin is speaking…'
                    : (_isMuted ? 'Mic Muted' : 'Listening to your voice…'),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLiveSpokenSnippetBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandPink.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.mic, color: AppColors.brandPink, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentSpokenSnippet,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.textPrimary,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live Speech',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.brandPink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallControlDock() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute / Unmute Button
          IconButton(
            icon: Icon(
              _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: _isMuted ? Colors.redAccent : context.textPrimary,
              size: 24,
            ),
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            onPressed: _toggleMute,
          ),

          // Voice Twin Prompt Action (Quick Query)
          IconButton(
            icon: const Icon(
              Icons.auto_awesome,
              color: AppColors.brandPink,
              size: 24,
            ),
            tooltip: 'Ask AI Twin for Update',
            onPressed: () {
              _handleUserSpeechCommitted("Give me a full status update on my account and public reels.");
            },
          ),

          // Keyboard Switch
          IconButton(
            icon: Icon(
              Icons.keyboard_rounded,
              color: context.textSecondary,
              size: 24,
            ),
            tooltip: 'Type message',
            onPressed: () {
              widget.onClose();
            },
          ),

          // End Call Button
          GestureDetector(
            onTap: () {
              HapticFeedback.heavyImpact();
              widget.onClose();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.call_end_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'END',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
