import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/studio_background.dart';
import 'models/omnichannel_upload_task.dart';
import 'services/ai_upload_assistant.dart';
import 'services/omnichannel_upload_engine.dart';

class AiVoiceManagerScreen extends ConsumerStatefulWidget {
  const AiVoiceManagerScreen({super.key});

  @override
  ConsumerState<AiVoiceManagerScreen> createState() => _AiVoiceManagerScreenState();
}

class _AiVoiceManagerScreenState extends ConsumerState<AiVoiceManagerScreen> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _transcript = '';
  String _aiResponse = "Hi! I'm your Upload Manager. What would you like me to do with your content today?";
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_isListening) {
             _stopListeningAndProcess();
          }
        }
      },
      onError: (error) {
        setState(() {
          _isListening = false;
          _isProcessing = false;
          _aiResponse = "Sorry, I couldn't hear that clearly. Try again?";
        });
      },
    );
  }

  void _startListening() async {
    if (await _speech.hasPermission) {
      setState(() {
        _isListening = true;
        _transcript = '';
        _aiResponse = 'Listening...';
      });
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _transcript = result.recognizedWords;
          });
        },
      );
    } else {
      setState(() {
        _aiResponse = "I need microphone access to hear you. Please enable it in your device settings.";
      });
    }
  }

  void _stopListeningAndProcess() async {
    setState(() {
      _isListening = false;
      _isProcessing = true;
      _aiResponse = "Processing your request...";
    });
    
    await _speech.stop();
    
    if (_transcript.isNotEmpty) {
      final assistant = ref.read(aiUploadAssistantProvider);
      final intent = await assistant.processVoiceCommand(_transcript);
      
      setState(() {
        _aiResponse = intent.rawResponse;
        _isProcessing = false;
      });

      // If metadata was generated, apply it to the first pending upload task
      if (intent.type == AiIntentType.generateMetadata && intent.generatedMetadata.isNotEmpty) {
        final engine = ref.read(omnichannelUploadEngineProvider.notifier);
        final tasks = ref.read(omnichannelUploadEngineProvider);
        final pendingTask = tasks.firstWhere((t) => t.status == UploadStatus.pending, orElse: () => tasks.first);
        
        engine.updateTaskMetadata(
          pendingTask.id,
          title: intent.generatedMetadata['title'],
          description: intent.generatedMetadata['description'],
          tags: List<String>.from(intent.generatedMetadata['tags'] ?? []),
        );
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
      backgroundColor: AppColors.darkBackground,
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
                              ? AppColors.mpepeMaroon
                              : AppColors.darkSurface,
                          border: Border.all(
                            color: _isListening ? AppColors.mpepeMaroon : Colors.white10,
                            width: 2,
                          ),
                          boxShadow: [
                            if (_isListening) ...[
                              BoxShadow(
                                color: AppColors.mpepeMaroon.withValues(alpha: 0.6),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                              BoxShadow(
                                color: AppColors.mpepeMaroon.withValues(alpha: 0.3),
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
                          color: _isListening || _isProcessing ? Colors.white : Colors.white38,
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
                            color: AppColors.darkSurfaceHighlight,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white12, width: 1),
                          ),
                          child: Text(
                            '"$_transcript"',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: AppColors.textPrimary,
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
                            color: Colors.white,
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
                            color: _isListening ? AppColors.mpepeMaroon : AppColors.darkSurfaceHighlight,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                            border: Border.all(
                              color: _isListening ? AppColors.mpepeMaroon : Colors.white24,
                              width: 2,
                            )
                          ),
                          child: Icon(
                            Icons.mic, 
                            size: _isListening ? 42 : 32, 
                            color: _isListening ? Colors.white : Colors.white70
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Hold to speak',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
            style: AppTheme.h1Style,
          ),
        ],
      ),
    );
  }
}
