import '../../models/oneova_look.dart';
import '../models/video_color_models.dart';

/// Interpolates OneovaLook parameters across timeline keyframes with precision easing.
class VideoKeyframeInterpolator {
  /// Evaluates the dynamic look for [clipGrade] at timeline offset [currentTimeSeconds].
  OneovaLook interpolateAtTime({
    required ClipColorGrade clipGrade,
    required double currentTimeSeconds,
  }) {
    if (clipGrade.isBypassed) {
      return const OneovaLook(id: 'bypassed', name: 'Bypassed');
    }

    final keyframes = clipGrade.keyframes;
    if (keyframes.isEmpty) {
      return clipGrade.baseLook;
    }

    // Single keyframe
    if (keyframes.length == 1) {
      return keyframes.first.look;
    }

    // Sort by timestamp
    final sorted = List<LookKeyframe>.from(keyframes)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    // Clamp before first
    if (currentTimeSeconds <= sorted.first.timeSeconds) {
      return sorted.first.look;
    }

    // Clamp after last
    if (currentTimeSeconds >= sorted.last.timeSeconds) {
      return sorted.last.look;
    }

    // Find bounding keyframe interval [k0, k1]
    LookKeyframe k0 = sorted.first;
    LookKeyframe k1 = sorted.last;

    for (int i = 0; i < sorted.length - 1; i++) {
      if (currentTimeSeconds >= sorted[i].timeSeconds &&
          currentTimeSeconds <= sorted[i + 1].timeSeconds) {
        k0 = sorted[i];
        k1 = sorted[i + 1];
        break;
      }
    }

    final span = k1.timeSeconds - k0.timeSeconds;
    if (span <= 0.0001) return k0.look;

    final rawT = ((currentTimeSeconds - k0.timeSeconds) / span).clamp(0.0, 1.0);
    final easedT = _applyEasing(rawT, k0.easing);

    return _blendLooks(k0.look, k1.look, easedT);
  }

  double _applyEasing(double t, KeyframeEasing easing) {
    return switch (easing) {
      KeyframeEasing.linear => t,
      KeyframeEasing.easeIn => t * t,
      KeyframeEasing.easeOut => t * (2.0 - t),
      KeyframeEasing.easeInOut =>
        t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t,
    };
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  OneovaLook _blendLooks(OneovaLook a, OneovaLook b, double t) {
    return a.copyWith(
      primary: LookPrimary(
        exposure: _lerp(a.primary.exposure, b.primary.exposure, t),
        contrast: _lerp(a.primary.contrast, b.primary.contrast, t),
        pivot: _lerp(a.primary.pivot, b.primary.pivot, t),
        highlights: _lerp(a.primary.highlights, b.primary.highlights, t),
        shadows: _lerp(a.primary.shadows, b.primary.shadows, t),
        whites: _lerp(a.primary.whites, b.primary.whites, t),
        blacks: _lerp(a.primary.blacks, b.primary.blacks, t),
        brightness: _lerp(a.primary.brightness, b.primary.brightness, t),
      ),
      color: LookColor(
        temperature: _lerp(a.color.temperature, b.color.temperature, t),
        tint: _lerp(a.color.tint, b.color.tint, t),
        vibrance: _lerp(a.color.vibrance, b.color.vibrance, t),
        saturation: _lerp(a.color.saturation, b.color.saturation, t),
        colorBoost: _lerp(a.color.colorBoost, b.color.colorBoost, t),
      ),
      wheels: LookWheels(
        lift: ColorWheel(
          r: _lerp(a.wheels.lift.r, b.wheels.lift.r, t),
          g: _lerp(a.wheels.lift.g, b.wheels.lift.g, t),
          b: _lerp(a.wheels.lift.b, b.wheels.lift.b, t),
          lum: _lerp(a.wheels.lift.lum, b.wheels.lift.lum, t),
        ),
        gamma: ColorWheel(
          r: _lerp(a.wheels.gamma.r, b.wheels.gamma.r, t),
          g: _lerp(a.wheels.gamma.g, b.wheels.gamma.g, t),
          b: _lerp(a.wheels.gamma.b, b.wheels.gamma.b, t),
          lum: _lerp(a.wheels.gamma.lum, b.wheels.gamma.lum, t),
        ),
        gain: ColorWheel(
          r: _lerp(a.wheels.gain.r, b.wheels.gain.r, t),
          g: _lerp(a.wheels.gain.g, b.wheels.gain.g, t),
          b: _lerp(a.wheels.gain.b, b.wheels.gain.b, t),
          lum: _lerp(a.wheels.gain.lum, b.wheels.gain.lum, t),
        ),
      ),
      film: LookFilm(
        emulationProfile: b.film.emulationProfile.isNotEmpty ? b.film.emulationProfile : a.film.emulationProfile,
        halation: _lerp(a.film.halation, b.film.halation, t),
        bloom: _lerp(a.film.bloom, b.film.bloom, t),
        grain: _lerp(a.film.grain, b.film.grain, t),
        fade: _lerp(a.film.fade, b.film.fade, t),
      ),
      optics: LookOptics(
        vignette: _lerp(a.optics.vignette, b.optics.vignette, t),
        chromaticAberration: _lerp(a.optics.chromaticAberration, b.optics.chromaticAberration, t),
        lensDistortion: _lerp(a.optics.lensDistortion, b.optics.lensDistortion, t),
      ),
      detail: LookDetail(
        sharpen: _lerp(a.detail.sharpen, b.detail.sharpen, t),
        clarity: _lerp(a.detail.clarity, b.detail.clarity, t),
        texture: _lerp(a.detail.texture, b.detail.texture, t),
      ),
    );
  }
}
