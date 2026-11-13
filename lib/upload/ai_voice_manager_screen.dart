import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../shared/audio/cloud_dictation.dart';
import '../shared/audio/mic_coordinator.dart';
import '../shared/audio/speech_hub.dart';
import '../shared/theme/app_theme.dart';
import 'models/omnichannel_upload_task.dart';
import 'services/ai_upload_assistant.dart';
import 'services/omnichannel_upload_engine.dart';

class AiVoiceManagerScreen extends ConsumerStatefulWidget {
  const AiVoiceManagerScreen({super.key});

  @override
  ConsumerState<AiVoiceManagerScreen> createState() => _AiVoiceManagerScreenState();
}

class _AiVoiceManagerScreenState extends ConsumerState<AiVoiceManagerScreen> {
  final SpeechHub _speech = SpeechHub.instance;
  MicLease? _micLease;
  CloudDictation? _cloud;
  bool _usingCloud = false;
  bool _isListening = false;
  String _transcript = '';
  String _aiResponse = "Hi! I'm your Upload Manager. What would you like me to do with your content today?";
  bool _isProcessing = false;

  @override
  void dispose() {
    unawaited(_speech.cancel(this));
    unawaited(_cloud?.dispose());
    unawaited(_micLease?.release());
    _micLease = null;
    super.dispose();
  }

  Future<void> _releaseMic() async {
    final lease = _micLease;
    _micLease = null;
    await lease?.release();
  }

  Future<void> _startListening() async {
    if (_isListening || _isProcessing) return;
    final perm = await Permission.microphone.request();
    if (!mounted) return;
    if (!perm.isGranted) {
      setState(() {
        _aiResponse = "I need microphone access to hear you. Please enable it in your device settings.";
      });
      return;
    }

    final got = await MicCoordinator.instance.acquire(
      MicUser.assistant,
      onPreempted: () async {
        _usingCloud = false;
        await _speech.cancel(this);
        await _cloud?.cancel();
        _micLease = null;
        if (mounted) setState(() => _isListening = false);
      },
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && _isListening && mounted) {
          unawaited(_stopListeningAndProcess());
        }
      },
    );
    if (got is MicBusy) {
      if (mounted) setState(() => _aiResponse = got.message);
      return;
    }
    _micLease = got as MicLease;
    if (!mounted) {
      await _releaseMic();
      return;
    }

    _usingCloud = false;
    setState(() {
      _isListening = true;
      _transcript = '';
      _aiResponse = 'Listening...';
    });

    final started = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onStatus: (status) {
        if (_usingCloud || !mounted) return;
        if ((status == 'done' || status == 'notListening' || status == 'preempted') && _isListening) {
          unawaited(_stopListeningAndProcess());
        }
      },
      onError: (error) {
        if (_usingCloud || !mounted || !_isListening) return;
        if (error.errorMsg == 'error_no_match' || error.errorMsg == 'error_speech_timeout') {
          unawaited(_stopListeningAndProcess());
        } else {
          unawaited(_startCloudFallback());
        }
      },
      onResult: (result) {
        if (_usingCloud || !mounted) return;
        setState(() {
          _transcript = result.recognizedWords;
        });
      },
    );

    if (!started && mounted && _isListening) {
      await _startCloudFallback();
    }
  }

  Future<void> _startCloudFallback() async {
    if (_usingCloud || !mounted || !_isListening) return;
    await _speech.cancel(this);
    _usingCloud = true;
    _cloud ??= CloudDictation();
    final ok = await _cloud!.start(
      autoStopOnSilence: true,
      onSilenceCommit: () => unawaited(_stopListeningAndProcess()),
    );
    if (!ok) {
      _usingCloud = false;
      await _releaseMic();
      if (mounted) {
        setState(() {
          _isListening = false;
          _isProcessing = false;
          _aiResponse = "Sorry, I couldn't start the microphone right now. Try again?";
        });
      }
    }
  }

  Future<void> _stopListeningAndProcess() async {
    if (!_isListening && !_usingCloud) return;
    final wasCloud = _usingCloud;
    _usingCloud = false;
    if (mounted) {
      setState(() {
        _isListening = false;
        _isProcessing = true;
        _aiResponse = "Processing your request...";
      });
    }

    await _speech.stop(this);
    if (wasCloud) {
      try {
        final text = (await _cloud?.stopAndTranscribe() ?? '').trim();
        if (text.isNotEmpty) _transcript = text;
      } catch (_) {}
    }
    await _releaseMic();
    if (!mounted) return;

    if (_transcript.trim().isNotEmpty) {
      final assistant = ref.read(aiUploadAssistantProvider);
      final intent = await assistant.processVoiceCommand(_transcript.trim());
      if (!mounted) return;

      setState(() {
        _aiResponse = intent.rawResponse;
        _isProcessing = false;
      });

      // If metadata was generated, apply it to the first pending upload task
      if (intent.type == AiIntentType.generateMetadata && intent.generatedMetadata.isNotEmpty) {
        final engine = ref.read(omnichannelUploadEngineProvider.notifier);
        final tasks = ref.read(omnichannelUploadEngineProvider);
        if (tasks.isNotEmpty) {
          final pendingTask = tasks.firstWhere((t) => t.status == UploadStatus.pending, orElse: () => tasks.first);

          engine.updateTaskMetadata(
            pendingTask.id,
            title: intent.generatedMetadata['title'],
            description: intent.generatedMetadata['description'],
            tags: List<String>.from(intent.generatedMetadata['tags'] ?? []),
          );
        }
      }
    } else {
      setState(() {
        _isProcessing = false;
        _aiResponse = "I didn't catch that. Tap the mic to try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // AI Avatar / Orb
                      Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening 
                              ? AppColors.brandBlue
                              : context.surface,
                          border: Border.all(
                            color: _isListening ? AppColors.brandBlue : context.border,
                            width: 2,
                          ),
                          boxShadow: [
                            if (_isListening) ...[
                              BoxShadow(
                                color: AppColors.brandBlue.withValues(alpha: 0.6),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                              BoxShadow(
                                color: AppColors.brandBlue.withValues(alpha: 0.3),
                                blurRadius: 100,
                                spreadRadius: 30,
                              ),
                            ] else
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                          ],
                        ),
                        child: Icon(
                          _isProcessing ? Icons.auto_awesome : Icons.graphic_eq,
                          size: 72,
                          color: _isListening || _isProcessing ? Colors.white : context.textMuted,
                        ).animate(target: (_isListening || _isProcessing) ? 1 : 0)
                         .scaleXY(end: 1.2, duration: 400.ms)
                         .shimmer(duration: 1.seconds, color: Colors.white54),
                      )
                      .animate(
                        target: _isListening ? 1 : 0,
                        onPlay: (controller) => _isListening ? controller.repeat(reverse: true) : controller.stop(),
                      )
                      .scaleXY(end: 1.15, duration: 800.ms, curve: Curves.easeInOutSine)
                      .then(delay: 0.ms)
                      .scaleXY(end: 1.0, duration: 800.ms, curve: Curves.easeInOutSine),
                      
                      const SizedBox(height: 48),

                      // User Transcript
                      if (_transcript.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            color: context.surfaceMid,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: context.border, width: 1),
                          ),
                          child: Text(
                            '"$_transcript"',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: context.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ).animate().fadeIn().slideY(begin: 0.2, end: 0),
                      
                      const SizedBox(height: 32),

                      // AI Response
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _aiResponse,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: context.textPrimary,
                            height: 1.3,
                            letterSpacing: -0.5,
                          ),
                        ).animate(key: ValueKey(_aiResponse)).fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
                      ),
                      
                      const SizedBox(height: 64),

                      // Mic Button
                      GestureDetector(
                        onTapDown: (_) => _startListening(),
                        onTapUp: (_) => _stopListeningAndProcess(),
                        onTapCancel: () => _stopListeningAndProcess(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isListening ? 100 : 88,
                          height: _isListening ? 100 : 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening ? AppColors.brandBlue : context.surfaceMid,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                            border: Border.all(
                              color: _isListening ? AppColors.brandBlue : context.border,
                              width: 2,
                            )
                          ),
                          child: Icon(
                            Icons.mic, 
                            size: _isListening ? 42 : 32, 
                            color: _isListening ? Colors.white : context.textSecondary
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Hold to speak',
                        style: TextStyle(color: context.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 16),
          Text(
            'Upload Manager AI',
            style: AppTheme.h1Style.copyWith(color: context.textPrimary),
          ),
        ],
      ),
    );
  }
}
