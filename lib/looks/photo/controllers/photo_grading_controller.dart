import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/oneova_look.dart';
import '../../ai/models/ai_grade_command.dart';
import '../models/photo_grading_models.dart';
import '../services/photo_export_service.dart';
import '../services/photo_batch_grading_service.dart';

class PhotoGradingController extends Notifier<PhotoGradingState> {
  late final PhotoExportService _exportService;
  late final PhotoBatchGradingService _batchService;

  @override
  PhotoGradingState build() {
    _exportService = PhotoExportService();
    _batchService = PhotoBatchGradingService(exportService: _exportService);

    const neutralLook = OneovaLook(
      id: 'photo_neutral',
      name: 'Original Neutral',
      categories: ['neutral'],
    );

    return const PhotoGradingState(
      currentLook: neutralLook,
      baselineLook: neutralLook,
      mode: PhotoGradingMode.simple,
      activeProTab: PhotoProNodeTab.primary,
      activeScopeType: ScopeType.waveform,
    );
  }

  /// Sets the active photo being edited in the studio.
  void setPhoto({
    required String path,
    int width = 1920,
    int height = 1080,
    int orientationDegrees = 0,
    int bitDepth = 8,
    String colorSpace = 'sRGB',
    int fileSizeBytes = 0,
  }) {
    state = state.copyWith(
      activePhoto: PhotoAssetMeta(
        path: path,
        width: width,
        height: height,
        orientationDegrees: orientationDegrees,
        bitDepth: bitDepth,
        colorSpace: colorSpace,
        fileSizeBytes: fileSizeBytes,
      ),
      statusMessage: 'Photo loaded: ${path.split('/').last}',
    );
  }

  /// Switches between Simple and Pro grading mode.
  void setMode(PhotoGradingMode mode) {
    state = state.copyWith(mode: mode);
  }

  /// Changes the active node tab in Pro mode.
  void setActiveProTab(PhotoProNodeTab tab) {
    state = state.copyWith(activeProTab: tab);
  }

  /// Sets A/B Hold-to-compare state.
  void setComparing(bool isComparing) {
    state = state.copyWith(isComparing: isComparing);
  }

  /// Toggles GPU Scope overlay visibility and scope type.
  void toggleScopes({bool? visible, ScopeType? type}) {
    state = state.copyWith(
      isScopesVisible: visible ?? !state.isScopesVisible,
      activeScopeType: type ?? state.activeScopeType,
    );
  }

  /// Updates the complete active OneovaLook.
  void setLook(OneovaLook look) {
    state = state.copyWith(currentLook: look);
  }

  /// Scales the overall master intensity of the active look.
  void setLookIntensity(double intensity) {
    final clamped = intensity.clamp(0.0, 1.0);
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(intensity: clamped),
    );
  }

  /// Updates primary exposure, contrast, and tonality parameters.
  void updatePrimary({
    double? exposure,
    double? contrast,
    double? pivot,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? brightness,
  }) {
    final cur = state.currentLook.primary;
    final updated = cur.copyWith(
      exposure: exposure,
      contrast: contrast,
      pivot: pivot,
      highlights: highlights,
      shadows: shadows,
      whites: whites,
      blacks: blacks,
      brightness: brightness,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(primary: updated),
    );
  }

  /// Updates color temperature, tint, vibrance, saturation, and color boost.
  void updateColor({
    double? temperature,
    double? tint,
    double? vibrance,
    double? saturation,
    double? colorBoost,
  }) {
    final cur = state.currentLook.color;
    final updated = cur.copyWith(
      temperature: temperature,
      tint: tint,
      vibrance: vibrance,
      saturation: saturation,
      colorBoost: colorBoost,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(color: updated),
    );
  }

  /// Updates 3-way color wheels (Lift, Gamma, Gain, Offset).
  void updateWheels({
    ColorWheel? lift,
    ColorWheel? gamma,
    ColorWheel? gain,
    ColorWheel? offset,
  }) {
    final cur = state.currentLook.wheels;
    final updated = cur.copyWith(
      lift: lift,
      gamma: gamma,
      gain: gain,
      offset: offset,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(wheels: updated),
    );
  }

  /// Updates an individual HSL color mixer band.
  void updateHslBand(String bandName, {double? hue, double? sat, double? lum}) {
    final hsl = state.currentLook.hsl;
    HslBand update(HslBand original) => original.copyWith(hue: hue, sat: sat, lum: lum);

    final updated = switch (bandName.toLowerCase()) {
      'red' => LookHsl(red: update(hsl.red), orange: hsl.orange, yellow: hsl.yellow, green: hsl.green, aqua: hsl.aqua, blue: hsl.blue, purple: hsl.purple, magenta: hsl.magenta),
      'orange' => LookHsl(red: hsl.red, orange: update(hsl.orange), yellow: hsl.yellow, green: hsl.green, aqua: hsl.aqua, blue: hsl.blue, purple: hsl.purple, magenta: hsl.magenta),
      'yellow' => LookHsl(red: hsl.red, orange: hsl.orange, yellow: update(hsl.yellow), green: hsl.green, aqua: hsl.aqua, blue: hsl.blue, purple: hsl.purple, magenta: hsl.magenta),
      'green' => LookHsl(red: hsl.red, orange: hsl.orange, yellow: hsl.yellow, green: update(hsl.green), aqua: hsl.aqua, blue: hsl.blue, purple: hsl.purple, magenta: hsl.magenta),
      'aqua' => LookHsl(red: hsl.red, orange: hsl.orange, yellow: hsl.yellow, green: hsl.green, aqua: update(hsl.aqua), blue: hsl.blue, purple: hsl.purple, magenta: hsl.magenta),
      'blue' => LookHsl(red: hsl.red, orange: hsl.orange, yellow: hsl.yellow, green: hsl.green, aqua: hsl.aqua, blue: update(hsl.blue), purple: hsl.purple, magenta: hsl.magenta),
      'purple' => LookHsl(red: hsl.red, orange: hsl.orange, yellow: hsl.yellow, green: hsl.green, aqua: hsl.aqua, blue: hsl.blue, purple: update(hsl.purple), magenta: hsl.magenta),
      'magenta' => LookHsl(red: hsl.red, orange: hsl.orange, yellow: hsl.yellow, green: hsl.green, aqua: hsl.aqua, blue: hsl.blue, purple: hsl.purple, magenta: update(hsl.magenta)),
      _ => hsl,
    };

    state = state.copyWith(
      currentLook: state.currentLook.copyWith(hsl: updated),
    );
  }

  /// Updates film stock emulation, halation, grain, and bloom.
  void updateFilm({
    String? emulationProfile,
    double? halation,
    double? bloom,
    double? grain,
    double? grainRoughness,
    double? fade,
  }) {
    final cur = state.currentLook.film;
    final updated = cur.copyWith(
      emulationProfile: emulationProfile,
      halation: halation,
      bloom: bloom,
      grain: grain,
      grainRoughness: grainRoughness,
      fade: fade,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(film: updated),
    );
  }

  /// Updates detail sharpening, clarity, texture, and dehaze.
  void updateDetail({
    double? sharpen,
    double? clarity,
    double? texture,
    double? dehaze,
  }) {
    final cur = state.currentLook.detail;
    final updated = cur.copyWith(
      sharpen: sharpen,
      clarity: clarity,
      texture: texture,
      dehaze: dehaze,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(detail: updated),
    );
  }

  /// Updates optics vignette, chromatic aberration, and lens distortion.
  void updateOptics({
    double? vignette,
    double? chromaticAberration,
    double? lensDistortion,
  }) {
    final cur = state.currentLook.optics;
    final updated = cur.copyWith(
      vignette: vignette,
      chromaticAberration: chromaticAberration,
      lensDistortion: lensDistortion,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(optics: updated),
    );
  }

  /// Updates Boost Beauty features (skin smoothing, face slim, teeth whitening).
  void updateBoostBeauty({
    bool? isEnabled,
    double? smoothSkin,
    double? evenTone,
    double? eyeBrighten,
    double? eyeEnlarge,
    double? teethWhitening,
    double? faceSlim,
    double? jawSlim,
    double? noseSlim,
    double? autoBoostLevel,
  }) {
    final cur = state.currentLook.boostBeauty;
    final updated = cur.copyWith(
      isEnabled: isEnabled,
      smoothSkin: smoothSkin,
      evenTone: evenTone,
      eyeBrighten: eyeBrighten,
      eyeEnlarge: eyeEnlarge,
      teethWhitening: teethWhitening,
      faceSlim: faceSlim,
      jawSlim: jawSlim,
      noseSlim: noseSlim,
      autoBoostLevel: autoBoostLevel,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(boostBeauty: updated),
    );
  }

  /// Updates background blur or replacement config.
  void updateBackground({
    String? mode,
    double? blurLevel,
    String? replaceUrl,
    String? colorHex,
  }) {
    final cur = state.currentLook.background;
    final updated = cur.copyWith(
      mode: mode,
      blurLevel: blurLevel,
      replaceUrl: replaceUrl,
      colorHex: colorHex,
    );
    state = state.copyWith(
      currentLook: state.currentLook.copyWith(background: updated),
    );
  }

  /// Applies a preset look with given master intensity.
  void applyPreset(OneovaLook preset, {double intensity = 1.0}) {
    state = state.copyWith(
      currentLook: preset.copyWith(intensity: intensity),
      statusMessage: 'Applied preset: ${preset.name}',
    );
  }

  /// Applies an AI grader result and updates look parameters.
  void applyAiResult(AiGradeResult result) {
    state = state.copyWith(
      currentLook: result.updatedLook,
      statusMessage: 'AI Grader: ${result.diffReport.visualDeltaSummary}',
    );
  }

  /// Resets all look parameters to the baseline neutral state.
  void resetToBaseline() {
    state = state.copyWith(
      currentLook: state.baselineLook,
      statusMessage: 'Reset to original neutral',
    );
  }

  /// Adds a list of photo file paths to the batch queue.
  void addToBatchQueue(List<String> paths) {
    final updated = {...state.batchQueue, ...paths}.toList();
    state = state.copyWith(batchQueue: updated);
  }

  /// Removes an individual item from the batch queue.
  void removeFromBatchQueue(String path) {
    final updated = state.batchQueue.where((p) => p != path).toList();
    state = state.copyWith(batchQueue: updated);
  }

  /// Clears the batch queue.
  void clearBatchQueue() {
    state = state.copyWith(batchQueue: const []);
  }

  /// Runs original-resolution export on the current active photo.
  Future<PhotoExportResult?> exportCurrentPhoto({String? destinationPath}) async {
    final photo = state.activePhoto;
    if (photo == null) return null;

    state = state.copyWith(isExporting: true, exportProgress: 0.1);
    try {
      final result = await _exportService.exportOriginalResolution(
        sourcePath: photo.path,
        look: state.currentLook,
        destinationPath: destinationPath,
      );
      state = state.copyWith(
        isExporting: false,
        exportProgress: 1.0,
        statusMessage: 'Exported ${result.outputWidth}x${result.outputHeight} photo',
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        exportProgress: 0.0,
        statusMessage: 'Export failed: $e',
      );
      rethrow;
    }
  }

  /// Executes batch grading on all queued photos.
  Future<BatchGradingReport> runBatchExport() async {
    if (state.batchQueue.isEmpty) {
      throw StateError('Batch queue is empty');
    }

    state = state.copyWith(isExporting: true, exportProgress: 0.0);

    try {
      final report = await _batchService.executeBatch(
        photoPaths: state.batchQueue,
        look: state.currentLook,
        onProgress: (update) {
          state = state.copyWith(
            exportProgress: update.fraction,
            statusMessage: 'Batch: ${update.completed}/${update.total} processed',
          );
        },
      );

      state = state.copyWith(
        isExporting: false,
        exportProgress: 1.0,
        statusMessage: 'Batch complete: ${report.successCount} succeeded, ${report.failedCount} failed',
      );
      return report;
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        statusMessage: 'Batch export error: $e',
      );
      rethrow;
    }
  }
}

final photoGradingControllerProvider =
    NotifierProvider<PhotoGradingController, PhotoGradingState>(() {
  return PhotoGradingController();
});
