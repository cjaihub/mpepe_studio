import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

enum MagicSelectStatus {
  idle,
  processing,
  success,
  insufficientConfidence,
}

class MagicSelectPanel extends StatefulWidget {
  final Function(Offset point) onCanvasTap;
  final Function(String command) onNlpCommand;
  
  const MagicSelectPanel({
    super.key,
    required this.onCanvasTap,
    required this.onNlpCommand,
  });

  @override
  State<MagicSelectPanel> createState() => _MagicSelectPanelState();
}

class _MagicSelectPanelState extends State<MagicSelectPanel> {
  MagicSelectStatus _status = MagicSelectStatus.idle;
  final TextEditingController _textController = TextEditingController();

  /// Simulates the callback received from the backend MaskQualityMetrics engine
  void updateStatus(MagicSelectStatus newStatus) {
    setState(() {
      _status = newStatus;
    });
  }

  void _submitCommand(String command) {
    if (command.trim().isEmpty) return;
    
    setState(() => _status = MagicSelectStatus.processing);
    widget.onNlpCommand(command);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // Header & Status Readout
          Row(
            children: [
              const Icon(Icons.auto_fix_high, color: AppColors.brandBlue, size: 24),
              const SizedBox(width: 8),
              Text(
                'Magic Select',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              _buildStatusIndicator(),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Conversational Input
          Container(
            decoration: BoxDecoration(
              color: context.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _status == MagicSelectStatus.insufficientConfidence 
                  ? AppColors.brandBlue 
                  : context.border,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: GoogleFonts.inter(color: context.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _getHintText(),
                      hintStyle: GoogleFonts.inter(color: context.textSecondary, fontSize: 14),
                    ),
                    onSubmitted: _submitCommand,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.mic, color: context.textSecondary),
                  onPressed: () {
                    // Trigger voice-to-text here
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: AppColors.brandBlue),
                  onPressed: () => _submitCommand(_textController.text),
                ),
              ],
            ),
          ),
          
          // Helper Chips for fast interaction
          if (_status == MagicSelectStatus.success) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildPromptChip('add'),
                  _buildPromptChip('remove'),
                  _buildPromptChip('only the face'),
                  _buildPromptChip('exclude background'),
                ],
              ),
            ).animate().fadeIn().slideX(begin: 0.2),
          ]
        ],
      ),
    );
  }

  String _getHintText() {
    switch (_status) {
      case MagicSelectStatus.idle:
        return 'Tap an object, or type a command...';
      case MagicSelectStatus.processing:
        return 'Analyzing...';
      case MagicSelectStatus.success:
        return 'e.g. "only the hair", "exclude shirt"';
      case MagicSelectStatus.insufficientConfidence:
        return 'Help me out! Where should I look?';
    }
  }

  Widget _buildStatusIndicator() {
    if (_status == MagicSelectStatus.processing) {
      return const SizedBox(
        width: 16, height: 16,
        child: AnimatedLoadingIndicator(color: AppColors.brandBlue, strokeWidth: 2),
      );
    }
    
    if (_status == MagicSelectStatus.insufficientConfidence) {
      return Text(
        'Needs correction',
        style: GoogleFonts.inter(
          color: AppColors.brandBlue, // Brand red for alerts
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeIn(duration: 400.ms);
    }
    
    if (_status == MagicSelectStatus.success) {
      return const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18)
        .animate().scale(curve: Curves.elasticOut);
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildPromptChip(String label) {
    return GestureDetector(
      onTap: () => _submitCommand(label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.border, width: 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
