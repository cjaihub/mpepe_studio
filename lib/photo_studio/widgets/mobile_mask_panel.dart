import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../shared/theme/app_theme.dart';

enum MaskPanelState {
  initial,
  aiCategorySelection,
  activeSelection,
  refinement
}

class MobileMaskPanel extends StatefulWidget {
  const MobileMaskPanel({super.key});

  @override
  State<MobileMaskPanel> createState() => _MobileMaskPanelState();
}

class _MobileMaskPanelState extends State<MobileMaskPanel> {
  MaskPanelState _currentState = MaskPanelState.initial;
  String? _activeAiCategory;

  // AI Categories explicitly requested
  final List<String> _aiCategories = [
    'Subject', 'Person', 'Face', 'Skin', 'Hair', 'Eyes', 
    'Mouth', 'Teeth', 'Clothing', 'Sky', 'Background', 
    'Object', 'Depth', 'Color', 'Luminance'
  ];

  void _transitionTo(MaskPanelState newState) {
    setState(() {
      _currentState = newState;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getHeaderTitle(),
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ).animate(target: _currentState == MaskPanelState.initial ? 1 : 0).fadeIn(),
                  
                  if (_currentState != MaskPanelState.initial)
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary, size: 20),
                      onPressed: () {
                        if (_currentState == MaskPanelState.refinement) {
                          _transitionTo(MaskPanelState.activeSelection);
                        } else if (_currentState == MaskPanelState.activeSelection || _currentState == MaskPanelState.aiCategorySelection) {
                          _transitionTo(MaskPanelState.initial);
                          _activeAiCategory = null;
                        }
                      },
                    ).animate().fadeIn().scale(),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Animated content switcher enforcing "Progressive disclosure"
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              child: _buildStateContent(),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _getHeaderTitle() {
    switch (_currentState) {
      case MaskPanelState.initial: return 'Create Mask';
      case MaskPanelState.aiCategorySelection: return 'AI Select';
      case MaskPanelState.activeSelection: return _activeAiCategory ?? 'Mask Active';
      case MaskPanelState.refinement: return 'Edge Refinement';
    }
  }

  Widget _buildStateContent() {
    switch (_currentState) {
      case MaskPanelState.initial:
        return _buildPrimaryRow();
      case MaskPanelState.aiCategorySelection:
        return _buildAiCategoryGrid();
      case MaskPanelState.activeSelection:
        return _buildActiveSelectionRow();
      case MaskPanelState.refinement:
        return _buildRefinementControls();
    }
  }

  // --- REQUIREMENT: Primary row: Select, Brush, AI, Refine ---
  Widget _buildPrimaryRow() {
    return Padding(
      key: const ValueKey('primary_row'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildToolButton(icon: Icons.ads_click, label: 'Select', onTap: () {}),
          _buildToolButton(icon: Icons.brush, label: 'Brush', onTap: () {}),
          _buildToolButton(icon: Icons.auto_awesome, label: 'AI', isBrandAction: true, onTap: () {
            _transitionTo(MaskPanelState.aiCategorySelection);
          }),
          _buildToolButton(icon: Icons.tune, label: 'Refine', onTap: () {}),
        ],
      ),
    );
  }

  // --- REQUIREMENT: AI selector categories ---
  Widget _buildAiCategoryGrid() {
    return SizedBox(
      key: const ValueKey('ai_grid'),
      height: 220, // Constrained height for scrollability
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // 3 rows
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.4, // Wide pills
        ),
        itemCount: _aiCategories.length,
        itemBuilder: (context, index) {
          final category = _aiCategories[index];
          return GestureDetector(
            onTap: () {
              setState(() => _activeAiCategory = category);
              _transitionTo(MaskPanelState.activeSelection);
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.border, width: 1),
              ),
              child: Text(
                category,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- REQUIREMENT: After selection: Add, Subtract, Refine, Invert, Track, Save ---
  Widget _buildActiveSelectionRow() {
    return Padding(
      key: const ValueKey('active_row'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildActionButton(icon: Icons.add_circle_outline, label: 'Add', onTap: () {}),
            _buildActionButton(icon: Icons.remove_circle_outline, label: 'Subtract', onTap: () {}),
            _buildActionButton(icon: Icons.tune, label: 'Refine', isBrandAction: true, onTap: () {
              _transitionTo(MaskPanelState.refinement);
            }),
            _buildActionButton(icon: Icons.flip, label: 'Invert', onTap: () {}),
            _buildActionButton(icon: Icons.track_changes, label: 'Track', onTap: () {}),
            _buildActionButton(icon: Icons.save, label: 'Save', onTap: () {}),
          ],
        ),
      ),
    );
  }

  // --- REQUIREMENT: Advanced controls remain inside Refine. Progressive disclosure. ---
  Widget _buildRefinementControls() {
    return Padding(
      key: const ValueKey('refine_controls'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildSliderControl('Feather'),
          const SizedBox(height: 16),
          _buildSliderControl('Smooth'),
          const SizedBox(height: 16),
          _buildSliderControl('Contract / Expand'),
          const SizedBox(height: 24),
          // Deep progressive disclosure
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.border, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Advanced Edge Settings',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: context.textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderControl(String label) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: context.surfaceMid,
              thumbColor: AppColors.brandBlue,
              trackHeight: 4,
            ),
            child: Slider(
              value: 0.5,
              onChanged: (val) {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required IconData icon, 
    required String label, 
    bool isBrandAction = false, 
    required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: isBrandAction ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isBrandAction ? Colors.transparent : context.border, 
            width: 1,
          ),
          boxShadow: isBrandAction ? [
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isBrandAction ? Colors.white : context.textPrimary, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isBrandAction ? Colors.white : context.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon, 
    required String label, 
    bool isBrandAction = false, 
    required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isBrandAction ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(30), // Pill shape
          border: Border.all(
            color: isBrandAction ? Colors.transparent : context.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isBrandAction ? Colors.white : context.textPrimary, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isBrandAction ? Colors.white : context.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
