import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared/theme/app_theme.dart';
import '../backend/voice_assistant_service.dart';
import '../auth/auth_repository.dart';

class VoiceAssistantOverlay extends ConsumerStatefulWidget {
  const VoiceAssistantOverlay({super.key});

  @override
  ConsumerState<VoiceAssistantOverlay> createState() => _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends ConsumerState<VoiceAssistantOverlay> {
  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceAssistantProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F13) : const Color(0xFFF0F0F5);
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      color: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down, color: textColor, size: 32),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  IconButton(
                    icon: Icon(Icons.settings, color: textColor, size: 28),
                    onPressed: _showSettings,
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Text Display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                voiceState.currentText.isEmpty 
                    ? (voiceState.state == VoiceState.listening ? "Listening..." : "Mpepe Voice")
                    : voiceState.currentText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),

            const Spacer(),

            // Orb Animation
            GestureDetector(
              onTap: () {
                if (voiceState.state == VoiceState.idle) {
                  ref.read(voiceAssistantProvider.notifier).startListening();
                } else {
                  ref.read(voiceAssistantProvider.notifier).stopListening();
                  ref.read(voiceAssistantProvider.notifier).stopSpeaking();
                }
              },
              child: _buildOrb(voiceState),
            ),

            const Spacer(),

            // Bottom Actions
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.add, color: textColor),
                      onPressed: () {
                        // Handle attachments if needed in voice mode
                      },
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () {
                        ref.read(voiceAssistantProvider.notifier).stopListening();
                        ref.read(voiceAssistantProvider.notifier).stopSpeaking();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrb(VoiceAssistantState state) {
    bool isListening = state.state == VoiceState.listening;
    bool isSpeaking = state.state == VoiceState.speaking;
    bool isProcessing = state.state == VoiceState.processing;

    double baseSize = 120.0;
    
    // Normalize sound level from -30..30 to 0.0..1.0 approximately
    double normalizedLevel = ((state.soundLevel.clamp(-30.0, 30.0) + 30.0) / 60.0);
    double dynamicScale = isListening ? (1.0 + (normalizedLevel * 0.5)) : 1.0;
    
    List<Widget> ripples = [];
    
    if (isListening || isSpeaking || isProcessing) {
      int count = isSpeaking ? 4 : (isListening ? 3 : 2);
      int duration = isSpeaking ? 800 : (isListening ? 1200 : 2000);
      
      for (int i = 0; i < count; i++) {
        ripples.add(
          Container(
            width: baseSize,
            height: baseSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.mpepeMaroon.withValues(alpha: 0.2),
            ),
          ).animate(onPlay: (controller) => controller.repeat())
           .scaleXY(begin: 1.0, end: isSpeaking ? 2.5 : (1.8 * dynamicScale), duration: duration.ms, curve: Curves.easeOut, delay: (i * (duration / count)).ms)
           .fadeOut(duration: duration.ms, curve: Curves.easeOut)
        );
      }
    }

    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...ripples,
          Container(
            width: baseSize,
            height: baseSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.mpepeMaroon.withValues(alpha: 0.8),
                  AppColors.mpepeMaroon,
                ]
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.mpepeMaroon.withValues(alpha: 0.5),
                  blurRadius: isSpeaking ? 40 : 20,
                  spreadRadius: isSpeaking ? 10 : 0,
                )
              ]
            ),
          ).animate(target: (isListening || isSpeaking) ? 1 : 0)
           .scaleXY(end: isListening ? (1.1 * dynamicScale) : 1.1, duration: isListening ? 100.ms : 600.ms, curve: Curves.easeInOut)
           .then(delay: 0.ms)
           .scaleXY(end: 1.0, duration: 600.ms, curve: Curves.easeInOut),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _VoiceSettingsSheet();
      },
    );
  }
}

class _VoiceSettingsSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VoiceSettingsSheet> createState() => _VoiceSettingsSheetState();
}

class _VoiceSettingsSheetState extends ConsumerState<_VoiceSettingsSheet> {
  List<Map<String, String>> _voices = [];
  String? _selectedVoice;
  String _selectedModel = 'anthropic/claude-3.5-sonnet';

  final List<String> _models = [
    'anthropic/claude-3.5-sonnet',
    'openai/gpt-4o',
    'google/gemini-1.5-pro',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final voices = await ref.read(voiceAssistantProvider.notifier).getAvailableVoices();
    final settings = await ref.read(authRepositoryProvider).getUserSettings();
    
    setState(() {
      _voices = voices;
      _selectedVoice = settings['selectedVoice'] ?? (voices.isNotEmpty ? voices.first['name'] : null);
      _selectedModel = settings['selectedModel'] ?? 'anthropic/claude-3.5-sonnet';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Voice Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          const Text("AI Model", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            items: _models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedModel = val);
                ref.read(authRepositoryProvider).saveUserSettings(selectedModel: val);
              }
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          const Text("System Voice", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_voices.isEmpty)
            const CircularProgressIndicator()
          else
            DropdownButtonFormField<String>(
              value: _selectedVoice,
              items: _voices.map((v) => DropdownMenuItem(value: v['name'], child: Text(v['name']!))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedVoice = val);
                  final voice = _voices.firstWhere((v) => v['name'] == val);
                  ref.read(voiceAssistantProvider.notifier).setVoice(voice);
                  ref.read(authRepositoryProvider).saveUserSettings(selectedVoice: val);
                }
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
