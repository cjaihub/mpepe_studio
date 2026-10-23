import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/shared/theme/app_theme.dart';

enum CurveChannel { rgb, red, green, blue }

class CurvesEditor extends StatefulWidget {
  final List<Offset> points;
  final ValueChanged<List<Offset>> onChanged;
  final CurveChannel initialChannel;
  final ValueChanged<CurveChannel>? onChannelChanged;

  const CurvesEditor({
    super.key,
    required this.points,
    required this.onChanged,
    this.initialChannel = CurveChannel.rgb,
    this.onChannelChanged,
  });

  @override
  State<CurvesEditor> createState() => _CurvesEditorState();
}

class _CurvesEditorState extends State<CurvesEditor> {
  int? _draggedPointIndex;
  late CurveChannel _currentChannel;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.initialChannel;
  }

  Color _getChannelColor(CurveChannel channel) {
    switch (channel) {
      case CurveChannel.rgb:
        return Colors.white;
      case CurveChannel.red:
        return const Color(0xFFFF4B4B);
      case CurveChannel.green:
        return const Color(0xFF2ECC71);
      case CurveChannel.blue:
        return AppColors.brandBlue;
    }
  }

  String _getChannelName(CurveChannel channel) {
    switch (channel) {
      case CurveChannel.rgb:
        return 'RGB';
      case CurveChannel.red:
        return 'Red';
      case CurveChannel.green:
        return 'Green';
      case CurveChannel.blue:
        return 'Blue';
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelColor = _getChannelColor(_currentChannel);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 210.0;
        final curveHeight = (availableHeight - 56.0).clamp(100.0, 150.0);
        final curveWidth = totalWidth - 32;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Channel Selector Bar & Reset Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: CurveChannel.values.map((channel) {
                      final isSelected = _currentChannel == channel;
                      final col = _getChannelColor(channel);
                      return GestureDetector(
                        onTap: () {
                          setState(() => _currentChannel = channel);
                          widget.onChannelChanged?.call(channel);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected ? col.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: isSelected ? col : Colors.transparent,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: col,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _getChannelName(channel),
                                style: GoogleFonts.inter(
                                  color: isSelected ? Colors.white : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  GestureDetector(
                    onTap: () {
                      widget.onChanged(const [Offset(0.0, 0.0), Offset(1.0, 1.0)]);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        'Reset',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Interactive Curve Canvas
              GestureDetector(
                onPanStart: (details) {
                  final localPos = details.localPosition;
                  double minDistance = double.infinity;
                  int? nearestIndex;

                  for (int i = 0; i < widget.points.length; i++) {
                    final p = _denormalize(widget.points[i], curveWidth, curveHeight);
                    final dist = (p - localPos).distance;
                    if (dist < 32 && dist < minDistance) {
                      minDistance = dist;
                      nearestIndex = i;
                    }
                  }

                  if (nearestIndex != null) {
                    setState(() => _draggedPointIndex = nearestIndex);
                  } else if (widget.points.length < 6) {
                    // Tap to add new control point
                    final normPt = _normalize(localPos, curveWidth, curveHeight);
                    final newPoints = List<Offset>.from(widget.points)..add(normPt);
                    newPoints.sort((a, b) => a.dx.compareTo(b.dx));
                    widget.onChanged(newPoints);
                    setState(() {
                      _draggedPointIndex = newPoints.indexOf(normPt);
                    });
                  }
                },
                onPanUpdate: (details) {
                  if (_draggedPointIndex != null) {
                    final newPoint = _normalize(details.localPosition, curveWidth, curveHeight);
                    double x = newPoint.dx.clamp(0.0, 1.0);
                    double y = newPoint.dy.clamp(0.0, 1.0);

                    // Prevent crossing neighboring points
                    if (_draggedPointIndex! > 0) {
                      x = x.clamp(widget.points[_draggedPointIndex! - 1].dx + 0.01, 1.0);
                    }
                    if (_draggedPointIndex! < widget.points.length - 1) {
                      x = x.clamp(0.0, widget.points[_draggedPointIndex! + 1].dx - 0.01);
                    }

                    final newPoints = List<Offset>.from(widget.points);
                    newPoints[_draggedPointIndex!] = Offset(x, y);
                    widget.onChanged(newPoints);
                  }
                },
                onPanEnd: (_) {
                  setState(() => _draggedPointIndex = null);
                },
                child: SizedBox(
                  width: curveWidth,
                  height: curveHeight,
                  child: CustomPaint(
                    painter: _CurvesPainter(
                      points: widget.points,
                      activePointIndex: _draggedPointIndex,
                      curveColor: channelColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Offset _denormalize(Offset normalized, double width, double height) {
    return Offset(
      normalized.dx * width,
      (1.0 - normalized.dy) * height,
    );
  }

  Offset _normalize(Offset local, double width, double height) {
    return Offset(
      (local.dx / width).clamp(0.0, 1.0),
      (1.0 - (local.dy / height)).clamp(0.0, 1.0),
    );
  }
}

class _CurvesPainter extends CustomPainter {
  final List<Offset> points;
  final int? activePointIndex;
  final Color curveColor;

  _CurvesPainter({
    required this.points,
    this.activePointIndex,
    required this.curveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final x = size.width * (i / 4);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Diagonal reference line
    final diagPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagPaint);

    if (points.isEmpty) return;

    // 2. Draw Spline
    final linePaint = Paint()
      ..color = curveColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final p0 = _toScreen(points[0], size);
    path.moveTo(p0.dx, p0.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final cur = _toScreen(points[i], size);
      final next = _toScreen(points[i + 1], size);
      final midX = (cur.dx + next.dx) / 2;
      path.cubicTo(midX, cur.dy, midX, next.dy, next.dx, next.dy);
    }
    canvas.drawPath(path, linePaint);

    // 3. Draw Points
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final activePointPaint = Paint()
      ..color = curveColor
      ..style = PaintingStyle.fill;

    final ringPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final p = _toScreen(points[i], size);
      final isActive = i == activePointIndex;
      canvas.drawCircle(p, isActive ? 7.5 : 5.5, isActive ? activePointPaint : pointPaint);
      canvas.drawCircle(p, isActive ? 7.5 : 5.5, ringPaint);
    }
  }

  Offset _toScreen(Offset normalized, Size size) {
    return Offset(
      normalized.dx * size.width,
      (1.0 - normalized.dy) * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvesPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.activePointIndex != activePointIndex ||
        oldDelegate.curveColor != curveColor;
  }
}
