import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/photo_studio/photo_studio_models.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_provider.dart';
import 'package:oneova/backend/mask_engine/mask_layer_manager.dart';
import 'package:oneova/backend/mask_engine/mask_coordinate_transformer.dart';
import 'dart:math' as math;

class DeterministicRenderView extends ConsumerStatefulWidget {
  final PhotoProject project;

  const DeterministicRenderView({super.key, required this.project});

  @override
  ConsumerState<DeterministicRenderView> createState() => _DeterministicRenderViewState();
}

class _DeterministicRenderViewState extends ConsumerState<DeterministicRenderView> {
  List<Offset> _currentStroke = [];
  bool _isDrawing = false;
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In a real RAW engine, this would be a Metal/OpenGL shader or C++ WebAssembly module.
    // For this prototype, we'll compose ColorFilters to simulate the pipeline.
    
    final layerManager = ref.watch(maskLayerManagerProvider);
    
    // Default to identity matrix
    List<double> composedMatrix = [
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];

    if (widget.project.currentGraph.layers.isNotEmpty) {
      final globalLayer = widget.project.currentGraph.layers.first;
      
      double exposure = _getParam(globalLayer, AdjustmentType.EXPOSURE, 0.0);
      double contrast = _getParam(globalLayer, AdjustmentType.CONTRAST, 0.0);
      double saturation = _getParam(globalLayer, AdjustmentType.SATURATION, 0.0);
      double temperature = _getParam(globalLayer, AdjustmentType.TEMPERATURE, 0.0);
      double tint = _getParam(globalLayer, AdjustmentType.TINT, 0.0);

      // 1. Exposure (Brightness) -> Multiplier
      // Scale exposure from [-1, 1] to [0.5, 2.0]
      double expFactor = math.pow(2.0, exposure).toDouble();
      List<double> expMatrix = [
        expFactor, 0, 0, 0, 0,
        0, expFactor, 0, 0, 0,
        0, 0, expFactor, 0, 0,
        0, 0, 0, 1, 0,
      ];
      composedMatrix = _multiplyMatrices(composedMatrix, expMatrix);

      // 2. Contrast
      // Scale contrast from [-1, 1] to [0.5, 2.0]
      double contFactor = math.pow(2.0, contrast).toDouble();
      double contOffset = 128 * (1 - contFactor);
      List<double> contMatrix = [
        contFactor, 0, 0, 0, contOffset,
        0, contFactor, 0, 0, contOffset,
        0, 0, contFactor, 0, contOffset,
        0, 0, 0, 1, 0,
      ];
      composedMatrix = _multiplyMatrices(composedMatrix, contMatrix);
      
      // 3. Saturation
      double satFactor = 1.0 + saturation; // [-1, 1] -> [0, 2]
      double lumR = 0.3086;
      double lumG = 0.6094;
      double lumB = 0.0820;
      double satR = (1 - satFactor) * lumR;
      double satG = (1 - satFactor) * lumG;
      double satB = (1 - satFactor) * lumB;
      List<double> satMatrix = [
        satR + satFactor, satG, satB, 0, 0,
        satR, satG + satFactor, satB, 0, 0,
        satR, satG, satB + satFactor, 0, 0,
        0, 0, 0, 1, 0,
      ];
      composedMatrix = _multiplyMatrices(composedMatrix, satMatrix);
      
      // 4. White Balance (Temp/Tint)
      // Very basic approximation
      double rScale = 1.0 + (temperature * 0.2) + (tint * 0.1);
      double gScale = 1.0 - (tint * 0.2);
      double bScale = 1.0 - (temperature * 0.2) + (tint * 0.1);
      List<double> wbMatrix = [
        rScale, 0, 0, 0, 0,
        0, gScale, 0, 0, 0,
        0, 0, bScale, 0, 0,
        0, 0, 0, 1, 0,
      ];
      composedMatrix = _multiplyMatrices(composedMatrix, wbMatrix);
    }

    // Conditionally show base image based on display mode
    Widget baseImage;
    final imageUri = widget.project.originalAsset.uri;
    if (imageUri.isNotEmpty && !imageUri.startsWith('http')) {
      baseImage = ColorFiltered(
        colorFilter: ColorFilter.matrix(composedMatrix),
        child: Image.file(
          File(imageUri),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white24, size: 100),
        ),
      );
    } else {
      baseImage = ColorFiltered(
        colorFilter: ColorFilter.matrix(composedMatrix),
        child: Image.network(
          imageUri.isNotEmpty ? imageUri : 'https://images.unsplash.com/photo-1542291026-7eec264c27ff',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white24, size: 100),
        ),
      );
    }

    if (layerManager.displayMode == MaskDisplayMode.maskOnly) {
      baseImage = Container(color: Colors.black); // Base is black in mask only
    } else if (layerManager.displayMode == MaskDisplayMode.checkerboard) {
      // Mock checkerboard background
      baseImage = Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage('https://upload.wikimedia.org/wikipedia/commons/7/70/Checkerboard_pattern.svg'),
            repeat: ImageRepeat.repeat,
          )
        ),
      );
    }

    return ListenableBuilder(
      listenable: layerManager,
      builder: (context, child) {
        return Stack(
          children: [
            // Gesture Handler OUTSIDE InteractiveViewer to allow custom matrix math
            GestureDetector(
              onTapUp: (details) async {
                final widgetSize = MediaQuery.of(context).size;
                const imageSize = Size(1000, 667); 
                
                final normPt = MaskCoordinateTransformer.screenToNormalizedImage(
                  details.localPosition,
                  widgetSize,
                  imageSize,
                  BoxFit.contain,
                  transformMatrix: _transformController.value,
                );
                
                final engine = ref.read(maskEngineProvider);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing Tap Selection...')));
                try {
                  await engine.addPointMask('local_media', normPt.dx, normPt.dy);
                } catch(e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: const TextStyle(color: Colors.red))));
                  }
                }
              },
              onPanStart: (details) {
                setState(() {
                  _isDrawing = true;
                  _currentStroke = [details.localPosition];
                });
              },
              onPanUpdate: (details) {
                if (_isDrawing) {
                  // Stroke Throttling: only add point if it moved at least 5 pixels
                  if (_currentStroke.isEmpty || (details.localPosition - _currentStroke.last).distance > 5.0) {
                    setState(() {
                      _currentStroke.add(details.localPosition);
                    });
                  }
                }
              },
              onPanEnd: (details) async {
                if (!_isDrawing) return;
                setState(() => _isDrawing = false);
                
                if (_currentStroke.length > 2) {
                  final widgetSize = MediaQuery.of(context).size;
                  const imageSize = Size(1000, 667); 
    
                  final normPoints = _currentStroke.map((pt) {
                    final norm = MaskCoordinateTransformer.screenToNormalizedImage(
                      pt,
                      widgetSize,
                      imageSize,
                      BoxFit.contain,
                      transformMatrix: _transformController.value,
                    );
                    return {'x': norm.dx, 'y': norm.dy};
                  }).toList();
                  
                  final engine = ref.read(maskEngineProvider);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing Brush Stroke...')));
                  try {
                    await engine.addStrokeMask('local_media', normPoints);
                  } catch(e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: const TextStyle(color: Colors.red))));
                    }
                  }
                }
                _currentStroke.clear();
              },
              child: Container(
                color: Colors.transparent, // Capture taps
                child: InteractiveViewer(
                  transformationController: _transformController,
                  panEnabled: false, // Disable built-in pan to allow brush
                  scaleEnabled: true,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      baseImage,
                      // Mask Overlay
                      if (layerManager.displayMode != MaskDisplayMode.normal)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MaskOverlayPainter(
                              layers: layerManager.layers,
                              displayMode: layerManager.displayMode,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Local drawing overlay on top of EVERYTHING
            if (_isDrawing)
              IgnorePointer(
                child: Positioned.fill(
                  child: CustomPaint(
                    painter: _LocalStrokePainter(
                      stroke: _currentStroke,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            // Display Mode Toggle
            Positioned(
              top: 16,
              right: 16,
              child: _buildDisplayModeSelector(context, layerManager),
            ),
          ],
        );
      }
    );
  }

  Widget _buildDisplayModeSelector(BuildContext context, MaskLayerManager layerManager) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MaskDisplayMode>(
          value: layerManager.displayMode,
          dropdownColor: Colors.black87,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          onChanged: (MaskDisplayMode? newValue) {
            if (newValue != null) {
              layerManager.setDisplayMode(newValue);
            }
          },
          items: MaskDisplayMode.values.map<DropdownMenuItem<MaskDisplayMode>>((MaskDisplayMode value) {
            return DropdownMenuItem<MaskDisplayMode>(
              value: value,
              child: Text(value.name.toUpperCase()),
            );
          }).toList(),
        ),
      ),
    );
  }

  double _getParam(PhotoLayer layer, AdjustmentType type, double defaultValue) {
    try {
      final adj = layer.adjustments.firstWhere((a) => a.type == type);
      return (adj.parameters['value'] as num?)?.toDouble() ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  List<double> _multiplyMatrices(List<double> a, List<double> b) {
    List<double> result = List.filled(20, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        for (int k = 0; k < 4; k++) {
          result[i * 5 + j] += a[i * 5 + k] * b[k * 5 + j];
        }
      }
    }
    // Add offsets
    for (int i = 0; i < 4; i++) {
        result[i * 5 + 4] += a[i * 5 + 4];
    }
    return result;
  }
}

class _MaskOverlayPainter extends CustomPainter {
  final List<dynamic> layers;
  final MaskDisplayMode displayMode;

  _MaskOverlayPainter({
    required this.layers,
    required this.displayMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (layers.isEmpty) return;

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.isVisible || layer.activeMask == null) continue;

      final mask = layer.activeMask;
      final normalizedPath = mask.parameters['normalized_path'] as List<dynamic>?;

      if (normalizedPath != null && normalizedPath.isNotEmpty) {
        final path = Path();
        for (int j = 0; j < normalizedPath.length; j++) {
          final point = normalizedPath[j] as Map<String, dynamic>;
          final x = (point['x'] as double) * size.width;
          final y = (point['y'] as double) * size.height;
          if (j == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();

        final paint = Paint();

        // Mode specific painting
        if (displayMode == MaskDisplayMode.maskOnly) {
          paint.color = Colors.white; // White = selected
          paint.style = PaintingStyle.fill;
          canvas.drawPath(path, paint);
        } else if (displayMode == MaskDisplayMode.edge) {
          final borderPaint = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          canvas.drawPath(path, borderPaint);
        } else {
          // Overlay or Normal (Normal is filtered before here)
          paint.color = layer.colorLabel.withOpacity(0.5);
          paint.style = PaintingStyle.fill;
          canvas.drawPath(path, paint);
          
          final borderPaint = Paint()
            ..color = layer.colorLabel
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          canvas.drawPath(path, borderPaint);
        }

        // Draw text label at the first point
        final firstPt = normalizedPath.first as Map<String, dynamic>;
        final labelX = (firstPt['x'] as double) * size.width;
        final labelY = (firstPt['y'] as double) * size.height;

        final textSpan = TextSpan(
          text: layer.name,
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 14, 
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(labelX + 8, labelY + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskOverlayPainter oldDelegate) => true;
}

class _LocalStrokePainter extends CustomPainter {
  final List<Offset> stroke;
  final Color color;

  _LocalStrokePainter({required this.stroke, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (stroke.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 20.0 // Brush size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(stroke.first.dx, stroke.first.dy);
    for (int i = 1; i < stroke.length; i++) {
      path.lineTo(stroke[i].dx, stroke[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LocalStrokePainter oldDelegate) => true;
}
