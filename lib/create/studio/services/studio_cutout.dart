import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import 'studio_project_store.dart';

/// What goes behind the cut-out person in a photo.
enum CutoutBackground { transparent, blur, colour, image }

/// Photo background removal for Studio: on-device subject segmentation
/// (`OneovaMediaEngine.cutout`) then the chosen background composited in.
class StudioCutout {
  StudioCutout._();

  /// The photo with its background removed (PNG with alpha).
  static Future<String> cutout(String path) async {
    final dir = await StudioProjectStore.dir('cutouts');
    final (out, _, _, _) = await OneovaMediaEngine.cutout(
      path,
      out: '${dir.path}/cutout_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    return out;
  }

  /// Draws [background] behind [cutoutPath]; returns a new image file.
  /// Transparent keeps the PNG as it is.
  static Future<String> compose({
    required String originalPath,
    required String cutoutPath,
    required CutoutBackground background,
    Color colour = const Color(0xFFFFFFFF),
    String? imagePath,
    double blurSigma = 18,
  }) async {
    if (background == CutoutBackground.transparent) return cutoutPath;
    final person = await _load(cutoutPath);
    final w = person.width.toDouble(), h = person.height.toDouble();
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, rect);
    switch (background) {
      case CutoutBackground.blur:
        final original = await _load(originalPath, width: person.width);
        canvas.drawImageRect(
          original,
          Rect.fromLTWH(0, 0, original.width.toDouble(), original.height.toDouble()),
          rect,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma * w / 720, sigmaY: blurSigma * w / 720, tileMode: TileMode.clamp),
        );
      case CutoutBackground.colour:
        canvas.drawRect(rect, Paint()..color = colour);
      case CutoutBackground.image:
        if (imagePath != null) {
          final bg = await _load(imagePath);
          final s = math.max(w / bg.width, h / bg.height);
          final sw = w / s, sh = h / s;
          canvas.drawImageRect(
            bg,
            Rect.fromLTWH((bg.width - sw) / 2, (bg.height - sh) / 2, sw, sh),
            rect,
            Paint()..filterQuality = FilterQuality.high,
          );
        }
      case CutoutBackground.transparent:
        break;
    }
    canvas.drawImage(person, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    final img = await rec.endRecording().toImage(person.width, person.height);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await StudioProjectStore.dir('cutouts');
    final file = File('${dir.path}/bg_${background.name}_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    return file.path;
  }

  static Future<ui.Image> _load(String path, {int? width}) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: width);
    return (await codec.getNextFrame()).image;
  }
}
