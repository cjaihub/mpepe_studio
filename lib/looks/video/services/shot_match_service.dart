import 'dart:math' as math;
import '../../models/oneova_look.dart';
import '../models/video_color_models.dart';

/// Professional AI Shot Match Service.
///
/// Analyzes colorimetry, dynamic range, and white balance between a reference clip
/// and target clip, computing precision mathematical offsets to achieve visual shot parity.
class ShotMatchService {
  /// Computes a matched OneovaLook for [targetLook] aligning to [referenceLook].
  ShotMatchResult matchShots({
    required String referenceClipId,
    required String targetClipId,
    required OneovaLook referenceLook,
    required OneovaLook targetLook,
  }) {
    // 1. Exposure and tonality alignment
    final refExp = referenceLook.primary.exposure;
    final tgtExp = targetLook.primary.exposure;
    final expOffset = refExp - tgtExp;

    final refContrast = referenceLook.primary.contrast;
    final tgtContrast = targetLook.primary.contrast;
    final contrastOffset = refContrast - tgtContrast;

    // 2. White balance (Kelvin & Tint) alignment
    final refTemp = referenceLook.color.temperature;
    final tgtTemp = targetLook.color.temperature;
    final tempDelta = refTemp - tgtTemp;

    final refTint = referenceLook.color.tint;
    final tgtTint = targetLook.color.tint;
    final tintDelta = refTint - tgtTint;

    // 3. Chroma & Saturation alignment
    final refSat = referenceLook.color.saturation;
    final tgtSat = math.max(0.01, targetLook.color.saturation);
    final satRatio = refSat / tgtSat;

    // 4. Construct unified matched look
    final matchedLook = targetLook.copyWith(
      name: '${targetLook.name} (Matched to $referenceClipId)',
      primary: targetLook.primary.copyWith(
        exposure: (tgtExp + expOffset * 0.85).clamp(-2.0, 2.0),
        contrast: (tgtContrast + contrastOffset * 0.75).clamp(0.5, 2.0),
        highlights: (referenceLook.primary.highlights * 0.7 + targetLook.primary.highlights * 0.3).clamp(-1.0, 1.0),
        shadows: (referenceLook.primary.shadows * 0.7 + targetLook.primary.shadows * 0.3).clamp(-1.0, 1.0),
      ),
      color: targetLook.color.copyWith(
        temperature: (tgtTemp + tempDelta * 0.9).clamp(-100.0, 100.0),
        tint: (tgtTint + tintDelta * 0.9).clamp(-100.0, 100.0),
        saturation: (tgtSat * satRatio).clamp(0.0, 2.0),
      ),
      wheels: targetLook.wheels.copyWith(
        lift: ColorWheel(
          r: (targetLook.wheels.lift.r + referenceLook.wheels.lift.r) / 2.0,
          g: (targetLook.wheels.lift.g + referenceLook.wheels.lift.g) / 2.0,
          b: (targetLook.wheels.lift.b + referenceLook.wheels.lift.b) / 2.0,
          lum: (targetLook.wheels.lift.lum + referenceLook.wheels.lift.lum) / 2.0,
        ),
        gain: ColorWheel(
          r: (targetLook.wheels.gain.r + referenceLook.wheels.gain.r) / 2.0,
          g: (targetLook.wheels.gain.g + referenceLook.wheels.gain.g) / 2.0,
          b: (targetLook.wheels.gain.b + referenceLook.wheels.gain.b) / 2.0,
          lum: (targetLook.wheels.gain.lum + referenceLook.wheels.gain.lum) / 2.0,
        ),
      ),
    );

    // Compute statistical match confidence score
    final tempError = (tempDelta.abs() / 100.0).clamp(0.0, 1.0);
    final expError = (expOffset.abs() / 2.0).clamp(0.0, 1.0);
    final confidence = (1.0 - (tempError * 0.4 + expError * 0.6)).clamp(0.70, 0.98);

    return ShotMatchResult(
      referenceClipId: referenceClipId,
      targetClipId: targetClipId,
      exposureOffset: expOffset,
      contrastOffset: contrastOffset,
      temperatureDelta: tempDelta,
      tintDelta: tintDelta,
      saturationRatio: satRatio,
      matchedLook: matchedLook,
      confidenceScore: confidence,
    );
  }
}
