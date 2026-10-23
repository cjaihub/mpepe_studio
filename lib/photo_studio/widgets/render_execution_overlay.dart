import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

enum RenderExecutionMode {
  fast,
  quality,
}

enum RenderExecutionState {
  idle,
  generatingFast,
  fastReady,
  generatingQuality,
  qualityReady,
}

class RenderExecutionOverlay extends StatefulWidget {
  /// Triggered when the user initiates a selection
  final Future<void> Function() onGenerateFastPreview;
  
  /// Triggered when the user approves the fast preview to kick off the final render
  final Future<void> Function() onGenerateQualityRender;

  const RenderExecutionOverlay({
    super.key,
    required this.onGenerateFastPreview,
    required this.onGenerateQualityRender,
  });

  @override
  State<RenderExecutionOverlay> createState() => RenderExecutionOverlayState();
}

class RenderExecutionOverlayState extends State<RenderExecutionOverlay> {
  RenderExecutionState _state = RenderExecutionState.idle;

  /// External trigger to begin the FAST preview process
  Future<void> initiateSelection() async {
    setState(() => _state = RenderExecutionState.generatingFast);
    
    try {
      await widget.onGenerateFastPreview();
      setState(() => _state = RenderExecutionState.fastReady);
    } catch (e) {
      setState(() => _state = RenderExecutionState.idle);
      // Handle error gracefully
    }
  }

  /// Triggers the QUALITY pipeline after user approves the FAST preview
  Future<void> _approveAndRenderQuality() async {
    setState(() => _state = RenderExecutionState.generatingQuality);
    
    try {
      await widget.onGenerateQualityRender();
      setState(() => _state = RenderExecutionState.qualityReady);
    } catch (e) {
      setState(() => _state = RenderExecutionState.fastReady); // Revert to fast if it fails
    }
  }

  /// Rejects the fast preview, returning to idle
  void _rejectPreview() {
    setState(() => _state = RenderExecutionState.idle);
  }

  @override
  Widget build(BuildContext context) {
    if (_state == RenderExecutionState.idle || _state == RenderExecutionState.qualityReady) {
      // Hide the overlay completely when idle or when the high-quality render is finished
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _state == RenderExecutionState.generatingQuality 
              ? AppColors.brandBlue 
              : context.border, 
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.08), 
              blurRadius: 16, 
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStateContent(),
        ),
      ),
    );
  }

  Widget _buildStateContent() {
    switch (_state) {
      case RenderExecutionState.generatingFast:
        return _buildProcessingUI(
          mode: 'FAST PREVIEW',
          description: 'Generating low-resolution interactive mask...',
          isPulse: false,
        );
        
      case RenderExecutionState.fastReady:
        return _buildApprovalUI();
        
      case RenderExecutionState.generatingQuality:
        return _buildProcessingUI(
          mode: 'QUALITY RENDER',
          description: 'Executing full-resolution GPU pass. High-quality edges...',
          isPulse: true,
        );
        
      default:
        return const SizedBox.shrink();
    }
  }

  /// REQUIREMENT: Show processing state honestly.
  Widget _buildProcessingUI({required String mode, required String description, required bool isPulse}) {
    return Row(
      key: ValueKey(mode),
      children: [
        SizedBox(
          width: 24, height: 24,
          child: AnimatedLoadingIndicator(
            color: isPulse ? AppColors.brandBlue : context.textPrimary, 
            strokeWidth: 2
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode,
                style: GoogleFonts.inter(
                  color: isPulse ? AppColors.brandBlue : context.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ).animate(onPlay: (c) => isPulse ? c.repeat(reverse: true) : null).fadeIn(duration: 400.ms),
              Text(
                description,
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// REQUIREMENT: FAST preview -> user approves -> QUALITY render
  Widget _buildApprovalUI() {
    return Column(
      key: const ValueKey('approval_ui'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              'Low-Res Preview Ready',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Warning: This is a fast interactive proxy. Approve to render the final full-resolution mask.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _rejectPreview,
                child: Text('Reject', style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _approveAndRenderQuality,
                child: Text('Render Quality', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
