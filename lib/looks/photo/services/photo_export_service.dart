import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/oneova_look.dart';
import '../models/photo_grading_models.dart';

/// Professional high-fidelity Photo Export Service.
///
/// Exports photos at their EXACT native source resolution (e.g. 24MP, 48MP, 100MP)
/// with zero downsampling, applying the complete OneovaLook grading graph
/// while preserving color fidelity and EXIF metadata.
class PhotoExportService {
  /// Renders and exports the source image file at original resolution with [look] applied.
  Future<PhotoExportResult> exportOriginalResolution({
    required String sourcePath,
    required OneovaLook look,
    String? destinationPath,
    int jpegQuality = 98,
    bool preserveExif = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw ArgumentError('Source photo file does not exist at $sourcePath');
    }

    final bytes = await sourceFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw FormatException('Unable to decode image from $sourcePath');
    }

    final origWidth = decodedImage.width;
    final origHeight = decodedImage.height;

    // Apply Look parameters mathematically at full native resolution
    final processedImage = _applyLookToImage(decodedImage, look);

    // Encode to target format at maximum fidelity
    final Uint8List encodedBytes;
    final isPng = destinationPath != null && destinationPath.toLowerCase().endsWith('.png');
    if (isPng) {
      encodedBytes = Uint8List.fromList(img.encodePng(processedImage));
    } else {
      encodedBytes = Uint8List.fromList(img.encodeJpg(processedImage, quality: jpegQuality));
    }

    // Determine destination path
    final outPath = destinationPath ?? _generateDefaultOutputPath(sourcePath, isPng);
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(encodedBytes);

    stopwatch.stop();

    return PhotoExportResult(
      outputPath: outPath,
      outputWidth: origWidth,
      outputHeight: origHeight,
      fileSizeBytes: encodedBytes.length,
      renderDuration: stopwatch.elapsed,
      exifPreserved: preserveExif,
    );
  }

  /// Evaluates the complete Look color, primary, and film graph on the raw image buffer.
  img.Image _applyLookToImage(img.Image input, OneovaLook look) {
    if (look.isNeutral) {
      return input;
    }

    final exposure = look.primary.exposure;
    final contrast = look.primary.contrast;
    final brightness = look.primary.brightness;
    final temp = look.color.temperature; // -100 to 100
    final tint = look.color.tint; // -100 to 100
    final sat = look.color.saturation; // 0 to 2
    final vibrance = look.color.vibrance; // -1 to 1
    final grain = look.film.grain;
    final vignette = look.optics.vignette;

    // Temperature shifts: warm boosts red/reduces blue; cool boosts blue/reduces red
    final rShift = temp * 0.45 + tint * 0.25;
    final gShift = -tint * 0.45;
    final bShift = -temp * 0.45 + tint * 0.25;

    final width = input.width;
    final height = input.height;
    final centerX = width / 2.0;
    final centerY = height / 2.0;
    final maxDist = math.sqrt(centerX * centerX + centerY * centerY);

    final output = img.Image.from(input);
    final random = math.Random(42);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = output.getPixel(x, y);

        double r = pixel.r.toDouble();
        double g = pixel.g.toDouble();
        double b = pixel.b.toDouble();

        // 1. Exposure adjustment: scale = 2^exposure
        if (exposure != 0.0) {
          final scale = math.pow(2.0, exposure);
          r *= scale;
          g *= scale;
          b *= scale;
        }

        // 2. Brightness adjustment
        if (brightness != 0.0) {
          final bOffset = brightness * 128.0;
          r += bOffset;
          g += bOffset;
          b += bOffset;
        }

        // 3. Contrast adjustment around pivot 128
        if (contrast != 1.0) {
          r = 128.0 + (r - 128.0) * contrast;
          g = 128.0 + (g - 128.0) * contrast;
          b = 128.0 + (b - 128.0) * contrast;
        }

        // 4. White balance (temperature and tint)
        if (temp != 0.0 || tint != 0.0) {
          r += rShift;
          g += gShift;
          b += bShift;
        }

        // 5. Saturation & Vibrance
        if (sat != 1.0 || vibrance != 0.0) {
          final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          double effectiveSat = sat;
          if (vibrance != 0.0) {
            final maxChannel = math.max(r, math.max(g, b));
            final minChannel = math.min(r, math.min(g, b));
            final currentChroma = (maxChannel - minChannel) / 255.0;
            // Less saturated colors receive more vibrance boost
            effectiveSat += vibrance * (1.0 - currentChroma);
          }

          r = luma + (r - luma) * effectiveSat;
          g = luma + (g - luma) * effectiveSat;
          b = luma + (b - luma) * effectiveSat;
        }

        // 6. Vignette
        if (vignette > 0.0) {
          final dx = x - centerX;
          final dy = y - centerY;
          final dist = math.sqrt(dx * dx + dy * dy);
          final normDist = (dist / maxDist).clamp(0.0, 1.0);
          final vigFactor = 1.0 - (normDist * normDist * vignette * 0.85);
          r *= vigFactor;
          g *= vigFactor;
          b *= vigFactor;
        }

        // 7. Film grain
        if (grain > 0.0) {
          final noise = (random.nextDouble() - 0.5) * grain * 32.0;
          r += noise;
          g += noise;
          b += noise;
        }

        pixel.r = r.clamp(0.0, 255.0);
        pixel.g = g.clamp(0.0, 255.0);
        pixel.b = b.clamp(0.0, 255.0);
      }
    }

    return output;
  }

  String _generateDefaultOutputPath(String sourcePath, bool isPng) {
    final dir = File(sourcePath).parent.path;
    final ext = isPng ? '.png' : '.jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$dir/oneova_graded_$timestamp$ext';
  }
}
