import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/projects/models/pro_project_models.dart';
import '../../backend/projects/models/effect_models.dart';
import '../../shared/theme/app_theme.dart';

class EffectInspectorPanel extends StatefulWidget {
  final Clip clip;
  final VoidCallback onStateChanged;

  const EffectInspectorPanel({
    super.key,
    required this.clip,
    required this.onStateChanged,
  });

  @override
  State<EffectInspectorPanel> createState() => _EffectInspectorPanelState();
}

class _EffectInspectorPanelState extends State<EffectInspectorPanel> {
  final List<String> _expandedEffects = [];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: context.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.clip.effects.length,
              itemBuilder: (context, index) {
                return _buildEffectNode(context, widget.clip.effects[index], index);
              },
            ),
          ),
          _buildAddEffectButton(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Effects',
        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: context.textPrimary),
      ),
    );
  }

  Widget _buildAddEffectButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: () {
          // Open Effect Browser (Registry)
          _showEffectBrowser();
        },
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add Effect'),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.surfaceMid,
          foregroundColor: context.textPrimary,
          minimumSize: const Size(double.infinity, 40),
        ),
      ),
    );
  }

  void _showEffectBrowser() {
    // Mock effect browser adding Gaussian Blur
    setState(() {
      widget.clip.effects.add(
        EffectState(
          name: 'Gaussian Blur',
          type: 'gaussian_blur',
          parameters: GaussianBlurParameters(),
        )
      );
    });
    widget.onStateChanged();
  }

  Widget _buildEffectNode(BuildContext context, EffectState effect, int index) {
    final isExpanded = _expandedEffects.contains(effect.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedEffects.remove(effect.id);
                } else {
                  _expandedEffects.add(effect.id);
                }
              });
            },
            leading: IconButton(
              icon: Icon(
                effect.enabled ? Icons.visibility : Icons.visibility_off,
                color: effect.enabled ? AppColors.brandBlue : context.textSecondary,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  widget.clip.effects[index] = effect.copyWith(enabled: !effect.enabled);
                });
                widget.onStateChanged();
              },
            ),
            title: Text(effect.name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.delete, color: context.textSecondary, size: 18),
                  onPressed: () {
                    setState(() {
                      widget.clip.effects.removeAt(index);
                    });
                    widget.onStateChanged();
                  },
                ),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: context.textSecondary),
              ],
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: _buildEffectParameters(context, effect, index),
            ),
        ],
      ),
    );
  }

  Widget _buildEffectParameters(BuildContext context, EffectState effect, int index) {
    // Render specific parameters based on type
    if (effect.parameters is GaussianBlurParameters) {
      final params = effect.parameters as GaussianBlurParameters;
      return Column(
        children: [
          _buildAnimatableSlider(context, 'Radius', params.radius, 0, 100, (v) {
            setState(() {
              widget.clip.effects[index] = effect.copyWith(parameters: params.copyWith(radius: v));
            });
            widget.onStateChanged();
          }),
        ],
      );
    } else if (effect.parameters is GlowParameters) {
       final params = effect.parameters as GlowParameters;
       return Column(
        children: [
          _buildAnimatableSlider(context, 'Intensity', params.intensity, 0, 5, (v) {
            setState(() {
              widget.clip.effects[index] = effect.copyWith(parameters: params.copyWith(intensity: v));
            });
            widget.onStateChanged();
          }),
          _buildAnimatableSlider(context, 'Radius', params.radius, 0, 100, (v) {
            setState(() {
              widget.clip.effects[index] = effect.copyWith(parameters: params.copyWith(radius: v));
            });
            widget.onStateChanged();
          }),
        ],
      );
    }
    
    // Fallback for others
    return Text('Parameters go here', style: GoogleFonts.inter(color: context.textSecondary));
  }

  Widget _buildAnimatableSlider(BuildContext context, String label, double value, double min, double max, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12)),
                  const SizedBox(width: 4),
                  Icon(Icons.diamond_outlined, size: 14, color: context.textSecondary), // Keyframe icon
                ],
              ),
              Text(value.toStringAsFixed(2), style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: context.border,
              thumbColor: context.textPrimary,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
