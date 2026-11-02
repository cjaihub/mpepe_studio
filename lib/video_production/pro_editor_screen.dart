import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/projects/models/pro_project_models.dart';
import '../backend/projects/models/effect_models.dart';
import '../backend/project_repository.dart';
import '../backend/projects/renderer/media_render_service.dart';
import '../backend/projects/renderer/render_models.dart';
import '../shared/theme/app_theme.dart';
import 'export_center_screen.dart';
import 'widgets/media_browser_panel.dart';
import 'widgets/ai_studio_panel.dart';
import 'widgets/pro_inspector_panel.dart';
import 'widgets/timeline_editor.dart';
import 'widgets/color_inspector_panel.dart';
import '../backend/projects/editor/timeline_controller.dart';
import '../backend/projects/editor/commands/clip_commands.dart';
import '../backend/projects/editor/timeline_time.dart';
import '../hub/screens/photo_studio/mask_stack_panel.dart';
import '../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../features/omni_command/omni_command_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ProEditorScreen extends StatefulWidget {
  final StudioProject project;

  const ProEditorScreen({super.key, required this.project});

  @override
  State<ProEditorScreen> createState() => _ProEditorScreenState();
}

class _ProEditorScreenState extends State<ProEditorScreen> {
  late StudioProject _project;
  late Sequence _activeSequence;
  String _activeTool = 'Media';
  Clip? _selectedClip;
  bool _showBeforePreview = false;
  List<EffectState> _effectClipboard = [];
  
  late TimelineController _timelineController;
  
  late MediaRenderService _renderService;
  late TimelineTime _sequenceTime;
  Timer? _autoSaveTimer;
  final ProjectRepository _projectRepository = ProjectRepository();
  RenderResult? _latestRender;
  int _renderRequestId = 0;
  bool _isRendering = false;
  final PreviewQuality _previewQuality = PreviewQuality.balanced;

  final List<String> _tools = [
    'Media',
    'Cut',
    'Audio',
    'Text',
    'Stickers',
    'Effects',
    'Transitions',
    'Speed',
    'Motion',
    'Color',
    'Mask',
    'AI',
    'Tracking',
    'Captions',
    'Photo',
    'Adjustments',
    'Layers',
  ];

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    // Need to re-assign if we added a sequence, but StudioProject's sequences is a final List.
    // In a real app with immutable state, we'd use copyWith. For this mockup state:
    if (_project.sequences.isEmpty) {
       _activeSequence = Sequence(
        name: 'Main Sequence',
        settings: _project.settings,
        tracks: [
          Track(name: 'V1', type: TrackType.video),
          Track(name: 'A1', type: TrackType.audio),
        ],
      );
      // Workaround for immutable list in mockup
      final mutableSequences = List<Sequence>.from(_project.sequences)..add(_activeSequence);
      _project = _project.copyWith(sequences: mutableSequences, activeSequenceId: _activeSequence.id);
    } else {
      _activeSequence = _project.sequences.firstWhere(
        (s) => s.id == _project.activeSequenceId,
        orElse: () => _project.sequences.first,
      );
    }

    _sequenceTime = TimelineTime.zero(_activeSequence.settings.frameRate);

    _timelineController = TimelineController(_activeSequence);
    _timelineController.addListener(() {
      if (mounted) {
        setState(() {});
        _requestRender();
        _scheduleAutoSave();
      }
    });

    _renderService = MediaRenderService();
    _requestRender();
  }

  Future<void> _requestRender({bool forceOriginal = false}) async {
    final currentRequestId = ++_renderRequestId;
    
    // De-bounce spinner logic: only show loading if it takes longer than 100ms
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && currentRequestId == _renderRequestId && !(_latestRender?.isSuccess ?? false)) {
        setState(() {
          _isRendering = true;
        });
      }
    });

    final request = RenderRequest(
      projectId: _project.id,
      sequenceId: _activeSequence.id,
      sequenceTime: _sequenceTime,
      target: RenderTarget.livePreview,
      quality: _previewQuality,
      bypassEffects: forceOriginal,
    );
    
    final result = await _renderService.render(_project, request);
    
    if (mounted && currentRequestId == _renderRequestId) {
      setState(() {
        _latestRender = result;
        _isRendering = false;
      });
    }
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        // Find existing sequences and replace the active one
        final updatedSequences = [
          for (var seq in _project.sequences)
            if (seq.id == _activeSequence.id) _activeSequence else seq
        ];
        
        // If it was a new sequence that wasn't in _project yet, add it
        if (!updatedSequences.any((s) => s.id == _activeSequence.id)) {
          updatedSequences.add(_activeSequence);
        }

        _project = _project.copyWith(sequences: updatedSequences);
        _projectRepository.updateProject(_project);
      }
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _timelineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    
    return Scaffold(
      backgroundColor: context.bg,
      appBar: _buildAppBar(),
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
      floatingActionButton: OmniCommandButton(
        omniContext: OmniContext(
          sessionId: buildOmniSessionId(),
          userId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
          surface: 'pro_editor',
          projectId: _project.id,
          sequenceId: _activeSequence.id,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.darkSurface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          HapticFeedback.lightImpact();
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/hub/home');
          }
        },
      ),
      title: Row(
        children: [
          Text(
            _project.title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(width: 16),
          _buildMetadataBadge('${_activeSequence.settings.width}x${_activeSequence.settings.height}'),
          const SizedBox(width: 8),
          _buildMetadataBadge('${_activeSequence.settings.frameRate} fps'),
          const SizedBox(width: 8),
          _buildMetadataBadge(_activeSequence.settings.colorSpace),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.undo, color: _timelineController.canUndo ? Colors.white : Colors.white30),
          onPressed: _timelineController.canUndo ? () => _timelineController.undo() : null,
        ),
        IconButton(
          icon: Icon(Icons.redo, color: _timelineController.canRedo ? Colors.white : Colors.white30),
          onPressed: _timelineController.canRedo ? () => _timelineController.redo() : null,
        ),
        IconButton(icon: const Icon(Icons.history, color: Colors.white), onPressed: () {}),
        const SizedBox(width: 16),
        if (_selectedClip != null) ...[
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copy Effects',
            onPressed: () {
              if (_selectedClip != null) {
                setState(() {
                  _effectClipboard = List.from(_selectedClip!.effects.map((e) => e.copyWith()));
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.paste, color: Colors.white),
            tooltip: 'Paste Effects',
            onPressed: _effectClipboard.isEmpty
                ? null
                : () {
                    setState(() {
                      _selectedClip!.effects.addAll(_effectClipboard.map((e) => e.copyWith(id: null)));
                    });
                  },
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: AppColors.onerovaGold),
            tooltip: 'AI Effect Assistant',
            onPressed: () {
              // AI Effect Assistant placeholder
            },
          ),
        ],
        const SizedBox(width: 16),
        Center(
          child: Text(
            'Autosaved',
            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(icon: const Icon(Icons.cloud_done, color: AppColors.textPrimary), onPressed: () {}),
        IconButton(icon: const Icon(Icons.play_arrow, color: Colors.white), onPressed: () {}),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ExportCenterScreen(project: _project),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Export', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighlight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Row(
            children: [
              _buildToolRail(),
              _buildLeftPanel(),
              Expanded(child: _buildViewer()),
              if (_selectedClip != null)
                _activeTool == 'Color'
                    ? ColorInspectorPanel(
                        clip: _selectedClip!,
                        onStateChanged: () => setState(() {}),
                      )
                    : ProInspectorPanel(selectedClip: _selectedClip),
              if (_selectedClip == null)
                Container(
                  width: 320,
                  color: AppColors.darkSurface,
                  child: Center(
                    child: Text('Select a clip', style: GoogleFonts.inter(color: AppColors.textSecondary)),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.darkSurfaceHighlight),
        Expanded(
          flex: 1,
          child: _buildTimeline(),
        ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    switch (_activeTool) {
      case 'Media':
        return MediaBrowserPanel(
          project: _project,
          onAddClip: (clip) {
            setState(() {
              _activeSequence.tracks[0].clips.add(clip);
            });
          },
        );
      case 'AI':
        return AiStudioPanel(project: _project);
      case 'Mask':
        return const MaskStackPanel();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: _buildViewer(),
        ),
        _buildMobileToolbar(),
        const Divider(height: 1, color: AppColors.darkSurfaceHighlight),
        Expanded(
          flex: 3,
          child: _buildTimeline(),
        ),
      ],
    );
  }

  Widget _buildToolRail() {
    return Container(
      width: 80,
      color: AppColors.darkSurface,
      child: ListView.builder(
        itemCount: _tools.length,
        itemBuilder: (context, index) {
          final tool = _tools[index];
          final isActive = tool == _activeTool;
          return InkWell(
            onTap: () {
              setState(() {
                _activeTool = tool;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isActive ? AppColors.brandBlue : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getIconForTool(tool),
                    color: isActive ? AppColors.brandBlue : AppColors.textSecondary,
                    size: isActive ? 24 : 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Colors.white : AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileToolbar() {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tools.length,
        itemBuilder: (context, index) {
          final tool = _tools[index];
          final isActive = tool == _activeTool;
          return InkWell(
            onTap: () {
              setState(() {
                _activeTool = tool;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getIconForTool(tool),
                    color: isActive ? AppColors.brandBlue : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewer() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          _buildRenderedPreview(),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: () {}),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
                  onPressed: () {},
                ),
                IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: () {}),
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                GestureDetector(
                  onTapDown: (_) {
                    setState(() => _showBeforePreview = true);
                    _requestRender(forceOriginal: true);
                  },
                  onTapUp: (_) {
                    setState(() => _showBeforePreview = false);
                    _requestRender();
                  },
                  onTapCancel: () {
                    setState(() => _showBeforePreview = false);
                    _requestRender();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _showBeforePreview ? AppColors.brandBlue : Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Before/After',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Fit',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRenderedPreview() {
    Widget content;

    if (_latestRender != null && _latestRender!.isSuccess) {
      // 1. Frame is valid and successfully rendered by the graph
      content = Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // MOCK of the actual Image pixel buffer:
              // if (_latestRender!.frame?.image != null) 
              //   RawImage(image: _latestRender!.frame!.image),
              // We simulate the canvas drawing here for architectural demonstration
              Container(
                width: 320,
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _showBeforePreview 
                        ? [Colors.grey.shade800, Colors.grey.shade900]
                        : [Colors.blueGrey.shade800, Colors.blueGrey.shade900],
                  ),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Text(
                    _showBeforePreview ? 'RAW FRAME\n(No Color/Effects)' : 'RENDERED FRAME\nSequence Time: ${_sequenceTime.toSeconds.toStringAsFixed(2)}s',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_latestRender != null && !_latestRender!.isSuccess) {
      // 2. Render Error / Diagnostic failure
      content = Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'RENDER ERROR\n${_latestRender!.diagnostics.isNotEmpty ? _latestRender!.diagnostics.first.message : "Unknown error"}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _requestRender(forceOriginal: _showBeforePreview),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkSurfaceHighlight),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    } else {
      // 3. Initial Loading State
      content = const Center(
        child: AnimatedLoadingIndicator(color: AppColors.brandBlue),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        // Non-blocking indicator for delayed scrubbing
        if (_isRendering)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: AnimatedLoadingIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text('Rendering...', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        // Persistent diagnostic overlay
        if (_latestRender != null)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.black54,
              child: Text(
                'Render Time: ${_latestRender!.renderTime.inMilliseconds}ms | Engine: RenderGraph | Status: ${_latestRender!.isSuccess ? "OK" : "ERR"}',
                style: GoogleFonts.inter(
                  color: _latestRender!.isSuccess ? Colors.greenAccent : Colors.redAccent, 
                  fontSize: 10, 
                  fontWeight: FontWeight.w600
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeline() {
    return Container(
      color: AppColors.darkBackground,
      child: TimelineEditor(
        sequence: _activeSequence,
        selectedClip: _selectedClip,
        initialPlayhead: _sequenceTime,
        onClipSelected: (clip) {
          setState(() {
            _selectedClip = clip;
          });
        },
        onClipTrimStart: (clip, newStart) {
          final maxStart = clip.startTime + clip.duration - 0.1;
          final validStart = newStart.clamp(0.0, maxStart);
          final diff = validStart - clip.startTime;
          
          final command = TrimClipCommand(
            trackId: _activeSequence.tracks.firstWhere((t) => t.clips.contains(clip)).id,
            clipId: clip.id,
            oldStartTime: clip.startTime,
            newStartTime: validStart,
            oldDuration: clip.duration,
            newDuration: clip.duration - diff,
            oldSourceStart: clip.sourceStart,
            newSourceStart: clip.sourceStart + diff,
          );
          _timelineController.execute(command);
        },
        onClipTrimEnd: (clip, newDuration) {
          final validDuration = newDuration.clamp(0.1, double.infinity);
          final command = TrimClipCommand(
            trackId: _activeSequence.tracks.firstWhere((t) => t.clips.contains(clip)).id,
            clipId: clip.id,
            oldStartTime: clip.startTime,
            newStartTime: clip.startTime,
            oldDuration: clip.duration,
            newDuration: validDuration,
            oldSourceStart: clip.sourceStart,
            newSourceStart: clip.sourceStart,
          );
          _timelineController.execute(command);
        },
        onClipMoved: (clip, newStart) {
          final validStart = newStart.clamp(0.0, double.infinity);
          final trackId = _activeSequence.tracks.firstWhere((t) => t.clips.contains(clip)).id;
          
          if (_timelineController.canMoveClip(trackId, clip.id, validStart)) {
            final command = MoveClipCommand(
              clipId: clip.id,
              sourceTrackId: trackId,
              targetTrackId: trackId,
              oldStartTime: clip.startTime,
              newStartTime: validStart,
            );
            _timelineController.execute(command);
          }
        },
        onPlayheadMoved: (time) {
          _sequenceTime = time;
          _requestRender();
        },
      ),
    );
  }

  IconData _getIconForTool(String tool) {
    switch (tool) {
      case 'Media': return Icons.perm_media;
      case 'Cut': return Icons.cut;
      case 'Audio': return Icons.audiotrack;
      case 'Text': return Icons.title;
      case 'Stickers': return Icons.emoji_emotions;
      case 'Effects': return Icons.auto_awesome;
      case 'Transitions': return Icons.compare_arrows;
      case 'Speed': return Icons.speed;
      case 'Motion': return Icons.transform;
      case 'Color': return Icons.color_lens;
      case 'Mask': return Icons.format_shapes;
      case 'AI': return Icons.psychology;
      case 'Tracking': return Icons.gps_fixed;
      case 'Captions': return Icons.subtitles;
      case 'Photo': return Icons.photo_camera;
      case 'Adjustments': return Icons.tune;
      case 'Layers': return Icons.layers;
      default: return Icons.build;
    }
  }
}
