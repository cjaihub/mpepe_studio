import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/gemini_live_service.dart';
import '../../shared/theme/app_theme.dart';

class LiveVoiceModeScreen extends ConsumerStatefulWidget {
  const LiveVoiceModeScreen({super.key});

  @override
  ConsumerState<LiveVoiceModeScreen> createState() => _LiveVoiceModeScreenState();
}

class _LiveVoiceModeScreenState extends ConsumerState<LiveVoiceModeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(geminiLiveProvider.notifier).connect();
    });
  }

  @override
  void deactivate() {
    ref.read(geminiLiveProvider.notifier).disconnect();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(geminiLiveProvider);
    final notifier = ref.read(geminiLiveProvider.notifier);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.textPrimary, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Ova Voice',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (liveState.currentError != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.brandPink,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        liveState.currentError!,
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.2),

            Expanded(
              child: _buildTranscript(liveState.transcript),
            ),
            
            _buildVisualizer(context, liveState.state),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: _buildControls(context, liveState, notifier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscript(List<String> transcript) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      reverse: true, // Show latest at the bottom by reversing
      itemCount: transcript.length,
      itemBuilder: (context, index) {
        // Reverse index
        final actualIndex = transcript.length - 1 - index;
        final text = transcript[actualIndex];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),
        );
      },
    );
  }

  Widget _buildVisualizer(BuildContext context, LiveVoiceState state) {
    String statusText;
    Color glowColor;
    bool isAnimating = true;

    switch (state) {
      case LiveVoiceState.listening:
        statusText = 'Listening...';
        glowColor = AppColors.brandPink;
        break;
      case LiveVoiceState.thinking:
        statusText = 'Thinking...';
        glowColor = AppColors.brandBlue;
        break;
      case LiveVoiceState.speaking:
        statusText = 'Speaking';
        glowColor = AppColors.brandBlue;
        break;
      case LiveVoiceState.interrupted:
        statusText = 'Interrupted';
        glowColor = AppColors.brandPink;
        isAnimating = false;
        break;
      case LiveVoiceState.reconnecting:
        statusText = 'Connecting...';
        glowColor = context.textSecondary;
        break;
      case LiveVoiceState.disconnected:
        statusText = 'Disconnected';
        glowColor = context.textMuted;
        isAnimating = false;
        break;
    }

    Widget visualizer = Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.surface,
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: isAnimating ? 0.45 : 0.15),
            blurRadius: isAnimating ? 40 : 10,
            spreadRadius: isAnimating ? 8 : 2,
          )
        ],
      ),
      child: Center(
        child: Icon(
          Icons.graphic_eq,
          color: glowColor,
          size: 64,
        ),
      ),
    );

    if (isAnimating) {
      visualizer = visualizer.animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1.seconds);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        visualizer,
        const SizedBox(height: 24),
        Text(
          statusText,
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, GeminiLiveState state, GeminiLiveService notifier) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlBtn(
          icon: state.isMuted ? Icons.mic_off : Icons.mic,
          isActive: state.isMuted,
          onTap: notifier.toggleMute,
        ),
        const SizedBox(width: 32),
        _ControlBtn(
          icon: Icons.call_end,
          isActive: true,
          activeColor: AppColors.brandPink,
          size: 64,
          onTap: () {
            notifier.disconnect();
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(width: 32),
        _ControlBtn(
          icon: Icons.stop_circle,
          isActive: state.state == LiveVoiceState.speaking,
          onTap: () {
            if (state.state == LiveVoiceState.speaking) {
              notifier.interrupt();
            }
          },
        ),
      ],
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final double size;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.isActive,
    this.activeColor,
    this.size = 56,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? AppColors.brandBlue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? effectiveActiveColor : context.surface,
          border: Border.all(
            color: isActive ? Colors.transparent : context.border,
            width: 1.0,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : context.textPrimary,
          size: size * 0.48,
        ),
      ),
    );
  }
}
