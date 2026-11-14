import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:oneova_media_engine/oneova_media_engine.dart';
import 'package:path_provider/path_provider.dart';

import '../../create/studio/services/studio_cutout.dart';

/// Product photo preparation, all on the phone:
/// background removed (ML Kit subject segmentation), the product placed on a
/// clean white studio background, saved as a JPEG no wider than 2048 px.
///
/// Only the subject model is trusted for products. Its fallback (the selfie
/// model, made for people) finds nothing in a photo of a shoe or a bag and
/// would leave an all-white picture, so that result is thrown away, and so is
/// any mask that covers almost nothing or almost everything.
class ProductPhoto {
  ProductPhoto._();

  /// Returns the cleaned photo. When the cut-out can't run on this phone (or
  /// finds no subject) the original is only resized, and [cleaned] is false.
  static Future<({File file, bool cleaned})> prepare(File original, {bool removeBackground = true}) async {
    var source = original.path;
    var cleaned = false;
    if (removeBackground) {
      try {
        final dir = await getTemporaryDirectory();
        final (cut, _, _, method) = await OneovaMediaEngine.cutout(
          original.path,
          out: '${dir.path}/product_cut_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        if (method != 'subject' || !await compute(isUsableCutout, cut)) throw StateError('no clear subject');
        source = await StudioCutout.compose(
          originalPath: original.path,
          cutoutPath: cut,
          background: CutoutBackground.colour,
          colour: const Color(0xFFFFFFFF),
        );
        cleaned = true;
      } catch (_) {
        source = original.path; // keep the seller moving with the photo as taken
      }
    }
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/product_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final ok = await compute(_toJpeg, (source, out));
    if (!ok) return (file: original, cleaned: false);
    return (file: File(out), cleaned: cleaned);
  }
}

bool _toJpeg((String, String) io) {
  try {
    final decoded = img.decodeImage(File(io.$1).readAsBytesSync());
    if (decoded == null) return false;
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > 2048) {
      image = image.width >= image.height ? img.copyResize(image, width: 2048) : img.copyResize(image, height: 2048);
    }
    // Any transparency left becomes white.
    final flat = img.Image(width: image.width, height: image.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    File(io.$2).writeAsBytesSync(img.encodeJpg(flat, quality: 88));
    return true;
  } catch (_) {
    return false;
  }
}

/// True when the cut-out kept a real subject: between 2% and 97% of the
/// pixels are solid (checked on a sample grid, fast on big photos).
@visibleForTesting
bool isUsableCutout(String pngPath) {
  try {
    final image = img.decodePng(File(pngPath).readAsBytesSync());
    if (image == null || !image.hasAlpha) return false;
    return cutoutCoverageOk(image);
  } catch (_) {
    return false;
  }
}

@visibleForTesting
bool cutoutCoverageOk(img.Image image) {
  final step = (image.width > image.height ? image.width : image.height) ~/ 160 + 1;
  var solid = 0, total = 0;
  for (var y = 0; y < image.height; y += step) {
    for (var x = 0; x < image.width; x += step) {
      total++;
      if (image.getPixel(x, y).a > 128) solid++;
    }
  }
  if (total == 0) return false;
  final share = solid / total;
  return share >= 0.02 && share <= 0.97;
}
