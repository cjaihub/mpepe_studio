import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/projects/models/pro_project_models.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/projects/editor/timeline_layout.dart';
import '../../backend/projects/editor/timeline_time.dart';

class TimelineEditor extends StatefulWidget {
  final Sequence sequence;
  final Clip? selectedClip;
  final Function(Clip?) onClipSelected;
  final Function(Clip, double) onClipTrimStart;
  final Function(Clip, double) onClipTrimEnd;
  final Function(Clip, double) onClipMoved;
  final Function(TimelineTime)? onPlayheadMoved;
  final TimelineTime initialPlayhead;

  const TimelineEditor({
    super.key,
    required this.sequence,
    required this.selectedClip,
    required this.onClipSelected,
    required this.onClipTrimStart,
    required this.onClipTrimEnd,
    required this.onClipMoved,
    this.onPlayheadMoved,
    required this.initialPlayhead,
  });

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  double _horizontalScrollOffset = 0.0;
  double _verticalScrollOffset = 0.0;
  double _pixelsPerSecond = 50.0;
  late TimelineTime _playheadTime;
  
  final double _trackHeight = 80.0;
  final double _rulerHeight = 24.0;
  final double _trackHeaderWidth = 120.0;
  final double _overscanPixels = 800.0; // Configurable overscan

  late TimelineLayout _layout;

  @override
  void initState() {
    super.initState();
    _playheadTime = widget.initialPlayhead;
    _updateLayout();
  }

  @override
  void didUpdateWidget(TimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlayhead != widget.initialPlayhead) {
      _playheadTime = widget.initialPlayhead;
    }
    _updateLayout();
  }

  void _updateLayout() {
    _layout = TimelineLayout(
      pixelsPerSecond: _pixelsPerSecond,
      frameRate: widget.sequence.settings.frameRate,
    );
  }

  double _getMaxTimelinePixels() {
    double maxSeconds = 30.0; // Minimum 30 seconds canvas
    for (var track in widget.sequence.tracks) {
      for (var clip in track.clips) {
        maxSeconds = max(maxSeconds, clip.startTime + clip.duration);
      }
    }
    // Add 10 seconds of padding at the end
    return _layout.secondsToPixels(maxSeconds + 10.0);
  }

  double _getMaxVerticalPixels() {
    return widget.sequence.tracks.length * _trackHeight;
  }


  void _handleScaleUpdate(ScaleUpdateDetails details, BoxConstraints constraints) {
    if (details.scale != 1.0) {
      setState(() {
        _pixelsPerSecond = (_pixelsPerSecond * details.scale).clamp(10.0, 1000.0);
        _updateLayout();
      });
    } else {
      // It's a pan/drag with two fingers or trackpad
      setState(() {
        _horizontalScrollOffset -= details.focalPointDelta.dx;
        _verticalScrollOffset -= details.focalPointDelta.dy;

        final maxHScroll = max(0.0, _getMaxTimelinePixels() - constraints.maxWidth + _trackHeaderWidth);
        _horizontalScrollOffset = _horizontalScrollOffset.clamp(0.0, maxHScroll);

        final maxVScroll = max(0.0, _getMaxVerticalPixels() - constraints.maxHeight + _rulerHeight);
        _verticalScrollOffset = _verticalScrollOffset.clamp(0.0, maxVScroll);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTimelineToolbar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onScaleUpdate: (details) => _handleScaleUpdate(details, constraints),
                child: Container(
                  color: AppColors.darkBackground,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left side: Track Headers (fixed width, vertically scrolls)
                      _buildTrackHeadersColumn(constraints.maxHeight),
                      // Right side: Ruler and Tracks Area (2D scrolling)
                      Expanded(
                        child: Column(
                          children: [
                            _buildRuler(constraints.maxWidth - _trackHeaderWidth),
                            Expanded(
                              child: _buildVirtualizedTracksArea(constraints.maxWidth - _trackHeaderWidth, constraints.maxHeight - _rulerHeight),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.darkSurfaceHighlight,
      child: Row(
        children: [
          Icon(Icons.timeline, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 8),
          Text(
            widget.sequence.name,
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.content_cut, color: Colors.white, size: 18), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white, size: 18),
            onPressed: () {
              setState(() {
                _pixelsPerSecond = (_pixelsPerSecond * 0.8).clamp(10.0, 1000.0);
                _updateLayout();
              });
            },
          ),
          Slider(
            value: _pixelsPerSecond,
            min: 10,
            max: 1000,
            activeColor: AppColors.brandBlue,
            onChanged: (val) {
              setState(() {
                _pixelsPerSecond = val;
                _updateLayout();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
            onPressed: () {
              setState(() {
                _pixelsPerSecond = (_pixelsPerSecond * 1.2).clamp(10.0, 1000.0);
                _updateLayout();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrackHeadersColumn(double maxHeight) {
    return SizedBox(
      width: _trackHeaderWidth,
      child: Column(
        children: [
          // Corner empty space for ruler
          Container(
            height: _rulerHeight,
            color: AppColors.darkSurface,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            child: Text('00:00:00:00', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 10)),
          ),
          // Scrollable track headers
          Expanded(
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(0, -_verticalScrollOffset),
                child: Column(
                  children: widget.sequence.tracks.map((track) {
                    return Container(
                      height: _trackHeight,
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        border: Border(bottom: BorderSide(color: AppColors.darkSurfaceHighlight)),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.name,
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          Row(
                            children: [
                              Icon(
                                track.isHidden ? Icons.visibility_off : Icons.visibility,
                                color: AppColors.textSecondary,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                track.isLocked ? Icons.lock : Icons.lock_open,
                                color: AppColors.textSecondary,
                                size: 16,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuler(double width) {
    return GestureDetector(
      onPanUpdate: (details) {
        final localDx = details.localPosition.dx;
        final absoluteDx = _horizontalScrollOffset + localDx;
        setState(() {
          _playheadTime = _layout.pixelsToTime(absoluteDx);
        });
        widget.onPlayheadMoved?.call(_playheadTime);
      },
      onTapDown: (details) {
        final localDx = details.localPosition.dx;
        final absoluteDx = _horizontalScrollOffset + localDx;
        setState(() {
          _playheadTime = _layout.pixelsToTime(absoluteDx);
        });
        widget.onPlayheadMoved?.call(_playheadTime);
      },
      child: Container(
        height: _rulerHeight,
        width: width,
        color: AppColors.darkSurfaceHighlight.withValues(alpha: 0.5),
        child: CustomPaint(
          size: Size(width, _rulerHeight),
          painter: VirtualizedTimeRulerPainter(
            layout: _layout,
            horizontalScrollOffset: _horizontalScrollOffset,
            frameRate: widget.sequence.settings.frameRate,
          ),
        ),
      ),
    );
  }

  Widget _buildVirtualizedTracksArea(double viewportWidth, double viewportHeight) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        widget.onClipSelected(null);
      },
      child: ClipRect(
        child: Stack(
          children: [
            // Background Grid (Optional)

            // Tracks & Clips
            ..._buildVisibleTracksAndClips(viewportWidth, viewportHeight),
            
            // Playhead
            _buildPlayhead(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildVisibleTracksAndClips(double viewportWidth, double viewportHeight) {
    final List<Widget> widgets = [];
    final startY = _verticalScrollOffset - _overscanPixels;
    final endY = _verticalScrollOffset + viewportHeight + _overscanPixels;
    
    final startX = _horizontalScrollOffset - _overscanPixels;
    final endX = _horizontalScrollOffset + viewportWidth + _overscanPixels;

    for (int i = 0; i < widget.sequence.tracks.length; i++) {
      final track = widget.sequence.tracks[i];
      final trackTop = i * _trackHeight;
      final trackBottom = trackTop + _trackHeight;

      // Vertical Culling
      if (trackBottom < startY || trackTop > endY) {
        continue;
      }

      // Draw track background separator
      widgets.add(
        Positioned(
          left: 0,
          right: 0,
          top: trackTop - _verticalScrollOffset,
          height: _trackHeight,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.darkSurfaceHighlight),
              ),
            ),
          ),
        ),
      );

      // Horizontal Clip Culling
      final visibleClips = _layout.getVisibleClips(track, startX, endX);
      for (var clip in visibleClips) {
        widgets.add(_buildClipWidget(clip, trackTop - _verticalScrollOffset));
      }
    }
    return widgets;
  }

  Widget _buildClipWidget(Clip clip, double trackTopInViewport) {
    final isSelected = widget.selectedClip?.id == clip.id;
    final absoluteLeft = _layout.secondsToPixels(clip.startTime);
    final width = _layout.secondsToPixels(clip.duration);
    
    // Convert to viewport coordinates
    final leftInViewport = absoluteLeft - _horizontalScrollOffset;

    return Positioned(
      left: leftInViewport,
      top: trackTopInViewport + 8, // Padding inside track
      height: _trackHeight - 16,
      width: width,
      child: GestureDetector(
        onTap: () {
          widget.onClipSelected(clip);
        },
        onHorizontalDragUpdate: (details) {
          final deltaSeconds = details.delta.dx / _pixelsPerSecond;
          widget.onClipMoved(clip, clip.startTime + deltaSeconds);
        },
        child: Container(
          decoration: BoxDecoration(
            color: clip.type == MediaType.audio ? Colors.teal : AppColors.brandBlue,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  clip.type.name.toUpperCase(),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              // Trim Handles
              if (isSelected) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final deltaSeconds = details.delta.dx / _pixelsPerSecond;
                      widget.onClipTrimStart(clip, clip.startTime + deltaSeconds);
                    },
                    child: Container(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final deltaSeconds = details.delta.dx / _pixelsPerSecond;
                      widget.onClipTrimEnd(clip, clip.duration + deltaSeconds);
                    },
                    child: Container(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              ],
              // Keyframe and Tracking Indicators
              ...clip.keyframes.map((kf) {
                final kfX = _layout.secondsToPixels(kf.time);
                return Positioned(
                  left: kfX - 4,
                  bottom: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.onerovaGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
              if (clip.tracking.isNotEmpty || clip.masks.any((m) => m.trackingReference != null || m.tracking.isNotEmpty))
                Positioned(
                  left: 8,
                  top: 4,
                  child: Icon(Icons.my_location, color: Colors.white70, size: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayhead() {
    final absoluteX = _layout.timeToPixels(_playheadTime);
    final viewportX = absoluteX - _horizontalScrollOffset;

    if (viewportX < 0 || viewportX > 10000) return const SizedBox.shrink();

    return Positioned(
      left: viewportX,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        color: AppColors.brandBlue,
      ),
    );
  }
}

class VirtualizedTimeRulerPainter extends CustomPainter {
  final TimelineLayout layout;
  final double horizontalScrollOffset;
  final double frameRate;

  VirtualizedTimeRulerPainter({
    required this.layout,
    required this.horizontalScrollOffset,
    required this.frameRate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 1;

    final textStyle = GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 10);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Calculate which second we start rendering at
    final startSeconds = max(0, (horizontalScrollOffset / layout.pixelsPerSecond).floor());
    // Calculate how many seconds fit in the viewport width
    final endSeconds = startSeconds + (size.width / layout.pixelsPerSecond).ceil() + 1;

    for (int s = startSeconds; s <= endSeconds; s++) {
      final absoluteX = layout.secondsToPixels(s.toDouble());
      final viewportX = absoluteX - horizontalScrollOffset;

      if (viewportX < 0 || viewportX > size.width) continue;

      // Major tick (Seconds)
      canvas.drawLine(Offset(viewportX, 12), Offset(viewportX, 24), paint);
      
      textPainter.text = TextSpan(text: '00:${s.toString().padLeft(2, '0')}', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(viewportX + 2, 2));

      // Minor ticks (Frames or Sub-seconds)
      if (layout.pixelsPerSecond > 100) {
        final frames = frameRate.toInt();
        final pixelPerFrame = layout.pixelsPerSecond / frames;
        for (int f = 1; f < frames; f++) {
          final fViewportX = viewportX + (f * pixelPerFrame);
          if (fViewportX > size.width) break;
          canvas.drawLine(Offset(fViewportX, 18), Offset(fViewportX, 24), paint);
        }
      } else if (layout.pixelsPerSecond > 50) {
        // Just half second
        final halfX = viewportX + (layout.pixelsPerSecond / 2);
        if (halfX <= size.width) {
          canvas.drawLine(Offset(halfX, 16), Offset(halfX, 24), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant VirtualizedTimeRulerPainter oldDelegate) {
    return oldDelegate.horizontalScrollOffset != horizontalScrollOffset ||
           oldDelegate.layout.pixelsPerSecond != layout.pixelsPerSecond;
  }
}
