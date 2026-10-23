import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/gemini_live_service.dart';
import '../../shared/theme/app_theme.dart';

class GeminiLiveOverlay extends ConsumerWidget {
  const GeminiLiveOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(geminiLiveProvider);
    final isBranded = sessionState.state != GeminiLiveState.disconnected && sessionState.state != GeminiLiveState.reconnecting;
    final fgColor = isBranded ? Colors.white : context.textPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _getBackgroundColor(context, sessionState.state),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isBranded ? Colors.transparent : context.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: _getShadowColor(context, sessionState.state).withValues(alpha: isBranded ? 0.4 : 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusIcon(sessionState.state, fgColor),
          const SizedBox(height: 16),
          Text(
            _getStatusText(sessionState.state),
            style: TextStyle(
              color: fgColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          if (sessionState.transcript.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              sessionState.transcript.last,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fgColor.withValues(alpha: 0.8),
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 24),
          _buildControls(context, ref, sessionState, fgColor),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(GeminiLiveState state, Color color) {
    IconData icon;
    switch (state) {
      case GeminiLiveState.disconnected:
        icon = Icons.cloud_off;
        break;
      case GeminiLiveState.reconnecting:
        icon = Icons.sync;
        break;
      case GeminiLiveState.listening:
        icon = Icons.mic;
        break;
      case GeminiLiveState.thinking:
        icon = Icons.graphic_eq; // Ideally an animated waveform
        break;
      case GeminiLiveState.speaking:
        icon = Icons.volume_up;
        break;
      case GeminiLiveState.interrupted:
        icon = Icons.front_hand;
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: Icon(icon, key: ValueKey(state), size: 48, color: color),
    );
  }

  String _getStatusText(GeminiLiveState state) {
    switch (state) {
      case GeminiLiveState.disconnected:
        return 'Disconnected';
      case GeminiLiveState.reconnecting:
        return 'Reconnecting...';
      case GeminiLiveState.listening:
        return 'Listening...';
      case GeminiLiveState.thinking:
        return 'Thinking...';
      case GeminiLiveState.speaking:
        return 'Speaking';
      case GeminiLiveState.interrupted:
        return 'Interrupted';
    }
  }

  Color _getBackgroundColor(BuildContext context, GeminiLiveState state) {
    // Pure Oneova brand colors mapped to live assistant states
    switch (state) {
      case GeminiLiveState.disconnected:
      case GeminiLiveState.reconnecting:
        return context.surfaceMid;
      case GeminiLiveState.listening:
        return AppColors.brandPink; // Active microphone accent
      case GeminiLiveState.thinking:
        return AppColors.brandBlue; // Active intelligence Core Blue
      case GeminiLiveState.speaking:
        return AppColors.brandBlue; // Audio response stream
      case GeminiLiveState.interrupted:
        return AppColors.brandPink; // User interruption accent
    }
  }

  Color _getShadowColor(BuildContext context, GeminiLiveState state) {
    return _getBackgroundColor(context, state);
  }

  Widget _buildControls(BuildContext context, WidgetRef ref, GeminiLiveSessionState sessionState, Color controlColor) {
    final notifier = ref.read(geminiLiveProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (sessionState.state == GeminiLiveState.disconnected)
          IconButton(
            onPressed: () => notifier.startVoiceMode(),
            icon: const Icon(Icons.power_settings_new),
            color: controlColor,
            iconSize: 32,
          )
        else ...[
          IconButton(
            onPressed: () => sessionState.isMuted ? notifier.resume() : notifier.mute(),
            icon: Icon(sessionState.isMuted ? Icons.mic_off : Icons.mic),
            color: controlColor,
          ),
          const SizedBox(width: 16),
          if (sessionState.state == GeminiLiveState.speaking)
            IconButton(
              onPressed: () => notifier.interruptAi(),
              icon: const Icon(Icons.stop_circle),
              color: controlColor,
              iconSize: 36,
            ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => notifier.stop(),
            icon: const Icon(Icons.close),
            color: controlColor,
          ),
        ]
      ],
    );
  }
}
