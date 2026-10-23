import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../backend/photo_studio/photo_studio_models.dart';
import '../photo_studio_screen.dart';

class HslMixerPanel extends ConsumerStatefulWidget {
  const HslMixerPanel({super.key});

  @override
  ConsumerState<HslMixerPanel> createState() => _HslMixerPanelState();
}

class _HslMixerPanelState extends ConsumerState<HslMixerPanel> {
  String _activeChannel = 'red';

  final List<Map<String, dynamic>> _channels = const [
    {'name': 'red', 'label': 'Red', 'color': Color(0xFFE53935)},
    {'name': 'orange', 'label': 'Orange', 'color': Color(0xFFFB8C00)},
    {'name': 'yellow', 'label': 'Yellow', 'color': Color(0xFFFDD835)},
    {'name': 'green', 'label': 'Green', 'color': Color(0xFF43A047)},
    {'name': 'cyan', 'label': 'Cyan', 'color': Color(0xFF00ACC1)},
    {'name': 'blue', 'label': 'Blue', 'color': Color(0xFF1E88E5)},
    {'name': 'purple', 'label': 'Purple', 'color': Color(0xFF8E24AA)},
    {'name': 'magenta', 'label': 'Magenta', 'color': Color(0xFFD81B60)},
  ];

  double _getValueForChannel(String channel, String param, PhotoProject project) {
    if (project.currentGraph.layers.isEmpty) return 0.0;
    final layer = project.currentGraph.layers.first;
    for (final adj in layer.adjustments.reversed) {
      if (adj.type == AdjustmentType.HSL && adj.parameters['channel'] == channel) {
        return (adj.parameters[param] as num?)?.toDouble() ?? 0.0;
      }
    }
    return 0.0;
  }

  void _updateValue(String param, double value) {
    final project = ref.read(activePhotoProjectProvider);
    if (project.currentGraph.layers.isEmpty) return;

    final currentHue = _getValueForChannel(_activeChannel, 'hue', project);
    final currentSat = _getValueForChannel(_activeChannel, 'saturation', project);
    final currentLum = _getValueForChannel(_activeChannel, 'luminance', project);

    ref.read(activePhotoProjectProvider.notifier).setOrReplaceAdjustment(
          project.currentGraph.layers.first.id,
          PhotoAdjustment(
            id: 'hsl_$_activeChannel',
            type: AdjustmentType.HSL,
            parameters: {
              'channel': _activeChannel,
              'hue': param == 'hue' ? value : currentHue,
              'saturation': param == 'saturation' ? value : currentSat,
              'luminance': param == 'luminance' ? value : currentLum,
            },
          ),
        );
  }

  void _resetActiveChannel() {
    final project = ref.read(activePhotoProjectProvider);
    if (project.currentGraph.layers.isEmpty) return;

    ref.read(activePhotoProjectProvider.notifier).setOrReplaceAdjustment(
          project.currentGraph.layers.first.id,
          PhotoAdjustment(
            id: 'hsl_$_activeChannel',
            type: AdjustmentType.HSL,
            parameters: {
              'channel': _activeChannel,
              'hue': 0.0,
              'saturation': 0.0,
              'luminance': 0.0,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(activePhotoProjectProvider);

    final currentHue = _getValueForChannel(_activeChannel, 'hue', project);
    final currentSaturation = _getValueForChannel(_activeChannel, 'saturation', project);
    final currentLuminance = _getValueForChannel(_activeChannel, 'luminance', project);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Channel Title and Reset Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Color Mixer (HSL)',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: _resetActiveChannel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'Reset ${_activeChannel.toUpperCase()}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 8 Channel Selector Chips (Horizontal Scroll or Flex Row)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _channels.map((channel) {
                final isSelected = _activeChannel == channel['name'];
                final Color color = channel['color'] as Color;
                return GestureDetector(
                  onTap: () => setState(() => _activeChannel = channel['name'] as String),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 1.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 6,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // 3 Compact Horizontal Sliders: Hue, Saturation, Luminance
          _buildCompactSlider('Hue', currentHue, (val) => _updateValue('hue', val)),
          _buildCompactSlider('Saturation', currentSaturation, (val) => _updateValue('saturation', val)),
          _buildCompactSlider('Luminance', currentLuminance, (val) => _updateValue('luminance', val)),
        ],
      ),
    );
  }

  Widget _buildCompactSlider(String label, double value, ValueChanged<double> onChanged) {
    final intDisplay = value.toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.0,
                activeTrackColor: AppColors.brandBlue,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: Colors.white,
                overlayColor: AppColors.brandBlue.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value,
                min: -100,
                max: 100,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              intDisplay > 0 ? '+$intDisplay' : '$intDisplay',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
