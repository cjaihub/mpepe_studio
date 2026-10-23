import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/mask_engine/universal_mask_models.dart';

class MaskInfoPanel extends StatefulWidget {
  final UniversalMask activeMask;
  final String semanticLabel; // e.g. "Woman's hair"
  final VoidCallback onInspect;
  final VoidCallback onRefine;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  const MaskInfoPanel({
    super.key,
    required this.activeMask,
    required this.semanticLabel,
    required this.onInspect,
    required this.onRefine,
    required this.onRegenerate,
    required this.onDelete,
  });

  @override
  State<MaskInfoPanel> createState() => _MaskInfoPanelState();
}

class _MaskInfoPanelState extends State<MaskInfoPanel> {
  bool _showAdvancedInfo = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          
          // Primary View: Friendly and accessible
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.brandBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected',
                    style: GoogleFonts.inter(
                      color: context.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.semanticLabel, // e.g., "Woman's hair"
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Progressive Disclosure Toggle
              IconButton(
                icon: Icon(
                  _showAdvancedInfo ? Icons.info : Icons.info_outline,
                  color: _showAdvancedInfo ? AppColors.brandBlue : context.textSecondary,
                ),
                onPressed: () {
                  setState(() => _showAdvancedInfo = !_showAdvancedInfo);
                },
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Action Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.search, 'Inspect', widget.onInspect),
              _buildActionButton(Icons.tune, 'Refine', widget.onRefine),
              _buildActionButton(Icons.refresh, 'Regenerate', widget.onRegenerate),
              _buildActionButton(Icons.delete_outline, 'Delete', widget.onDelete, isDestructive: true),
            ],
          ),

          // Technical Details (Hidden by default)
          if (_showAdvancedInfo) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Advanced Info',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTechRow('Method', 'AI segmentation'),
                  _buildTechRow('Model', widget.activeMask.parameters['model'] ?? 'Unknown Model'),
                  _buildTechRow('Confidence', _formatConfidence(widget.activeMask.parameters['confidence'])),
                  _buildTechRow('Frame', widget.activeMask.parameters['geometry'] ?? 'Original resolution'),
                  _buildTechRow('Refinement', widget.activeMask.parameters['feather'] != null ? 'Automatic edge refinement' : 'Raw edges'),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.1),
          ],
        ],
      ),
    );
  }

  String _formatConfidence(dynamic confidence) {
    if (confidence == null) return 'Not calibrated';
    if (confidence is double) {
      if (confidence > 0.9) return 'High (\${(confidence * 100).toInt()}%)';
      if (confidence > 0.6) return 'Moderate (\${(confidence * 100).toInt()}%)';
      return 'Low (\${(confidence * 100).toInt()}%) - Verification recommended';
    }
    return confidence.toString();
  }

  Widget _buildTechRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, {bool isDestructive = false}) {
    return GestureDetector(
      onTap: () {
        if (isDestructive) {
          _showDeleteConfirmation();
        } else {
          onTap();
        }
      },
      child: Column(
        children: [
          Icon(icon, color: isDestructive ? Colors.redAccent : context.textPrimary, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isDestructive ? Colors.redAccent : context.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // --- REQUIREMENT: Confirmations are Mandatory ---
  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Mask?',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Are you sure you want to delete this mask? This action cannot be undone.',
          style: GoogleFonts.inter(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete(); // Execute the actual destruction
            },
            child: Text('Confirm', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
