import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/projects/models/pro_project_models.dart';
import '../../shared/theme/app_theme.dart';

class ColorInspectorPanel extends StatefulWidget {
  final Clip clip;
  final VoidCallback onStateChanged;

  const ColorInspectorPanel({
    super.key,
    required this.clip,
    required this.onStateChanged,
  });

  @override
  State<ColorInspectorPanel> createState() => _ColorInspectorPanelState();
}

class _ColorInspectorPanelState extends State<ColorInspectorPanel> {
  int _selectedCategoryIndex = 0;
  int _selectedColorStateIndex = -1; // -1 for Base Grade, >=0 for secondary
  
  ColorState get _activeColorState {
    if (_selectedColorStateIndex == -1) return widget.clip.color;
    if (_selectedColorStateIndex < widget.clip.secondaryColorStates.length) {
      return widget.clip.secondaryColorStates[_selectedColorStateIndex];
    }
    return widget.clip.color;
  }
  
  final List<String> _categories = [
    'Basic',
    'Curves',
    'Wheels',
    'HSL',
    'LUTs',
    'HDR',
    'Presets',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: AppColors.darkSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildCategoryTabs(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildSelectedCategory(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Color',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  // Reset the active color state
                  if (_selectedColorStateIndex == -1) {
                    widget.clip.color = ColorState();
                  } else if (_selectedColorStateIndex < widget.clip.secondaryColorStates.length) {
                    widget.clip.secondaryColorStates[_selectedColorStateIndex] = ColorState(targetMaskId: _activeColorState.targetMaskId);
                  }
                  widget.onStateChanged();
                },
                tooltip: 'Reset Active Grade',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurfaceHighlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedColorStateIndex,
                    isExpanded: true,
                    dropdownColor: AppColors.darkSurfaceHighlight,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                    items: [
                      DropdownMenuItem(
                        value: -1,
                        child: Text('Primary Grade', style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      for (int i = 0; i < widget.clip.secondaryColorStates.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Builder(
                            builder: (context) {
                              final maskId = widget.clip.secondaryColorStates[i].targetMaskId;
                              final displayName = maskId ?? 'Layer \${i + 1}';
                              return Text(
                                'Secondary: $displayName',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                              );
                            }
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedColorStateIndex = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.darkSurfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: AppColors.brandBlue, size: 20),
                  onPressed: () {
                    setState(() {
                      widget.clip.secondaryColorStates.add(ColorState());
                      _selectedColorStateIndex = widget.clip.secondaryColorStates.length - 1;
                    });
                    widget.onStateChanged();
                  },
                  tooltip: 'Add Secondary Grade',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkSurfaceHighlight)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategoryIndex == index;
          return InkWell(
            onTap: () => setState(() => _selectedCategoryIndex = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? AppColors.brandBlue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _categories[index],
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedCategory() {
    switch (_categories[_selectedCategoryIndex]) {
      case 'Basic':
        return _buildBasicCorrection();
      case 'Curves':
        return _buildCurves();
      case 'Wheels':
        return _buildWheels();
      case 'HSL':
        return _buildHsl();
      case 'LUTs':
        return _buildLuts();
      case 'HDR':
        return _buildHdr();
      case 'Presets':
        return _buildPresets();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPresets() {
    // Mock Presets for now
    final mockPresets = [
      ColorPreset(name: 'Cinematic Teal & Orange', state: ColorState(exposure: 0.2, temperature: -0.1, tint: 0.1)),
      ColorPreset(name: 'Moody Dark', state: ColorState(exposure: -0.5, contrast: 1.2, saturation: 0.8)),
      ColorPreset(name: 'Bright & Airy', state: ColorState(exposure: 0.4, contrast: 0.9, saturation: 1.1)),
    ];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mockPresets.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ElevatedButton.icon(
            onPressed: () {
              // Save preset logic would go here
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Current as Preset'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkSurfaceHighlight,
              foregroundColor: Colors.white,
            ),
          );
        }

        final preset = mockPresets[index - 1];
        return ListTile(
          title: Text(preset.name, style: GoogleFonts.inter(color: Colors.white)),
          subtitle: Text(preset.category, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          trailing: ElevatedButton(
            onPressed: () {
              // Apply preset logic
              // In reality we would merge or replace the active ColorState
              final newState = preset.state;
              // E.g.
              _activeColorState.exposure = newState.exposure;
              _activeColorState.contrast = newState.contrast;
              _activeColorState.saturation = newState.saturation;
              widget.onStateChanged();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apply'),
          ),
          tileColor: AppColors.darkSurfaceHighlight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      },
    );
  }

  Widget _buildBasicCorrection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Light'),
        _buildSlider('Exposure', _activeColorState.exposure, -5, 5, (v) => _activeColorState.exposure = v),
        _buildSlider('Contrast', _activeColorState.contrast, 0, 2, (v) => _activeColorState.contrast = v),
        _buildSlider('Highlights', _activeColorState.highlights, -1, 1, (v) => _activeColorState.highlights = v),
        _buildSlider('Shadows', _activeColorState.shadows, -1, 1, (v) => _activeColorState.shadows = v),
        _buildSlider('Whites', _activeColorState.whites, -1, 1, (v) => _activeColorState.whites = v),
        _buildSlider('Blacks', _activeColorState.blacks, -1, 1, (v) => _activeColorState.blacks = v),
        const SizedBox(height: 24),
        _buildSectionTitle('Color'),
        _buildSlider('Temperature', _activeColorState.temperature, -1, 1, (v) => _activeColorState.temperature = v),
        _buildSlider('Tint', _activeColorState.tint, -1, 1, (v) => _activeColorState.tint = v),
        _buildSlider('Saturation', _activeColorState.saturation, 0, 2, (v) => _activeColorState.saturation = v),
        _buildSlider('Vibrance', _activeColorState.vibrance, -1, 1, (v) => _activeColorState.vibrance = v),
      ],
    );
  }

  Widget _buildCurves() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('RGB Curves'),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.darkBackground,
            border: Border.all(color: AppColors.darkSurfaceHighlight),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              'Curve Editor\n(Visual interactive editor placeholder)',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWheels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Color Wheels'),
        _buildWheelMockup('Lift (Shadows)', _activeColorState.lift),
        const SizedBox(height: 16),
        _buildWheelMockup('Gamma (Midtones)', _activeColorState.gamma),
        const SizedBox(height: 16),
        _buildWheelMockup('Gain (Highlights)', _activeColorState.gain),
      ],
    );
  }

  Widget _buildWheelMockup(String title, ColorWheel wheel) {
    return Column(
      children: [
        Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.darkSurfaceHighlight, width: 2),
            gradient: const SweepGradient(
              colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.pinkAccent, Colors.red],
            ),
          ),
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildSlider('Lum', wheel.luminance, -1, 1, (v) => wheel.luminance = v),
      ],
    );
  }

  Widget _buildHsl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('HSL'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _activeColorState.hsl.keys.map((colorName) {
            final color = _getColorFromName(colorName);
            return InkWell(
              onTap: () {},
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _buildSlider('Hue', 0, -1, 1, (v) {}),
        _buildSlider('Saturation', 0, -1, 1, (v) {}),
        _buildSlider('Luminance', 0, -1, 1, (v) {}),
      ],
    );
  }

  Color _getColorFromName(String name) {
    switch (name) {
      case 'Red': return Colors.red;
      case 'Orange': return Colors.orange;
      case 'Yellow': return Colors.yellow;
      case 'Green': return Colors.green;
      case 'Cyan': return Colors.cyan;
      case 'Blue': return Colors.blue;
      case 'Purple': return Colors.deepPurple;
      case 'Magenta': return Colors.pinkAccent;
      default: return Colors.grey;
    }
  }

  Widget _buildLuts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('LUT Stack'),
        if (_activeColorState.lutStack.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: Text('No LUTs applied', style: GoogleFonts.inter(color: AppColors.textSecondary)),
            ),
          ),
        for (final lut in _activeColorState.lutStack)
          _buildLutItem(lut),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _activeColorState.lutStack.add(
                LutStage(id: DateTime.now().toString(), name: 'Cinematic Warm', path: 'asset/lut/warm.cube')
              );
            });
            widget.onStateChanged();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add LUT'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkSurfaceHighlight,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 40),
          ),
        )
      ],
    );
  }

  Widget _buildLutItem(LutStage lut) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lut.name, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              Switch(
                value: lut.isEnabled,
                activeTrackColor: AppColors.brandBlue,
                onChanged: (val) {
                  setState(() => lut.isEnabled = val);
                  widget.onStateChanged();
                },
              ),
            ],
          ),
          _buildSlider('Intensity', lut.intensity, 0, 1, (v) => lut.intensity = v),
        ],
      ),
    );
  }

  Widget _buildHdr() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('HDR Wheels'),
        _buildSlider('Global', _activeColorState.hdrGlobal, -1, 1, (v) => _activeColorState.hdrGlobal = v),
        _buildSlider('Specular', _activeColorState.hdrSpecular, -1, 1, (v) => _activeColorState.hdrSpecular = v),
        _buildSlider('Light', _activeColorState.hdrLight, -1, 1, (v) => _activeColorState.hdrLight = v),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
              Text(value.toStringAsFixed(2), style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: AppColors.darkSurfaceHighlight,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: (val) {
                setState(() {
                  onChanged(val);
                });
                widget.onStateChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}
