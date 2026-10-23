import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/projects/models/pro_project_models.dart';
import 'effect_inspector_panel.dart';

class ProInspectorPanel extends StatefulWidget {
  final Clip? selectedClip;

  const ProInspectorPanel({super.key, this.selectedClip});

  @override
  State<ProInspectorPanel> createState() => _ProInspectorPanelState();
}

class _ProInspectorPanelState extends State<ProInspectorPanel> {
  @override
  Widget build(BuildContext context) {
    if (widget.selectedClip == null) {
      return Container(
        width: 320,
        color: context.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Inspector',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: context.textPrimary),
              ),
            ),
            Divider(height: 1, color: context.border),
            Expanded(
              child: Center(
                child: Text(
                  'Select a clip to inspect',
                  style: GoogleFonts.inter(color: context.textSecondary),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Actually selected a clip
    return Container(
      width: 320,
      color: context.surface,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            TabBar(
              indicatorColor: AppColors.brandBlue,
              labelColor: context.textPrimary,
              unselectedLabelColor: context.textSecondary,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'Video'),
                Tab(text: 'Audio'),
                Tab(text: 'Effects'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildVideoTab(context),
                  _buildAudioTab(context),
                  EffectInspectorPanel(clip: widget.selectedClip!, onStateChanged: () => setState(() {})),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, 'Transform'),
        _buildSliderRow(context, 'Scale', 1.0, 0.1, 3.0),
        _buildSliderRow(context, 'Position X', 0, -1000, 1000),
        _buildSliderRow(context, 'Position Y', 0, -1000, 1000),
        _buildSliderRow(context, 'Rotation', 0, -360, 360),
        _buildSliderRow(context, 'Opacity', 1.0, 0, 1.0),
        
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Color Correction'),
        _buildSliderRow(context, 'Exposure', 0, -2, 2),
        _buildSliderRow(context, 'Contrast', 1.0, 0, 2),
        _buildSliderRow(context, 'Saturation', 1.0, 0, 3),
        _buildSliderRow(context, 'Temperature', 0, -100, 100),
      ],
    );
  }

  Widget _buildAudioTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, 'Volume & Pan'),
        _buildSliderRow(context, 'Gain (dB)', 0, -60, 12),
        _buildSliderRow(context, 'Pan', 0, -1, 1),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Enhancements'),
        SwitchListTile(
          title: Text('Noise Reduction', style: GoogleFonts.inter(color: context.textPrimary)),
          value: false,
          onChanged: (val) {},
          activeTrackColor: AppColors.brandBlue,
        ),
        SwitchListTile(
          title: Text('Voice Isolation', style: GoogleFonts.inter(color: context.textPrimary)),
          value: false,
          onChanged: (val) {},
          activeTrackColor: AppColors.brandBlue,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildSliderRow(BuildContext context, String label, double value, double min, double max) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12)),
              Text(value.toStringAsFixed(2), style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.brandBlue,
              inactiveTrackColor: context.border,
              thumbColor: context.textPrimary,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: (newVal) {},
            ),
          ),
        ],
      ),
    );
  }
}
