import 'dart:typed_data';
import 'dart:ui' as ui;

class RenderFrame {
  final ui.Image? image;
  final Uint8List? rawPixels;
  final int width;
  final int height;
  final Duration timestamp;

  const RenderFrame({
    this.image,
    this.rawPixels,
    required this.width,
    required this.height,
    required this.timestamp,
  });
  
  void dispose() {
    image?.dispose();
  }
}
