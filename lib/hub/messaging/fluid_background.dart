import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class FluidBackground extends StatefulWidget {
  final Widget child;
  final bool interceptGestures;
  final Offset? externalPointer;
  final bool? externalIsActive;

  const FluidBackground({
    super.key, 
    required this.child,
    this.interceptGestures = true,
    this.externalPointer,
    this.externalIsActive,
  });

  @override
  State<FluidBackground> createState() => _FluidBackgroundState();
}

class _FluidBackgroundState extends State<FluidBackground> with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final AnimationController _timeController;
  Offset _pointerPos = Offset.zero;
  bool _isActive = false;
  double _activeLerp = 0.0;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _timeController = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // Runs indefinitely
    )..repeat();
    
    _timeController.addListener(() {
      if (mounted) {
        setState(() {
          final active = widget.externalIsActive ?? _isActive;
          if (active && _activeLerp < 1.0) {
            _activeLerp += 0.04; // Smooth, quick fade in
          } else if (!active && _activeLerp > 0.0) {
            _activeLerp -= 0.015; // Elegant slow fade out
          }
          _activeLerp = _activeLerp.clamp(0.0, 1.0);
        });
      }
    });
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/fluid_trackpad.frag');
      if (mounted) {
        setState(() {
          _program = program;
        });
      }
    } catch (e) {
      debugPrint("Failed to load shader: $e");
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_program == null) {
      return widget.child; // Fallback to standard rendering if shader fails to load
    }

    // ignore: unused_local_variable
    final bool isActive = widget.externalIsActive ?? _isActive;
    final Offset pointerPos = widget.externalPointer ?? _pointerPos;

    Widget content = Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _FluidPainter(
              shader: _program!.fragmentShader(),
              time: _timeController.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0.0,
              pointer: pointerPos,
              pointerActive: _activeLerp,
            ),
          ),
        ),
        widget.child,
      ],
    );

    if (widget.interceptGestures) {
      return GestureDetector(
        onPanDown: (details) {
          setState(() {
            _isActive = true;
            _pointerPos = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _pointerPos = details.localPosition;
          });
        },
        onPanEnd: (_) => setState(() => _isActive = false),
        onPanCancel: () => setState(() => _isActive = false),
        child: content,
      );
    }

    return content;
  }
}

class _FluidPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final Offset pointer;
  final double pointerActive;

  _FluidPainter({
    required this.shader,
    required this.time,
    required this.pointer,
    required this.pointerActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 0: uSize
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    // 1: uTime
    shader.setFloat(2, time / 1000.0); // Convert to seconds
    // 2: uPointer
    shader.setFloat(3, pointer.dx);
    shader.setFloat(4, pointer.dy);
    // 3: uPointerActive
    shader.setFloat(5, pointerActive);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _FluidPainter oldDelegate) {
    return oldDelegate.time != time || 
           oldDelegate.pointer != pointer || 
           oldDelegate.pointerActive != pointerActive;
  }
}
