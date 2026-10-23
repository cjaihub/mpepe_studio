import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/project_repository.dart';

class AiStudioPanel extends StatefulWidget {
  final StudioProject project;

  const AiStudioPanel({super.key, required this.project});

  @override
  State<AiStudioPanel> createState() => _AiStudioPanelState();
}

class _AiStudioPanelState extends State<AiStudioPanel> {
  final List<Map<String, dynamic>> _aiCapabilities = [
    {'name': 'Auto Edit', 'icon': Icons.movie_filter},
    {'name': 'Beat Sync', 'icon': Icons.music_note},
    {'name': 'Best Moments', 'icon': Icons.star},
    {'name': 'Scene Detection', 'icon': Icons.camera_roll},
    {'name': 'Face Detection', 'icon': Icons.face},
    {'name': 'Subject Detection', 'icon': Icons.person},
    {'name': 'Smart Crop', 'icon': Icons.crop_free},
    {'name': 'Reframe', 'icon': Icons.center_focus_strong},
    {'name': 'Silence Removal', 'icon': Icons.mic_off},
    {'name': 'Voice Enhancement', 'icon': Icons.record_voice_over},
    {'name': 'Noise Reduction', 'icon': Icons.waves},
    {'name': 'Auto Captions', 'icon': Icons.closed_caption},
    {'name': 'Caption Translation', 'icon': Icons.translate},
    {'name': 'AI Masking', 'icon': Icons.format_shapes},
    {'name': 'Object Removal', 'icon': Icons.cleaning_services},
    {'name': 'Background Separation', 'icon': Icons.flip_to_back},
    {'name': 'Shot Match', 'icon': Icons.compare},
    {'name': 'Color Match', 'icon': Icons.color_lens},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: context.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'AI Studio',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: context.textPrimary),
            ),
          ),
          Divider(height: 1, color: context.border),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _aiCapabilities.length,
              itemBuilder: (context, index) {
                final cap = _aiCapabilities[index];
                return _buildAiFeatureTile(context, cap['name'], cap['icon']);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiFeatureTile(BuildContext context, String name, IconData icon) {
    return Card(
      color: context.bg,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.border),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: AppColors.brandBlue),
        title: Text(name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.all(16),
        collapsedIconColor: context.textSecondary,
        iconColor: context.textPrimary,
        children: [
          Text(
            'Analyze selected clips to apply $name.',
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {},
                child: Text('Preview', style: GoogleFonts.inter(color: context.textSecondary)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                ),
                child: Text('Apply', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          )
        ],
      ),
    );
  }
}
