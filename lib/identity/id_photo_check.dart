import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Quick checks on the phone before an identity photo is uploaded, so fewer
/// checks get rejected. Nothing leaves the device; only yes/no results are
/// passed to the guide. This helps people take a good photo — it is not a
/// certified liveness or fraud test.
class IdPhotoResult {
  const IdPhotoResult({this.blurry = false, this.glare = false, this.dark = false, this.noFace = false, this.manyFaces = false, this.eyesClosed = false, this.faceSmall = false});
  final bool blurry, glare, dark, noFace, manyFaces, eyesClosed, faceSmall;

  bool get ok => !(blurry || glare || dark || noFace || manyFaces || eyesClosed || faceSmall);

  List<String> get tips => [
        if (blurry) 'It looks blurry — hold still and tap to focus.',
        if (glare) 'There’s a bright reflection — tilt it slightly away from the light.',
        if (dark) 'It’s too dark — move to a brighter spot.',
        if (noFace) 'We can’t see a face — make sure it’s in the frame.',
        if (manyFaces) 'More than one face is in the picture.',
        if (eyesClosed) 'Keep your eyes open and look at the camera.',
        if (faceSmall) 'Move a little closer so your face fills the oval.',
      ];

  Map<String, Object?> asGuideFacts(String which) => {
        '${which}_blurry': blurry,
        '${which}_glare': glare,
        '${which}_too_dark': dark,
        if (which == 'selfie') ...{'selfie_no_face': noFace, 'selfie_eyes_closed': eyesClosed},
      };
}

class IdPhotoCheck {
  /// [face]: 'selfie' expects exactly one large face with open eyes,
  /// 'document' expects the small portrait printed on an ID, 'none' skips faces.
  static Future<IdPhotoResult> check(File file, {String face = 'none'}) async {
    final stats = await compute(_imageStats, await file.readAsBytes());
    var noFace = false, many = false, eyes = false, small = false;
    if (face != 'none') {
      final detector = FaceDetector(options: FaceDetectorOptions(enableClassification: face == 'selfie', performanceMode: FaceDetectorMode.fast));
      try {
        final faces = await detector.processImage(InputImage.fromFilePath(file.path));
        noFace = faces.isEmpty;
        if (face == 'selfie' && faces.isNotEmpty) {
          many = faces.length > 1;
          final f = faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
          eyes = (f.leftEyeOpenProbability ?? 1) < 0.3 && (f.rightEyeOpenProbability ?? 1) < 0.3;
          small = stats.width > 0 && f.boundingBox.width < stats.width * 0.22;
        }
      } catch (_) {
        // Detector unavailable: don't block the person.
      } finally {
        detector.close();
      }
    }
    return IdPhotoResult(
      blurry: stats.sharpness < 60,
      glare: stats.glare > 0.06,
      dark: stats.brightness < 55,
      noFace: noFace,
      manyFaces: many,
      eyesClosed: eyes,
      faceSmall: small,
    );
  }

  /// Shows tips when a photo has problems; returns true to keep it anyway.
  static Future<bool> review(BuildContext context, IdPhotoResult r) async {
    if (r.ok || !context.mounted) return true;
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retake this photo?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...r.tips.map((t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $t'))),
          const SizedBox(height: 4),
          const Text('Clear photos are checked faster.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use anyway')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retake')),
        ],
      ),
    );
    return keep ?? true;
  }
}

class _Stats {
  const _Stats(this.width, this.sharpness, this.glare, this.brightness);
  final int width;
  final double sharpness, glare, brightness;
}

/// Sharpness = variance of the Laplacian on a 480px grey copy; glare = share of
/// near-white pixels; brightness = mean luminance.
_Stats _imageStats(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return const _Stats(0, 999, 0, 128);
  final g = img.grayscale(img.copyResize(src, width: min(480, src.width)));
  final w = g.width, h = g.height;
  final lum = List<double>.filled(w * h, 0);
  var sum = 0.0, bright = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = g.getPixel(x, y).r.toDouble();
      lum[y * w + x] = v;
      sum += v;
      if (v > 245) bright++;
    }
  }
  var lsum = 0.0, lsq = 0.0, n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final l = lum[i - w] + lum[i + w] + lum[i - 1] + lum[i + 1] - 4 * lum[i];
      lsum += l;
      lsq += l * l;
      n++;
    }
  }
  final mean = n == 0 ? 0.0 : lsum / n;
  final variance = n == 0 ? 999.0 : lsq / n - mean * mean;
  return _Stats(src.width, variance, bright / (w * h), sum / (w * h));
}
