import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/photo_studio/photo_studio_models.dart';
import 'package:oneova/backend/mask_engine/api/mask_engine_provider.dart';
import 'package:oneova/backend/mask_engine/mask_layer_manager.dart';
import 'package:oneova/backend/mask_engine/mask_coordinate_transformer.dart';
import 'package:oneova/create/studio/services/studio_looks.dart';
import 'package:oneova/looks/models/oneova_look.dart';
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

    OneovaLook? activeLook;
    double vignetteAmount = 0.0;
    double distortionAmount = 0.0;
    double perspectiveAmount = 0.0;

    if (widget.project.currentGraph.layers.isNotEmpty) {
      final globalLayer = widget.project.currentGraph.layers.first;

      double exposure = _getParam(globalLayer, AdjustmentType.EXPOSURE, 0.0);
      double contrast = _getParam(globalLayer, AdjustmentType.CONTRAST, 0.0);
      double highlights = _getParam(globalLayer, AdjustmentType.HIGHLIGHTS, 0.0);
      double shadows = _getParam(globalLayer, AdjustmentType.SHADOWS, 0.0);
      double whites = _getParam(globalLayer, AdjustmentType.WHITES, 0.0);
      double blacks = _getParam(globalLayer, AdjustmentType.BLACKS, 0.0);
      double saturation = _getParam(globalLayer, AdjustmentType.SATURATION, 0.0);
      double vibrance = _getParam(globalLayer, AdjustmentType.VIBRANCE, 0.0);
      double temperature = _getParam(globalLayer, AdjustmentType.TEMPERATURE, 0.0);
      double tint = _getParam(globalLayer, AdjustmentType.TINT, 0.0);
      double clarity = _getParam(globalLayer, AdjustmentType.CLARITY, 0.0);
      double texture = _getParam(globalLayer, AdjustmentType.TEXTURE, 0.0);
      double dehaze = _getParam(globalLayer, AdjustmentType.DEHAZE, 0.0);
      double sharpness = _getParam(globalLayer, AdjustmentType.SHARPNESS, 0.0);
      vignetteAmount = _getParam(globalLayer, AdjustmentType.VIGNETTE, 0.0);
      distortionAmount = _getParam(globalLayer, AdjustmentType.DISTORTION, 0.0);
      perspectiveAmount = _getParam(globalLayer, AdjustmentType.PERSPECTIVE, 0.0);

      ColorWheel wheelFor(AdjustmentType t) {
        final adj = globalLayer.adjustments.where((a) => a.type == t).lastOrNull;
        if (adj == null) return const ColorWheel();
        final h = ((adj.parameters['hue'] as num?)?.toDouble() ?? 0.0) * math.pi / 180.0;
        final s = ((adj.parameters['saturation'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
        final l = ((adj.parameters['luminance'] as num?)?.toDouble() ?? 0.0).clamp(-1.0, 1.0);
        final c = HSVColor.fromAHSV(1.0, (h * 180 / math.pi) % 360, s, 1.0).toColor();
        return ColorWheel(
          r: (c.r - 0.5) * 0.45 * s,
          g: (c.g - 0.5) * 0.45 * s,
          b: (c.b - 0.5) * 0.45 * s,
          lum: l * 0.25,
        );
      }

      HslBand hslFor(String ch) {
        for (final adj in globalLayer.adjustments.reversed) {
          if (adj.type == AdjustmentType.HSL && adj.parameters['channel'] == ch) {
            final h = ((adj.parameters['hue'] as num?)?.toDouble() ?? 0.0) * 0.3;
            final s = ((adj.parameters['saturation'] as num?)?.toDouble() ?? 0.0) / 100.0;
            final l = ((adj.parameters['luminance'] as num?)?.toDouble() ?? 0.0) / 100.0;
            return HslBand(hue: h, sat: s, lum: l);
          }
        }
        return const HslBand();
      }

      List<CurvePoint> masterCurve = const [CurvePoint(0, 0), CurvePoint(1, 1)];
      final curveAdj = globalLayer.adjustments.where((a) => a.type == AdjustmentType.CURVES_RGB).lastOrNull;
      if (curveAdj != null && curveAdj.parameters['points'] is List) {
        final rawPts = curveAdj.parameters['points'] as List;
        if (rawPts.length >= 2) {
          masterCurve = [
            for (final p in rawPts)
              if (p is List && p.length >= 2)
                CurvePoint((p[0] as num).toDouble().clamp(0.0, 1.0), (p[1] as num).toDouble().clamp(0.0, 1.0)),
          ];
        }
      }

      final liftW = wheelFor(AdjustmentType.COLOR_WHEELS_SHADOWS);
      final gammaW = wheelFor(AdjustmentType.COLOR_WHEELS_MIDTONES);
      final gainW = wheelFor(AdjustmentType.COLOR_WHEELS_HIGHLIGHTS);

      activeLook = OneovaLook(
        id: 'photo_studio_${globalLayer.adjustments.length}_${exposure}_${contrast}_${highlights}_${shadows}_${saturation}_${vibrance}_${temperature}_${tint}_${liftW.r}_${gammaW.r}_${gainW.r}_${masterCurve.length}',
        primary: LookPrimary(
          exposure: exposure,
          contrast: (1.0 + contrast * 0.65 + clarity * 0.25 + dehaze * 0.3).clamp(0.3, 2.2),
          highlights: highlights.clamp(-1.0, 1.0),
          shadows: (shadows - dehaze * 0.15).clamp(-1.0, 1.0),
          whites: whites.clamp(-1.0, 1.0),
          blacks: (blacks - dehaze * 0.2).clamp(-1.0, 1.0),
        ),
        color: LookColor(
          temperature: temperature * 45.0,
          tint: tint * 45.0,
          vibrance: (vibrance + dehaze * 0.12).clamp(-1.0, 1.0),
          saturation: (1.0 + saturation).clamp(0.0, 2.0),
        ),
        wheels: LookWheels(lift: liftW, gamma: gammaW, gain: gainW),
        curves: LookCurves(master: masterCurve),
        hsl: LookHsl(
          red: hslFor('red'),
          orange: hslFor('orange'),
          yellow: hslFor('yellow'),
          green: hslFor('green'),
          aqua: hslFor('cyan'),
          blue: hslFor('blue'),
          purple: hslFor('purple'),
          magenta: hslFor('magenta'),
        ),
        detail: LookDetail(sharpen: (sharpness.abs() * 0.5 + texture.clamp(0.0, 1.0) * 0.35).clamp(0.0, 1.0)),
        optics: LookOptics(vignette: vignetteAmount.abs().clamp(0.0, 1.0)),
      );

      // Matrix pipeline (combining exposure, contrast, tone recovery, saturation, vibrance, color wheels)
      double expFactor = math.pow(2.0, exposure + (shadows * 0.18) + (highlights * 0.14)).toDouble();
      List<double> expMatrix = [
        expFactor, 0, 0, 0, (shadows * 18 + blacks * 22 + liftW.lum * 25),
        0, expFactor, 0, 0, (shadows * 18 + blacks * 22 + liftW.lum * 25),
        0, 0, expFactor, 0, (shadows * 18 + blacks * 22 + liftW.lum * 25),
        0, 0, 0, 1, 0,
      ];
      composedMatrix = _multiplyMatrices(composedMatrix, expMatrix);

      double contFactor = math.pow(2.0, (contrast * 0.65) + (clarity * 0.28) + (dehaze * 0.32) + (whites * 0.12) - (blacks * 0.12)).toDouble();
      double contOffset = 128 * (1 - contFactor) - (dehaze * 14);
      List<double> contMatrix = [
        contFactor, 0, 0, 0, contOffset,
        0, contFactor, 0, 0, contOffset,
        0, 0, contFactor, 0, contOffset,
        0, 0, 0, 1, 0,
      ];
      composedMatrix = _multiplyMatrices(composedMatrix, contMatrix);

      double satFactor = (1.0 + saturation + vibrance * 0.65 + dehaze * 0.12).clamp(0.0, 2.5);
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

      double rScale = 1.0 + (temperature * 0.22) + (tint * 0.1) + (gainW.r + gammaW.r) * 0.8;
      double gScale = 1.0 - (tint * 0.22) + (gainW.g + gammaW.g) * 0.8;
      double bScale = 1.0 - (temperature * 0.22) + (tint * 0.1) + (gainW.b + gammaW.b) * 0.8;
      List<double> wbMatrix = [
        rScale, 0, 0, 0, liftW.r * 90,
        0, gScale, 0, 0, liftW.g * 90,
        0, 0, bScale, 0, liftW.b * 90,
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

    if (activeLook != null) {
      baseImage = StudioLookFilter(look: activeLook, child: baseImage);
    }
    if (vignetteAmount.abs() > 0.01) {
      baseImage = Stack(
        alignment: Alignment.center,
        children: [
          baseImage,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.85,
                    colors: [
                      Colors.transparent,
                      (vignetteAmount > 0 ? Colors.black : Colors.white)
                          .withValues(alpha: (vignetteAmount.abs() * 0.65).clamp(0.0, 0.85)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final crop = widget.project.currentGraph.crop;
    if (crop.rotationDegrees.abs() > 0.01 ||
        distortionAmount.abs() > 0.01 ||
        perspectiveAmount.abs() > 0.01) {
      final mat = Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(perspectiveAmount * 0.25)
        ..rotateZ(crop.rotationDegrees * math.pi / 180.0);
      final scale = (1.0 + distortionAmount * 0.25).clamp(0.75, 1.4);
      mat.scaleByDouble(scale, scale, 1.0, 1.0);
      baseImage = Transform(
        alignment: Alignment.center,
        transform: mat,
        child: baseImage,
      );
    }
    final double? targetAspect = switch (crop.ratio) {
      CropAspectRatio.square1x1 => 1.0,
      CropAspectRatio.ratio4x5 => 4.0 / 5.0,
      CropAspectRatio.ratio9x16 => 9.0 / 16.0,
      CropAspectRatio.ratio16x9 => 16.0 / 9.0,
      _ => null,
    };
    if (targetAspect != null) {
      baseImage = Center(
        child: AspectRatio(
          aspectRatio: targetAspect,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 800,
                height: 800 / targetAspect,
                child: baseImage,
              ),
            ),
          ),
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
