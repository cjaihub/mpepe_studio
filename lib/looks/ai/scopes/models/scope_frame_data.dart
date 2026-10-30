import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../../models/oneova_look.dart';

/// Telemetry metrics extracted from video frames or simulated from active Look graphs
/// for rendering GPU scopes (Waveform, RGB Parade, Vectorscope, Histogram).
@immutable
class ScopeFrameData {
  final List<double> lumaHistogram; // 256 bins normalized [0.0, 1.0]
  final List<double> redHistogram; // 256 bins normalized [0.0, 1.0]
  final List<double> greenHistogram; // 256 bins normalized [0.0, 1.0]
  final List<double> blueHistogram; // 256 bins normalized [0.0, 1.0]
  final List<List<double>> waveformColumns; // e.g. 64 horizontal columns x 32 vertical IRE levels
  final List<double> vectorscopeHueBins; // 36 bins (every 10 degrees)
  final double shadowClippingPercent; // % pixels below 0 IRE
  final double highlightClippingPercent; // % pixels above 100 IRE
  final double skinToneAngleDegrees; // Detected average skin chroma angle (skin line is ~57°)
  final double meanLuma; // 0.0 to 1.0
  final double dynamicRangeStops; // Estimated stops

  const ScopeFrameData({
    required this.lumaHistogram,
    required this.redHistogram,
    required this.greenHistogram,
    required this.blueHistogram,
    required this.waveformColumns,
    required this.vectorscopeHueBins,
    this.shadowClippingPercent = 0.0,
    this.highlightClippingPercent = 0.0,
    this.skinToneAngleDegrees = 57.0,
    this.meanLuma = 0.48,
    this.dynamicRangeStops = 11.5,
  });

  /// Calibrated skin-tone line angle in degrees on vectorscopes (I-axis).
  static const double skinToneTargetAngle = 57.0;

  /// Synthesizes realistic scope telemetry based on a `OneovaLook` parameters
  /// for live preview when camera frame analysis is running or in simulator environments.
  factory ScopeFrameData.fromLook(OneovaLook look) {
    final exposure = look.primary.exposure;
    final contrast = look.primary.contrast;
    final shadows = look.primary.shadows;
    final highlights = look.primary.highlights;
    final temp = look.color.temperature;
    final tint = look.color.tint;
    final sat = look.color.saturation;

    final baseLuma = (0.48 + exposure * 0.12).clamp(0.05, 0.95);

    // Compute histogram peaks
    final lumaHist = List<double>.generate(256, (i) {
      final x = i / 255.0;
      final dist = (x - baseLuma).abs();
      final width = 0.22 / contrast.clamp(0.5, 2.0);
      return math.exp(-math.pow(dist / width, 2)).clamp(0.0, 1.0);
    });

    final redHist = List<double>.generate(256, (i) {
      final x = i / 255.0;
      final shift = (temp * 0.015) + (shadows * 0.05);
      final dist = (x - (baseLuma + shift)).abs();
      return math.exp(-math.pow(dist / 0.24, 2)).clamp(0.0, 1.0);
    });

    final greenHist = List<double>.generate(256, (i) {
      final x = i / 255.0;
      final shift = -(tint * 0.015);
      final dist = (x - (baseLuma + shift)).abs();
      return math.exp(-math.pow(dist / 0.23, 2)).clamp(0.0, 1.0);
    });

    final blueHist = List<double>.generate(256, (i) {
      final x = i / 255.0;
      final shift = -(temp * 0.015) + (highlights * 0.05);
      final dist = (x - (baseLuma + shift)).abs();
      return math.exp(-math.pow(dist / 0.25, 2)).clamp(0.0, 1.0);
    });

    // 64 columns across frame, each with 32 IRE intensity points
    final waveform = List<List<double>>.generate(64, (col) {
      final colCenter = baseLuma + 0.15 * math.sin(col * 0.1);
      return List<double>.generate(32, (row) {
        final rowVal = row / 31.0;
        final d = (rowVal - colCenter).abs();
        return math.exp(-math.pow(d / 0.15, 2)).clamp(0.0, 1.0);
      });
    });

    // 36 vectorscope hue bins (0..350 degrees)
    final skinAngle = (skinToneTargetAngle + (temp * 0.6) + (tint * 0.4)).clamp(0.0, 360.0);
    final vectorscope = List<double>.generate(36, (bin) {
      final deg = bin * 10.0;
      final diff = (deg - skinAngle).abs();
      final minDiff = math.min(diff, 360.0 - diff);
      return (sat * math.exp(-math.pow(minDiff / 35.0, 2))).clamp(0.0, 1.0);
    });

    // Clipping estimations
    final shadowClip = exposure < -1.5 || shadows < -0.4 ? ((-exposure - 1.5) * 8.0).clamp(0.0, 35.0) : 0.0;
    final highlightClip = exposure > 1.5 || highlights > 0.4 ? ((exposure - 1.5) * 8.0).clamp(0.0, 35.0) : 0.0;

    return ScopeFrameData(
      lumaHistogram: lumaHist,
      redHistogram: redHist,
      greenHistogram: greenHist,
      blueHistogram: blueHist,
      waveformColumns: waveform,
      vectorscopeHueBins: vectorscope,
      shadowClippingPercent: shadowClip,
      highlightClippingPercent: highlightClip,
      skinToneAngleDegrees: skinAngle,
      meanLuma: baseLuma,
      dynamicRangeStops: 12.0 - (contrast - 1.0).abs() * 2.0,
    );
  }
}
