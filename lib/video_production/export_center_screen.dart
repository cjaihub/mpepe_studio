import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/project_repository.dart';
import 'dart:async';
import '../backend/projects/renderer/export_engine.dart';
import '../backend/projects/renderer/media_render_service.dart';
import '../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ExportCenterScreen extends StatefulWidget {
  final StudioProject project;

  const ExportCenterScreen({super.key, required this.project});

  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  String _selectedPreset = 'Master';
  String _selectedCodec = 'H.264';
  String _selectedResolution = '1080p';
  double _selectedFrameRate = 30.0;
  bool _isHDR = false;
  String _selectedAudioCodec = 'AAC';
  
  final List<String> _presets = ['Master', 'YouTube', 'Instagram', 'Oneova Reel', 'Custom'];
  final List<String> _codecs = ['H.264', 'HEVC (H.265)', 'ProRes 422', 'ProRes 4444'];
  final List<String> _resolutions = ['Source', '1080p', '2K', '4K'];
  final List<double> _frameRates = [23.976, 24, 25, 29.97, 30, 50, 59.94, 60, 120];

  late ExportEngine _exportEngine;
  Timer? _exportTimer;
  ExportJob? _currentJob;

  @override
  void initState() {
    super.initState();
    _exportEngine = ExportEngine(MediaRenderService());
    _applyPreset(_selectedPreset);
  }

  @override
  void dispose() {
    _exportTimer?.cancel();
    super.dispose();
  }

  void _applyPreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      switch (preset) {
        case 'Master':
          _selectedCodec = 'ProRes 422';
          _selectedResolution = 'Source';
          break;
        case 'YouTube':
          _selectedCodec = 'H.264';
          _selectedResolution = '4K';
          break;
        case 'Instagram':
        case 'Oneova Reel':
          _selectedCodec = 'H.264';
          _selectedResolution = '1080p';
          break;
        case 'Custom':
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.textPrimary),
          onPressed: () {
            HapticFeedback.lightImpact();
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        title: Text(
          'Export Center',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: context.textPrimary),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.close, color: context.textPrimary),
            onPressed: () {
              HapticFeedback.lightImpact();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/hub/home');
              }
            },
          )
        ],
      ),
      body: Row(
        children: [
          // Left: settings
          Expanded(
            flex: 1,
            child: Container(
              color: context.surface,
              padding: const EdgeInsets.all(24),
              child: ListView(
                children: [
                  _buildSectionTitle(context, 'Presets'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presets.map((p) => _buildChoiceChip(context, p, _selectedPreset, (val) => _applyPreset(val))).toList(),
                  ),
                  const SizedBox(height: 32),
                  
                  _buildSectionTitle(context, 'Video Settings'),
                  const SizedBox(height: 16),
                  _buildDropdown(context, 'Codec', _selectedCodec, _codecs, (val) => setState(() { _selectedCodec = val!; _selectedPreset = 'Custom'; })),
                  const SizedBox(height: 16),
                  _buildDropdown(context, 'Resolution', _selectedResolution, _resolutions, (val) => setState(() { _selectedResolution = val!; _selectedPreset = 'Custom'; })),
                  const SizedBox(height: 16),
                  _buildDropdown(context, 'Frame Rate', _selectedFrameRate.toString(), _frameRates.map((e) => e.toString()).toList(), (val) => setState(() { _selectedFrameRate = double.parse(val!); _selectedPreset = 'Custom'; })),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('HDR Export', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600)),
                      Switch(
                        value: _isHDR,
                        onChanged: (val) => setState(() { _isHDR = val; _selectedPreset = 'Custom'; }),
                        activeTrackColor: AppColors.brandBlue,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  _buildSectionTitle(context, 'Audio Settings'),
                  const SizedBox(height: 16),
                  _buildDropdown(context, 'Audio Codec', _selectedAudioCodec, ['AAC', 'PCM (Uncompressed)'], (val) => setState(() { _selectedAudioCodec = val!; _selectedPreset = 'Custom'; })),
                ],
              ),
            ),
          ),
          
          // Right: preview and queue
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildRenderedPreview(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estimated Size: 450 MB',
                              style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'File: ${widget.project.title}_export.mp4',
                              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {},
                              child: Text('Add to Render Queue', style: GoogleFonts.inter(color: context.textSecondary)),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _currentJob != null && _currentJob!.status != ExportStatus.completed
                                  ? null
                                  : _startExport,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                _currentJob != null && _currentJob!.status == ExportStatus.rendering
                                    ? 'Rendering \${(_currentJob!.progress * 100).toInt()}%'
                                    : 'Export Now',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: context.textSecondary),
    );
  }

  Widget _buildChoiceChip(BuildContext context, String label, String selected, Function(String) onSelected) {
    final isSelected = label == selected;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.inter(color: isSelected ? Colors.white : context.textPrimary)),
      selected: isSelected,
      selectedColor: AppColors.brandBlue,
      backgroundColor: context.surfaceMid,
      onSelected: (val) {
        if (val) onSelected(label);
      },
    );
  }

  Widget _buildDropdown(BuildContext context, String label, String value, List<String> items, Function(String?) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600)),
        DropdownButton<String>(
          value: value,
          dropdownColor: context.surfaceMid,
          style: GoogleFonts.inter(color: context.textPrimary),
          underline: Container(),
          onChanged: onChanged,
          items: items.map<DropdownMenuItem<String>>((String val) {
            return DropdownMenuItem<String>(
              value: val,
              child: Text(val),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRenderedPreview() {
    Widget baseImage = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey, Colors.grey],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          'Final Rendered Output',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );

    // Apply the active sequence's first clip's color grade to prove the pipeline works
    if (widget.project.sequences.isEmpty || widget.project.sequences.first.tracks.isEmpty || widget.project.sequences.first.tracks.first.clips.isEmpty) {
      return baseImage;
    }

    final color = widget.project.sequences.first.tracks.first.clips.first.color;
    final e = color.exposure * 255.0; // simple scalar for demonstration
    final c = color.contrast;
    final t = (1.0 - c) * 128.0;

    final matrix = <double>[
      c, 0, 0, 0, e + t,
      0, c, 0, 0, e + t,
      0, 0, c, 0, e + t,
      0, 0, 0, 1, 0,
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: baseImage,
        ),
        if (_currentJob != null)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedLoadingIndicator(
                      value: _currentJob!.progress,
                      color: AppColors.brandBlue,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Exporting: \${(_currentJob!.progress * 100).toInt()}%',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _currentJob!.status.name.toUpperCase(),
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _startExport() {
    final settings = ExportSettings(
      outputWidth: 1920,
      outputHeight: 1080,
      frameRate: _selectedFrameRate,
      codec: _selectedCodec,
      bitrate: 8000000,
      audioCodec: _selectedAudioCodec,
      colorOutput: 'Rec.709',
      isHDR: _isHDR,
      outputPath: 'export_\${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    final job = ExportJob(
      id: 'job_\${DateTime.now().millisecondsSinceEpoch}',
      project: widget.project,
      sequenceId: widget.project.activeSequenceId ?? (widget.project.sequences.isNotEmpty ? widget.project.sequences.first.id : 'default_seq'),
      startTime: 0.0,
      endTime: 10.0, // Mock duration
      settings: settings,
    );

    _exportEngine.enqueue(job);
    
    setState(() {
      _currentJob = job;
    });

    _exportTimer?.cancel();
    _exportTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_currentJob?.status == ExportStatus.completed || _currentJob?.status == ExportStatus.failed) {
        timer.cancel();
      }
    });
  }
}
