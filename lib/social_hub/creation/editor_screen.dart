import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../backend/social/services/draft_manager.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final VideoDraft? initialDraft;
  const EditorScreen({super.key, this.initialDraft});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late VideoDraft _currentDraft;
  bool _isPlaying = false;
  double _playbackPosition = 0.0;

  // Simulated tracks
  final List<String> _videoClips = ['clip1 (0:05)', 'clip2 (0:08)'];
  final List<String> _audioTracks = ['voiceover (0:04)', 'music (0:13)'];
  final List<String> _textTracks = ['Caption: Hello!'];
  final List<String> _effectTracks = ['Blur In'];
  final List<String> _pipTracks = ['PiP Reaction'];

  // Selected tool
  String? _selectedTool;

  @override
  void initState() {
    super.initState();
    _currentDraft =
        widget.initialDraft ??
        VideoDraft(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'New Project',
          updatedAt: DateTime.now(),
        );
    _autoSave();
  }

  void _autoSave() {
    // Defer provider mutation to after first build to avoid Riverpod error:
    // "Tried to modify a provider while the widget tree was building."
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(draftManagerProvider.notifier).saveDraft(_currentDraft);
      }
    });
  }

  void _showToolBottomSheet(String title, List<Widget> children) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _handleToolTap(String toolName) {
    setState(() => _selectedTool = toolName);

    // Show specific tools bottom sheet
    switch (toolName) {
      case 'Pre-Prod':
        _showToolBottomSheet('Pre-Production', [
          _buildToolRow(['Storyboard', 'Script', 'Teleprompter', 'Shot List']),
        ]);
        break;
      case 'Edit':
        _showToolBottomSheet('Edit Tools (Non-destructive)', [
          _buildToolRow(['Trim', 'Split', 'Crop', 'Resize', 'Rotate']),
          _buildToolRow(['Speed', 'Reverse', 'Keyframes', 'Motion', 'Replace']),
        ]);
        break;
      case 'Markers':
        _showToolBottomSheet('Markers & Sync', [
          _buildToolRow(['Scene Mk', 'Chapter Mk', 'Beat Detect', 'Sync Music']),
        ]);
        break;
      case 'Audio':
        _showToolBottomSheet('Audio Tools', [
          _buildToolRow([
            'Music',
            'Voiceover',
            'Sound FX',
            'Mixing',
            'Volume Auto',
          ]),
        ]);
        break;
      case 'Text':
        _showToolBottomSheet('Text Tools', [
          _buildToolRow([
            'Text',
            'Auto Captions',
            'Caption Style',
            'Title Cards',
            'Stickers',
          ]),
        ]);
        break;
      case 'Effects':
        _showToolBottomSheet('Effects Tools', [
          _buildToolRow([
            'Effects',
            'Transitions',
            'Filters',
            'Blur',
            'Masking',
          ]),
        ]);
        break;
      case 'Overlay':
        _showToolBottomSheet('Overlay / Advanced', [
          _buildToolRow([
            'PiP',
            'Green Screen',
            'Remove BG',
            'Blend',
            'Safe Zones',
          ]),
        ]);
        break;
      case 'Export':
        _showToolBottomSheet('Export & Thumbnails', [
          _buildToolRow(['Thumbnail Gen', 'A/B Thumbs', 'Export Presets', 'Quality Insp']),
          _buildToolRow(['BG Render', 'Duplicate', 'History', 'Drafts']),
        ]);
        break;
      case 'AI Magic':
        _showToolBottomSheet('Controlled AI Creation', [
          _buildToolRow(['Text2Video', 'Img2Video', 'Restyle', 'Settings']),
          _buildToolRow(['Auto Reframe', 'Obj Remove', 'BG Replace']),
          _buildToolRow(['Auto Caps', 'Rewrite', 'Hook Gen', 'Title Gen']),
          _buildToolRow(['Voice Clean', 'Enhance', 'Noise Rm', 'Dubbing', 'Sub Trans']),
          _buildToolRow(['Highlights', 'Long2Short', 'Scene Suggest']),
        ]);
        break;
    }
  }

  Widget _buildToolRow(List<String> tools) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tools.map((tool) => _buildSubToolItem(tool)).toList(),
      ),
    );
  }

  Widget _buildSubToolItem(String label) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // Close sheet
        
        // Mocking AI metadata updates when an AI tool is tapped
        if (['Text2Video', 'Img2Video', 'Restyle'].contains(label)) {
          _currentDraft.metadata['ai_generated'] = true;
          _currentDraft.metadata['ai_assisted'] = true;
        } else if (label == 'Settings') {
          final enabled = _currentDraft.metadata['ai_processing_enabled'] ?? true;
          _currentDraft.metadata['ai_processing_enabled'] = !enabled;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Processing ${!enabled ? 'Enabled' : 'Disabled'}')));
          _autoSave();
          setState(() {});
          return;
        } else if (['Auto Reframe', 'Obj Remove', 'BG Replace', 'Auto Caps', 'Rewrite', 'Hook Gen', 'Title Gen', 'Voice Clean', 'Enhance', 'Noise Rm', 'Dubbing', 'Sub Trans', 'Highlights', 'Long2Short', 'Scene Suggest'].contains(label)) {
          _currentDraft.metadata['ai_assisted'] = true;
          _currentDraft.metadata['ai_edited'] = true;
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Applied $label')));
        _autoSave();
        setState(() {});
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.build, color: context.textPrimary, size: 20),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(color: context.textPrimary, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () {
            _autoSave();
            if (context.canPop()) {
              context.pop();
            } else {
              context.push('/social_hub/feed');
            }
          },
        ),
        title: Text(
          'Studio Editor',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.undo, color: context.textPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Undo command')));
            },
          ),
          IconButton(
            icon: Icon(Icons.redo, color: context.textPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Redo command')));
            },
          ),
          IconButton(
            icon: Icon(Icons.save_alt, color: context.textPrimary),
            onPressed: () {
              _autoSave();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Draft saved')));
            },
          ),
          TextButton(
            onPressed: () {
              // Finish creation and go to feed or upload
              context.push('/social_hub/feed');
            },
            child: const Text(
              'Next',
              style: TextStyle(
                color: AppColors.brandBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Video Preview
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  const Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white24,
                      size: 64,
                    ),
                  ),
                  // AI Metadata indicators
                  if (_currentDraft.metadata['ai_generated'] == true || _currentDraft.metadata['ai_assisted'] == true || _currentDraft.metadata['ai_edited'] == true)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              _currentDraft.metadata['ai_generated'] == true ? 'AI Generated' : 
                              (_currentDraft.metadata['ai_edited'] == true ? 'AI Edited' : 'AI Assisted'),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Simulated elements
                  if (_selectedTool == 'Overlay')
                    Positioned(
                      bottom: 50,
                      right: 20,
                      child: Container(
                        width: 80,
                        height: 120,
                        color: Colors.white24,
                        child: const Center(
                          child: Text(
                            'PiP',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  // Safe Zones overlay
                  if (_selectedTool == 'Overlay')
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1, style: BorderStyle.solid),
                        ),
                        child: const Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Text('Safe Zone', style: TextStyle(color: Colors.green, fontSize: 10)),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() => _isPlaying = !_isPlaying);
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen, color: Colors.white),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Timeline Area
          Expanded(
            flex: 3,
            child: Container(
              color: context.surface,
              child: Column(
                children: [
                  // Playhead / Time ruler
                  Container(
                    height: 24,
                    color: context.surfaceMid,
                    child: Slider(
                      value: _playbackPosition,
                      onChanged: (val) {
                        setState(() => _playbackPosition = val);
                      },
                      activeColor: AppColors.brandBlue,
                      inactiveColor: context.border,
                    ),
                  ),
                  // Tracks
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        _buildTrackRow('Markers', ['Scene 1', 'Beat', 'Beat', 'Scene 2'], Colors.yellow),
                        _buildTrackRow('Text', _textTracks, Colors.orange),
                        _buildTrackRow('Effects', _effectTracks, Colors.purple),
                        _buildTrackRow('PiP/Overlay', _pipTracks, Colors.cyan),
                        _buildTrackRow('Video', _videoClips, Colors.blue),
                        _buildTrackRow('Audio', _audioTracks, Colors.green),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tools Area
          Container(
            height: 100,
            color: context.surface,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              children: [
                _buildMainToolItem('Pre-Prod', Icons.movie_creation),
                _buildMainToolItem('AI Magic', Icons.smart_toy),
                _buildMainToolItem('Edit', Icons.cut),
                _buildMainToolItem('Markers', Icons.location_on),
                _buildMainToolItem('Audio', Icons.audiotrack),
                _buildMainToolItem('Text', Icons.text_fields),
                _buildMainToolItem('Overlay', Icons.layers),
                _buildMainToolItem('Effects', Icons.star_border),
                _buildMainToolItem('Export', Icons.upload_file),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(String title, List<String> items, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              title,
              style: TextStyle(
                color: context.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: items.isEmpty ? 1 : items.length,
                itemBuilder: (context, index) {
                  if (items.isEmpty) return const SizedBox();
                  return Container(
                    width: index == 0
                        ? 120
                        : 80, // simulated varying clip lengths
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      items[index],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainToolItem(String label, IconData icon) {
    final isSelected = _selectedTool == label;
    return GestureDetector(
      onTap: () => _handleToolTap(label),
      child: Container(
        width: 70,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? AppColors.brandBlue : context.textPrimary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.brandBlue : context.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
