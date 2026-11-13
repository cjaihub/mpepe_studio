import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../shared/audio/mic_coordinator.dart';

final audioRecorderServiceProvider = Provider<AudioRecorderService>((ref) {
  final service = AudioRecorderService();
  ref.onDispose(service.dispose);
  return service;
});

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordPath;
  DateTime? _recordingStartTime;
  MicLease? _lease;

  /// Fires when recording was stopped from outside (a call, Ova, or another
  /// app took the mic) so the composer can leave recording mode.
  void Function()? onInterrupted;

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }

  Stream<Amplitude> get onAmplitudeChanged =>
      _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 70));

  Duration get currentDuration =>
      _recordingStartTime == null ? Duration.zero : DateTime.now().difference(_recordingStartTime!);

  Future<void> startRecording() async {
    if (await hasPermission()) {
      final got = await MicCoordinator.instance.acquire(
        MicUser.voiceNote,
        onPreempted: () async {
          _lease = null;
          await cancelRecording();
          onInterrupted?.call();
        },
        onInterruption: (i) {
          if (i == MicInterruption.heldByOtherApp && _lease != null) {
            // The recording would only capture silence from here on.
            unawaited(cancelRecording().then((_) => onInterrupted?.call()));
          }
        },
      );
      if (got is MicBusy) throw Exception(got.message);
      _lease = got as MicLease;
      try {
        if (await _audioRecorder.isRecording()) {
          await _audioRecorder.stop();
        }
      } catch (_) {}

      final tempDir = await getTemporaryDirectory();
      _currentRecordPath = '${tempDir.path}/voice_message_${const Uuid().v4()}.m4a';
      _recordingStartTime = DateTime.now();

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _audioRecorder.start(
        config,
        path: _currentRecordPath!,
      );
    } else {
      throw Exception('Microphone permission denied');
    }
  }

  Future<File?> stopRecording() async {
    _recordingStartTime = null;
    String? path;
    try {
      path = await _audioRecorder.stop();
    } finally {
      await _releaseLease();
    }
    if (path != null) {
      return File(path);
    }
    return null;
  }

  Future<void> cancelRecording() async {
    _recordingStartTime = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    await _releaseLease();
    if (_currentRecordPath != null) {
      final file = File(_currentRecordPath!);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      _currentRecordPath = null;
    }
  }

  Future<void> _releaseLease() async {
    final lease = _lease;
    _lease = null;
    await lease?.release();
  }

  void dispose() {
    unawaited(_releaseLease());
    _audioRecorder.dispose();
  }
}
