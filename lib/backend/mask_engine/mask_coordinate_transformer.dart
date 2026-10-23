import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
class MaskCoordinateTransformer {
  /// Converts a local widget coordinate (e.g. from GestureDetector inside InteractiveViewer)
  /// into a normalized [0.0, 1.0] coordinate relative to the actual image pixels.
  /// 
  /// [localPoint] is the coordinate from details.localPosition.
  /// [widgetSize] is the size of the container holding the image.
  /// [imageSize] is the actual intrinsic size of the image.
  /// [fit] is the BoxFit used to render the image (usually BoxFit.contain).
  static Offset screenToNormalizedImage(
    Offset localPoint,
    Size widgetSize,
    Size imageSize,
    BoxFit fit, {
    Matrix4? transformMatrix,
  }) {
    if (widgetSize.isEmpty || imageSize.isEmpty) return Offset.zero;

    Offset pt = localPoint;
    
    // 1. Invert the InteractiveViewer's transform if provided
    if (transformMatrix != null) {
      final Matrix4 inverted = Matrix4.inverted(transformMatrix);
      final Vector3 transformedPt = inverted.transform3(Vector3(pt.dx, pt.dy, 0.0));
      pt = Offset(transformedPt.x, transformedPt.y);
    }

    // 2. Calculate how the image is fitted inside the widget
    final FittedSizes fittedSizes = applyBoxFit(fit, imageSize, widgetSize);
    
    // 3. Calculate the destination rectangle where the image is actually drawn
    final Rect destRect = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & widgetSize);

    // 4. Map to normalized coordinates
    double x = (pt.dx - destRect.left) / destRect.width;
    double y = (pt.dy - destRect.top) / destRect.height;

    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);

    return Offset(x, y);
  }

  /// Converts a normalized [0.0, 1.0] image coordinate back to a local widget coordinate.
  static Offset normalizedImageToScreen(
    Offset normalizedPoint,
    Size widgetSize,
    Size imageSize,
    BoxFit fit, {
    Matrix4? transformMatrix,
  }) {
    if (widgetSize.isEmpty || imageSize.isEmpty) return Offset.zero;

    final FittedSizes fittedSizes = applyBoxFit(fit, imageSize, widgetSize);
    final Rect destRect = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & widgetSize);

    Offset pt = Offset(
      destRect.left + (normalizedPoint.dx * destRect.width),
      destRect.top + (normalizedPoint.dy * destRect.height),
    );

    if (transformMatrix != null) {
      final Vector3 transformedPt = transformMatrix.transform3(Vector3(pt.dx, pt.dy, 0.0));
      pt = Offset(transformedPt.x, transformedPt.y);
    }

    return pt;
  }
}
