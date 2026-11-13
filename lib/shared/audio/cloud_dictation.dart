import 'dart:async';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Dictation that doesn't depend on the phone's speech service.
///
/// Android voice typing normally runs through the system recognizer, which
/// lives in another app (Google). When that app is missing, disabled, or
/// already busy, Oneova records the audio itself and transcribes it with
/// Gemini instead, so voice typing keeps working.
class CloudDictation {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;

  bool _recording = false;
  bool get isRecording => _recording;

  /// Starts recording.
  ///
  /// [onLevel] receives 0..1 loudness for live waveforms/orbs.
  /// When [autoStopOnSilence] is true, [onSilenceCommit] fires automatically
  /// once speech is detected and followed by [silenceWindow] of quiet (or after
  /// [maxDuration]), enabling hands-free real-time turns without the OS speech app.
  Future<bool> start({
    void Function(double level)? onLevel,
    bool autoStopOnSilence = false,
    Duration silenceWindow = const Duration(milliseconds: 1100),
    Duration maxDuration = const Duration(seconds: 22),
    VoidCallback? onSilenceCommit,
  }) async {
    if (_recording) return true;
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/dictation_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 48000,
          noiseSuppress: true,
          autoGain: true,
          echoCancel: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
          ),
        ),
        path: _path!,
      );
      _recording = true;
      if (onLevel != null || (autoStopOnSilence && onSilenceCommit != null)) {
        bool spoke = false;
        bool committed = false;
        DateTime? quietSince;
        final startedAt = DateTime.now();
        _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
          if (!_recording || committed) return;
          // dBFS (-60 quiet .. 0 loud) to 0..1.
          final level = ((a.current + 60) / 60).clamp(0.0, 1.0);
          onLevel?.call(level);
          if (autoStopOnSilence && onSilenceCommit != null) {
            final now = DateTime.now();
            if (level >= 0.34) {
              spoke = true;
              quietSince = null;
            } else if (spoke && level < 0.25) {
              quietSince ??= now;
              if (now.difference(quietSince!) >= silenceWindow) {
                committed = true;
                onSilenceCommit();
                return;
              }
            }
            if (now.difference(startedAt) >= maxDuration) {
              committed = true;
              onSilenceCommit();
            }
          }
        });
      }
      return true;
    } catch (e) {
      debugPrint('[CloudDictation] start failed: $e');
      _recording = false;
      await _ampSub?.cancel();
      _ampSub = null;
      return false;
    }
  }

  /// Stops and returns the spoken text ('' when nothing was understood).
  Future<String> stopAndTranscribe() async {
    final path = await _stop();
    if (path == null) return '';
    final file = File(path);
    try {
      if (!await file.exists() || await file.length() < 2048) return '';
      final bytes = await file.readAsBytes();
      return await _transcribe(bytes);
    } finally {
      unawaited(file.delete().then((_) {}, onError: (_) {}));
    }
  }

  /// Stops without transcribing.
  Future<void> cancel() async {
    final path = await _stop();
    if (path != null) unawaited(File(path).delete().then((_) {}, onError: (_) {}));
  }

  Future<String?> _stop() async {
    if (!_recording) return null;
    _recording = false;
    await _ampSub?.cancel();
    _ampSub = null;
    try {
      return await _recorder.stop() ?? _path;
    } catch (_) {
      return _path;
    }
  }

  static Future<String> _transcribe(Uint8List bytes) async {
    const prompt = 'Transcribe this speech exactly as spoken, in the language spoken. '
        'Return only the transcript text with natural punctuation. '
        'If there is no speech, return nothing.';
    for (final (vertex, model) in const [
      (false, 'gemini-2.5-flash'),
      (true, 'gemini-2.5-flash'),
      (false, 'gemini-2.0-flash'),
    ]) {
      try {
        final ai = vertex ? FirebaseAI.agentPlatform(location: 'us-central1') : FirebaseAI.googleAI();
        final res = await ai
            .generativeModel(model: model)
            .generateContent([
              Content.multi([TextPart(prompt), InlineDataPart('audio/mp4', bytes)]),
            ])
            .timeout(const Duration(seconds: 20));
        final text = res.text?.trim() ?? '';
        if (text.isNotEmpty) return text;
        return '';
      } catch (e) {
        debugPrint('[CloudDictation] $model failed: $e');
      }
    }
    throw StateError('Transcription unavailable');
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}

